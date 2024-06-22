# Lua Module in Zig

This example builds a simple Zig library as a Lua module that can be loaded from a Lua script.
Specifically, it targets Lua 5.1, which is binary compatible with the version of LuaJIT built into
Neovim these days.

## Prerequisites

- Lua/luajit 5.1 (`sudo apt install luajit libluajit-5.1-dev`)
- Zig 0.12

## Build

`zig build`

## Test

To test: `luajit test.lua`

## Extending to Real Projects

See `test.lua` for how to add a directory to Lua's .so search path.

To use a build library in Neovim, simply place it in an existing directory in `package.cpath`, or
put it in the same folder as you Neovim Lua config files and do: `require('zig_mod')`.

**NOTE**: The name name of the generated library (e.g. `zig_mod.so`) must match the library name
string passed to `c.luaL_register(..., "zig_mod", ...)`, which must also match the name of your
export `luaopen_zig_mod()` function. If any of them do not match, you won't be able to load your
library.
