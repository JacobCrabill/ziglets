const builtin = @import("builtin");
const std = @import("std");

const CFlags = &[_][]const u8{"-fPIC"};

pub fn build(b: *std.Build) !void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var env_map: std.process.EnvMap = try std.process.getEnvMap(alloc);
    defer env_map.deinit();

    // Setup our standard library & include paths
    const HOME = env_map.get("HOME") orelse "";

    const lib_path: []const u8 = try std.mem.concat(alloc, u8, &.{ HOME, "/.local/lib/" });
    const include_path: []const u8 = try std.mem.concat(alloc, u8, &.{ HOME, "/.local/include/" });
    defer alloc.free(lib_path);
    defer alloc.free(include_path);

    ////////////////////////////////////////////////////////////////////////////
    // Example application using tree-sitter-markdown
    ////////////////////////////////////////////////////////////////////////////

    const exe = b.addExecutable(.{
        .name = "test-md-parser",
        .root_source_file = .{ .path = "test-md-parser.zig" },
        .version = .{ .major = 0, .minor = 1, .patch = 0 },
        .optimize = optimize,
        .target = target,
        .link_libc = true,
    });
    exe.addIncludePath(.{ .path = include_path });
    exe.addRPath(.{ .path = lib_path });
    exe.addLibraryPath(.{ .path = lib_path });
    exe.linkSystemLibrary("tree-sitter");
    exe.linkSystemLibrary("tree-sitter-markdown");
    exe.linkSystemLibrary("tree-sitter-markdown-inline");
    b.installArtifact(exe);

    // Configure how the main executable should be run
    const exe_runner = b.addRunArtifact(exe);
    exe_runner.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        exe_runner.addArgs(args);
    }

    // Run the application
    const run = b.step("run", "Run the test application");
    run.dependOn(&exe_runner.step);
}
