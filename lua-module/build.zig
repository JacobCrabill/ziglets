const std = @import("std");

const Build = std.Build;
const Step = std.Build.Step;

pub fn build(b: *Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Build export-module as a shared library for running via Lua
    const zig_mod = b.addSharedLibrary(.{
        .name = "zig_mod",
        .root_source_file = b.path("export-module.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Point the compiler to the location of the Lua headers (lua.h and friends)
    // Note that we require Lua 5.1, specifically
    // This is compatible with the version of LuaJIT built into NeoVim
    zig_mod.addIncludePath(.{ .path = "/usr/include/luajit-2.1" });
    zig_mod.linkSystemLibrary("lua5.1");

    // "Install" to the output dir using the correct naming convention to load with lua
    // const copy_step = b.addInstallFileWithDir(zig_mod.getEmittedBin(), .lib, "zig_mod.so");
    const copy_step = b.addInstallFileWithDir(zig_mod.getEmittedBin(), .lib, "zig_mod.so");
    copy_step.step.dependOn(&zig_mod.step);
    b.getInstallStep().dependOn(&copy_step.step);
}
