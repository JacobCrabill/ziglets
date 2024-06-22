//! Registering a Zig function to be called from Lua
//! This creates a shared library that can be imported from a Lua program, e.g.:
//! > mylib = require('zig-mod')
//! > print( mylib.adder(40, 2) )
//! 42

// The code here is specific to Lua 5.1
// This has been tested with LuaJIT 5.1, specifically
pub const c = @cImport({
    @cInclude("luaconf.h");
    @cInclude("lua.h");
    @cInclude("lualib.h");
    @cInclude("lauxlib.h");
});

// It can be convenient to store a short reference to the Lua struct when
// it is used multiple times throughout a file.
const LuaState = c.lua_State;
const FnReg = c.luaL_Reg;

/// A Zig function called by Lua must accept a single ?*LuaState parameter and must
/// return a c_int representing the number of return values pushed onto the stack
export fn adder(lua: ?*LuaState) callconv(.C) c_int {
    const a = c.lua_tointeger(lua, 1);
    const b = c.lua_tointeger(lua, 2);
    c.lua_pushinteger(lua, a + b);
    return 1;
}

/// I reccommend using ZLS (the Zig language server) for autocompletion to help
/// find relevant Lua function calls like pushstring, tostring, etc.
export fn hello(lua: ?*LuaState) callconv(.C) c_int {
    c.lua_pushstring(lua, "Hello, World!");
    return 1;
}

/// Function registration struct for the 'adder' function
const adder_reg: FnReg = .{ .name = "adder", .func = adder };
const hello_reg: FnReg = .{ .name = "hello", .func = hello };

/// The list of function registrations for our library
/// Note that the last entry must be empty/null as a sentinel value to the luaL_register function
const lib_fn_reg = [_]FnReg{ adder_reg, hello_reg, FnReg{} };

/// Register the function with Lua using the special luaopen_x function
/// This is the entrypoint into the library from a Lua script
export fn luaopen_zig_mod(lua: ?*LuaState) callconv(.C) c_int {
    c.luaL_register(lua.?, "zig_mod", @ptrCast(&lib_fn_reg[0]));
    return 1;
}
