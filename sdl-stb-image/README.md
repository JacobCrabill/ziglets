# Zig SDL + STB Image Demo

Uses the `stb_image` library to load an image, and `SDL.zig` to display that image

## Usage

Requires Zig v0.11

`zig build run -- ../assets/zig-zero.png`

## Dependencies (build.zig.zon + submodules)

- [**zig-stb-image**](https://github.com/JacobCrabill/zig-stb-image)
  - Repackaged for Zig from [**STB**](https://github.com/nothings/stb)
- [**SDL.zig**](https://github.com/MasterQ32/SDL.zig)
