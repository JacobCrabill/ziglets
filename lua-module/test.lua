-- For luajit 2.1.0 (Based on Lua 5.1)
package.cpath = package.cpath .. ';./zig-out/lib/?.so'
local mylib = require('zig_mod')

print(mylib.adder(40, 2))
print(mylib.hello())
