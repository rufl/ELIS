# Third-Party Notices

ELIS source is licensed under the top-level [MIT License](LICENSE), except for material explicitly identified below or inside its own directory.

## Lupinho

ELIS is a compatible Zig port of [lupi-org-br/lupinho](https://github.com/lupi-org-br/lupinho), pinned for compatibility work at revision `379a599d5e93db8228e2b0d4348ea65fcafa2ac5`. Substantial compatible behavior, API naming, and reference data—including the canonical font—derive from that MIT-licensed project.

> MIT License
>
> Copyright (c) 2026 Marcelo Marcinio Pereira Junior
>
> Permission is hereby granted, free of charge, to any person obtaining a copy
> of this software and associated documentation files (the "Software"), to deal
> in the Software without restriction, including without limitation the rights
> to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
> copies of the Software, and to permit persons to whom the Software is
> furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in all
> copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
> IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
> FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
> AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
> LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
> OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
> SOFTWARE.

## Native libraries

ELIS dynamically links libraries supplied by the operating system. Source distributions do not bundle them.

| Library | Use | Upstream license |
|---|---|---|
| SDL2 / sdl2-compat | Window, renderer, input, controllers, audio | zlib |
| Lua 5.4 | Cartridge runtime and codec execution | MIT |
| libzip | `.lupi` ZIP archive reading | BSD-3-Clause |
| libcurl | HTTPS demo acquisition | curl license (MIT-style) |
| libsndfile | Music decoding | LGPL-2.1-or-later |

Binary distributors are responsible for satisfying the exact licenses of the library versions they ship. ELIS uses dynamic linking and does not vendor modified copies of these libraries.

## lupi-codec

Automatic source-demo conversion downloads the pinned `lupi-codec` revision `3e8c66299a4606b36b9f490212acc44e084a6aa2` at runtime. The codec is not vendored into this repository. Its own repository and license remain authoritative.

## Mr. Rescue: Lupi Edition

`demos/mr-rescue/` is a separately licensed physical-validation cartridge and is not covered solely by the ELIS MIT License.

- Port code follows the upstream zlib terms preserved in `demos/mr-rescue/LICENSE.upstream`.
- Converted graphics, music, text, and adapted map data are CC-BY-SA-3.0; the legal text is in `demos/mr-rescue/CC-BY-SA-3.0.txt`.
- Complete attribution, source revision, copied-versus-reimplemented boundaries, and conversion details are in `demos/mr-rescue/SOURCE.md`.
- ELIS-owned audit and conversion tools remain MIT.

## Contributor Covenant

`CODE_OF_CONDUCT.md` is adapted from Contributor Covenant 2.1 and remains available under CC-BY-4.0. Its attribution is preserved in that file.

## Downloaded demos and future ports

Catalog demos are downloaded from their upstream repositories and are ignored by Git. Their upstream licenses govern them. Future ports must retain isolated license and attribution files as described in [CONTRIBUTING.md](CONTRIBUTING.md).
