# Mazestein 3D port

This is an engine-compatible port of [NOIST1611/Mazestein3D](https://github.com/NOIST1611/Mazestein3D).
The original is a textureless, component-based Lua raycasting prototype for Retro Gadgets. This port
keeps that scope and adapts its map, FOV, wall shading, movement, collision, and raycast concepts to
ELIS's Lua `ui.*` API.

Run it with:

```sh
zig build
zig-out/bin/elis mazestein3d
```

Controls: `W/S` move forward/backward; `A/D` turn. The renderer is intentionally bounded to 120
four-pixel columns, a 15×15 map, an indexed 256-color framebuffer, and no external textures or
unbounded allocations. This matches the source project's documented v0.1 limitation that textures
and entities were not yet implemented.
