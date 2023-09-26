const std = @import("std");
const SDL = @import("thirdparty/SDL.zig/Sdk.zig");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const std_build_opts = .{
        .target = target,
        .optimize = optimize,
    };

    // The SDL.zig package is not compatible with the Zig package manager, and must
    // be included as a submodule b/c its functions must be used at build time
    const sdk = SDL.init(b, null);

    // Declare dependencies from build.zig.zon
    const stbi = b.dependency("stbi", std_build_opts);
    const stb_lib = stbi.artifact("stb-image");

    const main_exe = b.addExecutable(.{
        .name = "test-main",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    // To use a dependency as a module in your projects, you must add it like so
    main_exe.addModule("stb_image", stbi.module("stb_image"));
    main_exe.addModule("sdl2", sdk.getWrapperModule());

    // The STB Image package requires linking to the stb_image lib it produces
    main_exe.linkLibrary(stb_lib);
    main_exe.linkLibC();

    // The SDL SDK hides all the libs and options it requires in its 'link' function
    sdk.link(main_exe, .dynamic);

    b.installArtifact(main_exe);

    const run = b.addRunArtifact(main_exe);
    if (b.args) |args| {
        run.addArgs(args);
    }
    const run_step = b.step("run", "Run the demo");
    run_step.dependOn(&run.step);
}
