#!/usr/bin/env python3
"""Package existing ELIS binaries without building or uploading.

Run on Ubuntu 24.04 x86_64 or in an MSYS2 UCRT64 shell, respectively:
  python3 scripts/package_release.py --platform linux-x86_64 --version 0.1.0-rc.1 --output dist
  python3 scripts/package_release.py --platform windows-x86_64 --version 0.1.0-rc.1 --output dist

Output: elis-VERSION-PLATFORM.tar.gz/.zip, its .manifest.json, and SHA256SUMS.
Archives have one equally named root directory. Inputs are zig-out/bin/elis
and elis-studio (with .exe on Windows). SOURCE_DATE_EPOCH, if set, controls
archive timestamps; otherwise the source commit timestamp is used. Identical
inputs and packaging environment produce identical archives.
Windows downloads exact-version MSYS2 corresponding-source archives over HTTPS
for the libraries it ships; no other downloads or uploads are performed.
"""

import argparse
import datetime
import gzip
import hashlib
import io
import json
import os
import html
from pathlib import Path
import platform
import re
import shutil
import struct
import subprocess
import sys
import tarfile
import tempfile
import zipfile


import urllib.parse
import urllib.request


ROOT = Path(__file__).resolve().parent.parent
SEMVER = re.compile(
    r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"
    r"(?:-((?:0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)"
    r"(?:\.(?:0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*))*))?"
    r"(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?"
)
# Only Windows OS components are exempt from redistributing DLLs. In
# particular libwinpthread, GCC runtimes, OpenSSL and zlib are NOT system DLLs.
SYSTEM_DLLS = frozenset("""
advapi32.dll avrt.dll bcrypt.dll bcryptprimitives.dll cabinet.dll cfgmgr32.dll
combase.dll comctl32.dll comdlg32.dll crypt32.dll cryptbase.dll cryptsp.dll
d3d9.dll d3d11.dll d3d12.dll dcomp.dll dinput8.dll dnsapi.dll dsound.dll
dwmapi.dll dxgi.dll gdi32.dll gdi32full.dll hid.dll imm32.dll iphlpapi.dll
kernel32.dll kernelbase.dll mf.dll mfplat.dll mfreadwrite.dll mfuuid.dll
mmdevapi.dll mpr.dll msacm32.dll msvcrt.dll mswsock.dll ncrypt.dll netapi32.dll
normaliz.dll ntdll.dll ole32.dll oleacc.dll oleaut32.dll opengl32.dll
powrprof.dll propsys.dll psapi.dll rpcrt4.dll secur32.dll setupapi.dll
shell32.dll shlwapi.dll sspicli.dll ucrtbase.dll user32.dll userenv.dll
usp10.dll uxtheme.dll version.dll win32u.dll windowscodecs.dll winhttp.dll
wininet.dll winmm.dll winspool.drv wintrust.dll wldap32.dll ws2_32.dll
wtsapi32.dll xinput1_4.dll
""".split())
UBUNTU_PACKAGES = [
    "libc6", "libgcc-s1", "libstdc++6", "libsdl2-2.0-0", "liblua5.4-0",
    "libzip4t64", "libcurl4t64", "libsndfile1", "ca-certificates",
]
# Explicit allowlist: never recursively copy a developer checkout, demo tree,
# downloads, caches, or an unapproved cartridge into a binary distribution.
SOURCE_FILES = (
    "example/game.lua", "mazestein3d/game.lua", "mazestein3d/README.md",
    "LICENSE", "THIRD_PARTY_NOTICES.md", "LICENSES/MIT.txt",
    "LICENSES/Zlib.txt", "LICENSES/CC-BY-SA-3.0.txt", "LICENSES/CC-BY-4.0.txt",
)


def command(*args):
    result = subprocess.run(
        args, cwd=ROOT, env={**os.environ, "LC_ALL": "C", "LANG": "C"},
        text=True, encoding="utf-8", stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False,
    )
    if result.returncode:
        raise RuntimeError(f"{args[0]} failed ({result.returncode}): {result.stderr.strip()}")
    return result.stdout


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def safe_file(path):
    if path.is_symlink() or not path.is_file():
        raise RuntimeError(f"Required regular, non-symlink file missing: {path}")
    return path.read_bytes()


def verify_binary(data, windows, name):
    if windows:
        if len(data) < 64 or data[:2] != b"MZ":
            raise RuntimeError(f"Not a Windows executable: {name}")
        offset = struct.unpack_from("<I", data, 60)[0]
        if offset + 26 > len(data) or data[offset:offset + 4] != b"PE\0\0":
            raise RuntimeError(f"Invalid PE header: {name}")
        machine = struct.unpack_from("<H", data, offset + 4)[0]
        magic = struct.unpack_from("<H", data, offset + 24)[0]
        if machine != 0x8664 or magic != 0x20B:
            raise RuntimeError(f"Not a Windows x86_64 PE32+ binary: {name}")
    elif (len(data) < 20 or data[:6] != b"\x7fELF\x02\x01"
          or struct.unpack_from("<H", data, 18)[0] != 62):
        raise RuntimeError(f"Not a Linux x86_64 ELF binary: {name}")


def msys_path(path):
    # pacman's file database uses POSIX paths, even with native Windows Python.
    if os.name == "nt" and str(path).startswith("/"):
        return Path(command("cygpath", "-w", str(path)).strip())
    return Path(path)


def compatible_library_license(expression, owner, version):
    # Evaluate SPDX alternatives rather than rejecting a usable LGPL branch.
    # Unknown/custom licenses require an explicit review, never a guess.
    # MSYS2 labels this reviewed permissive bzip2 release merely "custom".
    # Its exact upstream license is retained with the binary and source package:
    # https://sourceware.org/git/?p=bzip2.git;a=blob_plain;f=LICENSE;hb=bzip2-1.0.8
    if (owner == "mingw-w64-ucrt-x86_64-bzip2" and version == "1.0.8-4"
            and expression == "custom"):
        return
    # Reviewed legacy metadata, not blanket acceptance of unknown licenses.
    # LAME's COPYING is the GNU Library GPL v2; Vorbis uses BSD-3-Clause:
    # https://github.com/rbrito/lame/blob/master/COPYING
    # https://github.com/xiph/vorbis/blob/v1.3.7/COPYING
    legacy_licenses = {
        ("mingw-w64-ucrt-x86_64-lame", "3.100-3", "LGPL"),
        ("mingw-w64-ucrt-x86_64-libvorbis", "1.3.7-3", "custom"),
    }
    if (owner, version, expression) in legacy_licenses:
        return
    allowed = {
        "MIT", "BSD-2-Clause", "BSD-3-Clause", "BSD-4-Clause", "0BSD", "ISC",
        "Zlib", "curl", "Apache-2.0", "BSL-1.0", "Unlicense", "CC0-1.0",
        "LGPL-2.0-only", "LGPL-2.0-or-later", "LGPL-2.1-only",
        "LGPL-2.1-or-later", "LGPL-3.0-only", "LGPL-3.0-or-later",
        "Unicode-3.0", "Unicode-DFS-2016", "MPL-2.0",
    }
    tokens = re.findall(r"\(|\)|[^\s()]+", expression.replace("spdx:", ""))
    position = 0

    def atom():
        nonlocal position
        if position >= len(tokens):
            raise RuntimeError(f"Incomplete license expression for {owner}: {expression}")
        token = tokens[position]
        position += 1
        if token == "(":
            result = alternatives()
            if position >= len(tokens) or tokens[position] != ")":
                raise RuntimeError(f"Unbalanced license expression for {owner}: {expression}")
            position += 1
            return result
        if token in ("AND", "OR", "WITH", ")"):
            raise RuntimeError(f"Invalid license expression for {owner}: {expression}")
        if position < len(tokens) and tokens[position] == "WITH":
            position += 1
            if position >= len(tokens):
                raise RuntimeError(f"Missing license exception for {owner}")
            exception = tokens[position]
            position += 1
            return (owner == "mingw-w64-ucrt-x86_64-gcc-libs"
                    and token == "GPL-3.0-or-later" and exception == "GCC-exception-3.1")
        return token in allowed

    def conjunction():
        nonlocal position
        result = atom()
        # Older pacman metadata lists multiple licenses separated by spaces.
        while position < len(tokens) and tokens[position] not in ("OR", ")"):
            if tokens[position] == "AND":
                position += 1
            right = atom()
            result = result and right
        return result

    def alternatives():
        nonlocal position
        result = conjunction()
        while position < len(tokens) and tokens[position] == "OR":
            position += 1
            right = conjunction()
            result = result or right
        return result

    result = alternatives()
    if position != len(tokens) or not result:
        raise RuntimeError(
            f"Unreviewed or incompatible DLL license for {owner}: {expression}. "
            "GPL/AGPL without a reviewed linking exception is not approved for this MIT bundle."
        )


class SourceRedirectHandler(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, message, headers, newurl):
        parsed = urllib.parse.urlsplit(newurl)
        previous = urllib.parse.urlsplit(request.full_url)
        # MSYS2's authoritative mirror service selects external HTTPS mirrors.
        # Permit that delegation only for the same exact source archive name.
        source_mirror = (previous.path.endswith(".src.tar.zst")
                         and parsed.path.rsplit("/", 1)[-1] == previous.path.rsplit("/", 1)[-1])
        if (parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password
                or parsed.port not in (None, 443)
                or (not source_mirror and parsed.hostname != "packages.msys2.org")):
            raise RuntimeError(f"Refusing unsafe source redirect: {newurl}")
        return super().redirect_request(request, fp, code, message, headers, newurl)


def validate_source_url(url):
    parsed = urllib.parse.urlsplit(url)
    if (parsed.scheme != "https" or parsed.hostname not in ("packages.msys2.org", "mirror.msys2.org")
            or parsed.username or parsed.password or parsed.port not in (None, 443)):
        raise RuntimeError(f"Refusing non-MSYS2 HTTPS source URL: {url}")


def fetch_source_bytes(url, maximum):
    validate_source_url(url)
    request = urllib.request.Request(url, headers={"User-Agent": "ELIS-release-packager"})
    with urllib.request.build_opener(SourceRedirectHandler()).open(request, timeout=120) as response:
        data = response.read(maximum + 1)
    if len(data) > maximum:
        raise RuntimeError(f"Source download exceeds size limit: {url}")
    return data


def source_license_texts(archive, prefix=""):
    """Retain upstream legal texts when binary packages omit share/licenses."""
    texts = {}
    for member in archive:
        if not member.isfile():
            continue
        name = member.name.replace("\\", "/")
        if name.startswith("/") or any(part in ("", ".", "..") for part in name.split("/")):
            raise RuntimeError(f"Unsafe source license path: {name}")
        basename = name.rsplit("/", 1)[-1].upper()
        if re.fullmatch(r"(?:COPYING|COPYRIGHT|LICENSE|LICENCE|NOTICE)(?:[._-].*)?", basename):
            if member.size > 4 * 1024 * 1024 or len(texts) >= 4096:
                raise RuntimeError("Source license collection exceeds bounds")
            with archive.extractfile(member) as stream:
                data = stream.read()
            if data.strip():
                texts[prefix + name] = data
    return texts


def corresponding_source(package):
    owner = package["name"]
    compatible_library_license(package["licenses"], owner, package["version"])
    page_url = package["package_information"]
    page = fetch_source_bytes(page_url, 4 * 1024 * 1024).decode("utf-8")
    match = re.search(r'Source-Only Tarball:</dt>\s*<dd[^>]*>\s*<a href="([^"]+)"', page)
    if not match:
        raise RuntimeError(f"MSYS2 has no corresponding-source tarball for {owner}")
    url = html.unescape(match[1])
    match = re.fullmatch(r"https://mirror\.msys2\.org/mingw/sources/(mingw-w64-[A-Za-z0-9_.+-]+\.src\.tar\.zst)", url)
    if not match:
        raise RuntimeError(f"Unexpected MSYS2 source tarball URL: {url}")
    filename = match[1]
    data = fetch_source_bytes(url, 512 * 1024 * 1024)
    if not shutil.which("zstd"):
        raise RuntimeError("Inspecting MSYS2 source archives requires zstd")
    with tempfile.TemporaryDirectory(prefix="elis-sources-") as temporary:
        compressed = Path(temporary) / "source.tar.zst"
        unpacked = Path(temporary) / "source.tar"
        compressed.write_bytes(data)
        with unpacked.open("wb") as stream:
            result = subprocess.run(["zstd", "-dc", str(compressed)], stdout=stream, stderr=subprocess.PIPE)
        if result.returncode:
            raise RuntimeError(f"Invalid source compression for {owner}: {result.stderr.decode(errors='replace')}")
        with tarfile.open(unpacked, "r:") as archive:
            members = {}
            for member in archive:
                parts = member.name.rstrip("/").split("/")
                if (member.name.startswith("/") or "\\" in member.name
                        or any(part in ("", ".", "..") for part in parts)
                        or not (member.isfile() or member.isdir())):
                    raise RuntimeError(f"Unsafe source archive member for {owner}: {member.name}")
                if member.name in members:
                    raise RuntimeError(f"Duplicate source archive member for {owner}: {member.name}")
                members[member.name] = member
            infos = [name for name in members if name.endswith("/.SRCINFO") and name.count("/") == 1]
            if len(infos) != 1:
                raise RuntimeError(f"Missing unambiguous .SRCINFO in {filename}")
            info_name = infos[0]
            if members[info_name].size > 1024 * 1024:
                raise RuntimeError(f"Oversized .SRCINFO in {filename}")
            with archive.extractfile(members[info_name]) as stream:
                info_bytes = stream.read()
            metadata = {}
            for line in info_bytes.decode("utf-8").splitlines():
                if " = " in line:
                    key, value = line.strip().split(" = ", 1)
                    metadata.setdefault(key, []).append(value)
            base = metadata.get("pkgbase", [""])[0]
            version = metadata.get("pkgver", [""])[0] + "-" + metadata.get("pkgrel", [""])[0]
            if metadata.get("epoch", ["0"])[0] != "0":
                version = metadata["epoch"][0] + ":" + version
            source_root = info_name.rsplit("/", 1)[0]
            recipe = members.get(f"{base}/PKGBUILD")
            if (version != package["version"] or base != source_root
                    or filename != f"{base}-{version.split(':')[-1]}.src.tar.zst"
                    or recipe is None or not recipe.isfile() or recipe.size == 0):
                raise RuntimeError(f"Corresponding-source version/recipe mismatch: {owner} {package['version']} vs {base} {version}")
            sources = []
            checksum_algorithms = {"md5sums": "md5", "sha1sums": "sha1", "sha224sums": "sha224",
                                   "sha256sums": "sha256", "sha384sums": "sha384",
                                   "sha512sums": "sha512", "b2sums": "blake2b"}
            for key, values in metadata.items():
                if key != "source" and not key.startswith("source_"):
                    continue
                for index, source in enumerate(values):
                    if "::" in source:
                        source_name = source.split("::", 1)[0]
                    else:
                        source_name = urllib.parse.urlsplit(source).path.rsplit("/", 1)[-1]
                        if source.startswith("git+"):
                            source_name = source_name.removesuffix(".git")
                    if not source_name or "/" in source_name or "\\" in source_name or source_name in (".", ".."):
                        raise RuntimeError(f"Unsafe source filename in {filename}: {source}")
                    source_path = f"{base}/{source_name}"
                    member = members.get(source_path)
                    if member is None:
                        raise RuntimeError(f"Incomplete corresponding source for {owner}: missing {source_name}")
                    if member.isdir() and not any(
                            name.startswith(source_path + "/") and item.isfile()
                            for name, item in members.items()):
                        raise RuntimeError(f"Empty VCS corresponding source for {owner}: {source_name}")
                    checksums = {}
                    for checksum_key, algorithm in checksum_algorithms.items():
                        values_key = checksum_key + key[len("source"):]
                        expected = metadata.get(values_key)
                        if expected is None:
                            continue
                        if len(expected) != len(values):
                            raise RuntimeError(f"Source checksum count mismatch in {filename}: {values_key}")
                        if expected[index] == "SKIP":
                            continue
                        if not member.isfile():
                            raise RuntimeError(f"Source checksum refers to non-file: {source_path}")
                        digest = hashlib.new(algorithm)
                        with archive.extractfile(member) as stream:
                            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                                digest.update(chunk)
                        if digest.hexdigest() != expected[index].lower():
                            raise RuntimeError(f"Source checksum mismatch for {owner}: {source_name}")
                        checksums[algorithm] = digest.hexdigest()
                    sources.append({"source": source, "archive_member": source_path, "checksums": checksums})
            if not sources:
                raise RuntimeError(f"No upstream sources in {filename}")
            license_texts = {}
            if not package["license_files"]:
                license_texts.update(source_license_texts(archive))
                for entry in sources:
                    member = members[entry["archive_member"]]
                    if member.isfile() and re.search(r"\.tar\.(?:gz|bz2|xz)$|\.tgz$", member.name):
                        with archive.extractfile(member) as stream:
                            with tarfile.open(fileobj=stream, mode="r|*") as upstream:
                                license_texts.update(source_license_texts(upstream, member.name + "/"))
                if not license_texts:
                    raise RuntimeError(f"No upstream license texts in corresponding sources for {owner}")
    return data, {
        "file": f"SOURCES/{filename}", "url": url, "sha256": sha256(data),
        "package_base": base, "version": version, "metadata_url": page_url,
        "srcinfo_sha256": sha256(info_bytes), "upstream_sources": sources,
    }, license_texts


def windows_libraries(binaries, files):
    objdump = shutil.which("objdump")
    if not objdump or not shutil.which("pacman"):
        raise RuntimeError("Windows packaging requires objdump and pacman in MSYS2 UCRT64")
    directories = [ROOT / "zig-out/bin"]
    directories.extend(Path(p) for p in os.environ.get("PATH", "").split(os.pathsep) if p)
    candidates = {}
    for directory in directories:
        if directory.is_dir():
            for path in sorted(directory.iterdir()):
                if path.is_file() and path.suffix.lower() == ".dll":
                    candidates.setdefault(path.name.lower(), path)

    packages = {}
    libraries = []
    system_imports = set()
    import_graph = {}
    pending = list(binaries)
    visited = set()
    while pending:
        path = pending.pop(0)
        key = path.name.lower()
        if key in visited:
            continue
        visited.add(key)
        verify_binary(safe_file(path), True, path.name)
        table = command(objdump, "-p", str(path))
        imports = sorted(set(re.findall(r"^\s*DLL Name:\s*(\S+)\s*$", table, re.MULTILINE)), key=str.lower)
        if not imports:
            raise RuntimeError(f"No PE imports found by objdump: {path.name}")
        import_graph[path.name] = imports
        for name in imports:
            if not re.fullmatch(r"[A-Za-z0-9_.+-]+\.(?:dll|drv)", name, re.IGNORECASE):
                raise RuntimeError(f"Unsafe DLL import name: {name!r}")
            lower = name.lower()
            if lower in SYSTEM_DLLS or re.fullmatch(r"(?:api|ext)-ms-win-[a-z0-9-]+\.dll", lower):
                system_imports.add(lower)
                continue
            if lower in visited or any(p.name.lower() == lower for p in pending):
                continue
            dependency = candidates.get(lower)
            if dependency is None:
                raise RuntimeError(f"Missing non-system DLL {name}, imported by {path.name}")
            data = safe_file(dependency)
            verify_binary(data, True, name)
            owner_path = command("cygpath", "-u", str(dependency)).strip() if os.name == "nt" else str(dependency)
            owners = command("pacman", "-Qqo", owner_path).splitlines()
            if len(owners) != 1 or not owners[0].startswith("mingw-w64-ucrt-x86_64-"):
                raise RuntimeError(f"DLL is not owned by one MSYS2 UCRT64 package: {dependency}")
            owner = owners[0]
            if owner not in packages:
                metadata = command("pacman", "-Qi", owner)
                fields = {}
                active_key = None
                for line in metadata.splitlines():
                    match = re.match(r"^([A-Za-z ]+?)\s*:\s*(.*)$", line)
                    if match:
                        key = match[1].strip().lower()
                        active_key = key if key in ("name", "version", "url", "licenses") else None
                        if active_key:
                            fields[active_key] = match[2]
                    elif active_key and line[:1].isspace():
                        fields[active_key] += " " + line.strip()
                if (fields.get("name") != owner or not fields.get("version")
                        or fields.get("licenses", "None") == "None"):
                    raise RuntimeError(f"Missing package name/version/license metadata: {owner}")
                license_paths = []
                for line in command("pacman", "-Ql", owner).splitlines():
                    prefix = owner + " "
                    if not line.startswith(prefix):
                        raise RuntimeError(f"Unexpected pacman file record: {line}")
                    filename = line[len(prefix):]
                    if "/share/licenses/" not in filename or filename.endswith("/"):
                        continue
                    source = msys_path(filename)
                    if not source.is_file():
                        raise RuntimeError(f"Missing installed license text: {filename}")
                    relative = filename.split("/share/licenses/", 1)[1]
                    if any(part in ("", ".", "..") for part in relative.split("/")):
                        raise RuntimeError(f"Unsafe package license path: {filename}")
                    destination = f"LICENSES/msys2/{owner}/{relative}"
                    license_data = source.read_bytes()
                    if not license_data.strip():
                        raise RuntimeError(f"Empty installed license text: {filename}")
                    files[destination] = (license_data, 0o644)
                    license_paths.append(destination)
                fields["license_files"] = sorted(license_paths)
                fields["distribution"] = "MSYS2 UCRT64"
                fields["package_information"] = f"https://packages.msys2.org/package/{owner}"
                packages[owner] = fields
            files[name] = (data, 0o755)
            libraries.append({"file": name, "sha256": sha256(data), "package": owner})
            pending.append(dependency)
    return {
        "shipped_libraries": sorted(libraries, key=lambda item: item["file"].lower()),
        "library_packages": [packages[key] for key in sorted(packages)],
        "system_dll_imports": sorted(system_imports),
        "dll_imports": dict(sorted(import_graph.items())),
    }


def linux_libraries(binaries):
    release = {}
    for line in Path("/etc/os-release").read_text().splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            release[key] = value.strip('"')
    if release.get("ID") != "ubuntu" or release.get("VERSION_ID") != "24.04" or platform.machine() != "x86_64":
        raise RuntimeError("Linux release packaging must run on Ubuntu 24.04 x86_64; this is not a portable Linux bundle")
    libraries = {}
    for binary in binaries:
        # These are locally built release inputs, not arbitrary downloaded ELF
        # files. ldd resolves their complete host dynamic dependency closure.
        output = command("ldd", str(binary))
        if "not found" in output or "statically linked" in output:
            raise RuntimeError(f"Unresolved or unexpected static Linux binary: {binary.name}\n{output}")
        for line in output.splitlines():
            match = re.match(r"\s*(?:(\S+)\s+=>\s+)?(/\S+)\s+\(0x[0-9a-fA-F]+\)", line)
            if not match:
                if line.strip().startswith("linux-vdso.so."):
                    continue
                raise RuntimeError(f"Unrecognized ldd dependency: {line}")
            path = Path(match[2])
            name = match[1] or path.name
            if name in libraries:
                continue
            # Ubuntu's usrmerge database may record either /lib or /usr/lib.
            paths = [str(path), str(path.resolve())]
            if str(path).startswith("/usr/"):
                paths.append(str(path)[4:])
            else:
                paths.append("/usr" + str(path))
            owner = None
            for candidate in dict.fromkeys(paths):
                try:
                    result = command("dpkg-query", "-S", candidate).strip().splitlines()
                except RuntimeError:
                    continue
                if len(result) == 1 and ": " in result[0]:
                    owner = result[0].rsplit(": ", 1)[0]
                    break
            if owner is None:
                raise RuntimeError(f"Cannot identify Ubuntu package owning {name}")
            version = command("dpkg-query", "-W", "-f=${Version}", owner).strip()
            libraries[name] = {"soname": name, "package": owner, "version": version,
                               "sha256": sha256(path.read_bytes()), "bundled": False}
    return {"shipped_libraries": [], "runtime_libraries": [libraries[key] for key in sorted(libraries)],
            "runtime_packages": UBUNTU_PACKAGES, "distribution": "Ubuntu 24.04 x86_64"}


def run_instructions(version, windows):
    common = f"""ELIS {version} — simulator and Workshop prerelease

Extract the entire archive into a writable folder. Keep both executables,
cartridges and (on Windows) DLLs together. Use the run launchers from any
working directory, or open a terminal in this extracted folder.

Included cartridges: example and mazestein3d only. Mr. Rescue is not bundled,
not hardware-approved, and is removed from the packaged demo catalog.
Catalog HTTPS entries are optional upstream downloads, not bundled games.
Downloads and source conversion can require additional tools and network
access; this archive does not include downloaded games or lupi-codec.
Simulator results are not physical Lupi hardware certification.

LICENSE and THIRD_PARTY_NOTICES.md retain project and upstream attribution.
The notices describe source-only content too; their Mr. Rescue and Contributor
Covenant sections do not imply those works are in this binary bundle.
manifest.json records source commit, payload checksums and library provenance.
The manifest does not hash itself. Adjacent SHA256SUMS covers the archive and
external manifest. Archive timestamps are normalized, not build timestamps.
"""
    if windows:
        return common + """
Platform: Windows 10 version 1903 or newer / Windows 11 x86_64, UCRT.
No MSYS2 installation or compiler is needed to run it. Non-system imported
DLLs are bundled recursively; Windows supplies OS/API-set DLLs. A working
display/audio driver is needed for interactive use.

Double-click run-elis.cmd or run-workshop.cmd. PowerShell alternatives:
  .\\elis.exe example
  .\\elis.exe mazestein3d
  .\\elis-studio.exe

Optional source-demo conversion requires MSYS2 Bash/coreutils plus
mingw-w64-ucrt-x86_64-imagemagick (ImageMagick 7). ELIS_CODEC_BASH selects
bash.exe when it is not at C:/msys64/usr/bin/bash.exe. Encoded cartridges
and the bundled examples do not require these tools.

LICENSES/msys2 retains each shipped package's installed license texts.
Library package versions, upstream URLs and license expressions are in
manifest.json. SOURCES contains the exact matching MSYS2 corresponding-source
archives, including upstream sources, build recipes and patches. Their HTTPS
origins, SHA256 hashes, .SRCINFO versions and verified upstream checksums are
recorded in manifest.json. Extract a source archive and use its PKGBUILD with
MSYS2 makepkg-mingw to rebuild the library (the recipe lists build dependencies).
These libraries are unmodified, dynamically linked and replaceable with
ABI-compatible versions. You may modify these libraries and reverse engineer
ELIS for debugging those modifications as permitted by their applicable
licenses. No restriction on these rights is imposed by this distribution.
"""
    return common + """
Platform: Ubuntu 24.04 x86_64 ONLY. This is dynamically linked, not a static
or distro-independent portable Linux release. Other distributions/releases
are unsupported. Shared libraries are NOT bundled: install Ubuntu packages
and their transitive dependencies before starting:

  sudo apt-get update
  sudo apt-get install --yes --no-install-recommends \\
    libc6 libgcc-s1 libstdc++6 libsdl2-2.0-0 liblua5.4-0 \\
    libzip4t64 libcurl4t64 libsndfile1 ca-certificates

A working graphical desktop/display server and graphics/audio drivers are
needed for interactive use. Run:
  ./run-elis.sh
  ./elis example
  ./elis mazestein3d
  ./run-workshop.sh

If a renderer is unavailable, try SDL_RENDER_DRIVER=software ./elis example.
Exact build-host runtime package versions are retained in manifest.json;
Ubuntu security updates providing compatible ABIs remain recommended.
"""


def archive_payload(path, root_name, files, windows, epoch):
    if windows:
        date = datetime.datetime.fromtimestamp(max(epoch, 315532800), datetime.timezone.utc)
        with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
            for name, (data, mode) in sorted(files.items()):
                info = zipfile.ZipInfo(f"{root_name}/{name}", date.timetuple()[:6])
                info.create_system = 3
                info.external_attr = (0o100000 | mode) << 16
                info.compress_type = zipfile.ZIP_DEFLATED
                archive.writestr(info, data, compresslevel=9)
    else:
        with path.open("wb") as raw:
            with gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=epoch, compresslevel=9) as compressed:
                with tarfile.open(fileobj=compressed, mode="w", format=tarfile.PAX_FORMAT) as archive:
                    for name, (data, mode) in sorted(files.items()):
                        info = tarfile.TarInfo(f"{root_name}/{name}")
                        info.size = len(data)
                        info.mode = mode
                        info.mtime = epoch
                        info.uid = info.gid = 0
                        info.uname = info.gname = ""
                        archive.addfile(info, io.BytesIO(data))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--platform", required=True, choices=("linux-x86_64", "windows-x86_64"))
    parser.add_argument("--version", required=True, help="SemVer without a leading v, e.g. 0.1.0-rc.1")
    parser.add_argument("--output", required=True, help="Output directory; existing release artifacts are never overwritten")
    args = parser.parse_args()
    if len(args.version) > 100 or not SEMVER.fullmatch(args.version):
        parser.error("--version must be a path-safe semantic version without a leading v")
    if (not args.output or any(ord(c) < 32 for c in args.output)
            or ".." in args.output.replace("\\", "/").split("/")):
        parser.error("--output must be a directory path without control characters or parent traversal")
    output = Path(args.output).absolute()
    if any(path.is_symlink() for path in (output, *output.parents)):
        parser.error("--output must not traverse symlinks")
    if output == ROOT or output in ROOT.parents or any(output == ROOT / name or ROOT / name in output.parents
                                                       for name in ("src", "scripts", "example", "mazestein3d", "demos", "LICENSES", ".git", "zig-out")):
        parser.error("--output must not overwrite source or build input directories")
    windows = args.platform == "windows-x86_64"
    commit = command("git", "rev-parse", "HEAD").strip()
    if not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", commit):
        raise RuntimeError("Cannot determine source commit")
    epoch_text = os.environ.get("SOURCE_DATE_EPOCH", command("git", "show", "-s", "--format=%ct", "HEAD").strip())
    if not re.fullmatch(r"[0-9]+", epoch_text) or not 0 <= int(epoch_text) <= 0xFFFFFFFF:
        raise RuntimeError("SOURCE_DATE_EPOCH must be an integer in [0, 4294967295]")
    epoch = int(epoch_text)
    files = {name: (safe_file(ROOT / name), 0o644) for name in SOURCE_FILES}
    suffix = ".exe" if windows else ""
    binaries = [ROOT / "zig-out/bin" / (name + suffix) for name in ("elis", "elis-studio")]
    for binary in binaries:
        data = safe_file(binary)
        verify_binary(data, windows, binary.name)
        files[binary.name] = (data, 0o755)
    catalog = []
    for line in safe_file(ROOT / "demos/catalog.txt").decode("utf-8").splitlines():
        if not line.strip() or line.startswith("#"):
            catalog.append(line)
            continue
        parts = line.split("|")
        if len(parts) != 2:
            raise RuntimeError(f"Malformed demo catalog entry: {line}")
        if parts[1].startswith("builtin:"):
            if parts[1] == "builtin:mazestein3d":
                catalog.append(line)
            elif parts[1] != "builtin:mr-rescue/current":
                raise RuntimeError(f"Unapproved builtin cartridge: {parts[1]}")
        elif re.fullmatch(r"https://github\.com/lupi-org-br/[A-Za-z0-9_.-]+", parts[1]):
            catalog.append(line)
        else:
            raise RuntimeError(f"Unapproved catalog source: {parts[1]}")
    files["demos/catalog.txt"] = (("\n".join(catalog) + "\n").encode(), 0o644)
    provenance = windows_libraries(binaries, files) if windows else linux_libraries(binaries)
    if windows:
        for package in provenance["library_packages"]:
            # FLAC's package metadata also covers GPL tools and FDL manuals.
            # Only its BSD-licensed codec DLLs are approved here:
            # https://github.com/xiph/flac/blob/1.5.0/README.md
            if package["name"] == "mingw-w64-ucrt-x86_64-flac":
                shipped = {
                    library["file"].lower()
                    for library in provenance["shipped_libraries"]
                    if library["package"] == package["name"]
                }
                if (package["version"] != "1.5.0-2" or not shipped
                        or not shipped <= {"libflac.dll", "libflac-14.dll", "libflac++-11.dll"}):
                    raise RuntimeError(f"Unreviewed FLAC binary selection: {shipped}")
                package["package_licenses"] = package["licenses"]
                package["licenses"] = "BSD-3-Clause"
                package["license_scope"] = "Bundled libFLAC/libFLAC++ codec DLLs only"
            # gettext's GPL command-line tools are not part of libintl.
            # https://github.com/autotools-mirror/gettext/blob/v1.0/gettext-runtime/intl/libintl.rc
            if package["name"] == "mingw-w64-ucrt-x86_64-gettext-runtime":
                shipped = {
                    library["file"].lower()
                    for library in provenance["shipped_libraries"]
                    if library["package"] == package["name"]
                }
                if package["version"] != "1.0-1" or shipped != {"libintl-8.dll"}:
                    raise RuntimeError(f"Unreviewed gettext binary selection: {shipped}")
                package["package_licenses"] = package["licenses"]
                package["licenses"] = "LGPL-2.1-or-later"
                package["license_scope"] = "Bundled libintl DLL only"
            source_data, source, source_licenses = corresponding_source(package)
            destination = source["file"]
            if destination in files and files[destination][0] != source_data:
                raise RuntimeError(f"Conflicting source archives: {destination}")
            files[destination] = (source_data, 0o644)
            package["corresponding_source"] = source
            for name, data in sorted(source_licenses.items()):
                destination = f"LICENSES/msys2/{package['name']}/sources/{name}"
                files[destination] = (data, 0o644)
                package["license_files"].append(destination)
    files["RUNNING.txt"] = (run_instructions(args.version, windows).encode(), 0o644)
    for name, executable in (("elis", "elis"), ("workshop", "elis-studio")):
        if windows:
            launcher = f'@echo off\r\nsetlocal\r\ncd /d "%~dp0"\r\n"%~dp0{executable}.exe" %*\r\nexit /b %errorlevel%\r\n'
            files[f"run-{name}.cmd"] = (launcher.encode(), 0o644)
        else:
            launcher = f'#!/bin/sh\nset -eu\ncd -- "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"\nexec "./{executable}" "$@"\n'
            files[f"run-{name}.sh"] = (launcher.encode(), 0o755)
    manifest = {
        "schema_version": 1, "project": "ELIS", "version": args.version,
        "platform": args.platform, "source_commit": commit, "source_date_epoch": epoch,
        "bundled_cartridges": ["example", "mazestein3d"], **provenance,
        "files": [{"path": name, "sha256": sha256(data), "size": len(data), "mode": oct(mode)}
                  for name, (data, mode) in sorted(files.items())],
    }
    manifest_bytes = (json.dumps(manifest, indent=2, sort_keys=True, ensure_ascii=False) + "\n").encode()
    files["manifest.json"] = (manifest_bytes, 0o644)
    root_name = f"elis-{args.version}-{args.platform}"
    archive_name = root_name + (".zip" if windows else ".tar.gz")
    manifest_name = root_name + ".manifest.json"
    output.mkdir(parents=True, exist_ok=True)
    for name in (archive_name, manifest_name):
        if (output / name).exists():
            raise RuntimeError(f"Refusing to replace release artifact: {output / name}")
    if (output / "SHA256SUMS").is_symlink():
        raise RuntimeError("SHA256SUMS must not be a symlink")
    with tempfile.TemporaryDirectory(prefix=".elis-package-", dir=output) as temp:
        staging = Path(temp)
        archive_payload(staging / archive_name, root_name, files, windows, epoch)
        (staging / manifest_name).write_bytes(manifest_bytes)
        sums = {}
        checksums = output / "SHA256SUMS"
        if checksums.exists():
            for line in checksums.read_text().splitlines():
                match = re.fullmatch(r"([0-9a-f]{64})  (elis-[A-Za-z0-9.+-]+\.(?:tar\.gz|zip|manifest\.json))", line)
                if not match or match[2] in sums:
                    raise RuntimeError("Invalid existing SHA256SUMS")
                if sha256(safe_file(output / match[2])) != match[1]:
                    raise RuntimeError(f"Existing artifact checksum mismatch: {match[2]}")
                sums[match[2]] = match[1]
        for name in (archive_name, manifest_name):
            sums[name] = sha256((staging / name).read_bytes())
        (staging / "SHA256SUMS").write_text("".join(f"{sums[name]}  {name}\n" for name in sorted(sums)), encoding="utf-8", newline="\n")
        for name in (archive_name, manifest_name, "SHA256SUMS"):
            os.replace(staging / name, output / name)
    print(output / archive_name)
    print(output / manifest_name)
    print(output / "SHA256SUMS")


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, ValueError, tarfile.TarError, subprocess.SubprocessError) as error:
        print(f"Packaging failed: {error}", file=sys.stderr)
        sys.exit(1)
