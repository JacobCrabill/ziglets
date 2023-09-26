/// Adapted from:
///   github.com/zigimg/sdl-example
const std = @import("std");
const SDL = @import("sdl2");
const stb = @import("stb_image");

const assert = std.debug.assert;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var allocator: std.mem.Allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("ERROR: Expected argument: <image file>\n", .{});
        std.debug.print("Usage:\n\t{s} <image_file>.[png,jpg,gif,...]\n", .{args[0]});
        return;
    }

    const filename = args[1];

    try SDL.init(.{ .video = true, .events = true, .audio = false });
    defer SDL.quit();

    var img = try stb.load_image(filename);

    const format = switch (img.nchan) {
        1 => "Grayscale",
        2 => "Grayscale with alpha",
        3 => "RGB",
        4 => "RGBA",
        else => "Unknown Pixel Format",
    };
    std.debug.print("Loaded image {s}; Size: {d}x{d}; Format: {s}\n", .{ filename, img.width, img.height, format });

    var window = try SDL.createWindow(
        "Example: stb_image with SDL2",
        .{ .centered = {} },
        .{ .centered = {} },
        @intCast(img.width),
        @intCast(img.height),
        .{ .vis = .shown },
    );
    defer window.destroy();

    var renderer = try SDL.createRenderer(window, null, .{});
    defer renderer.destroy();

    // Load the image into an SDL Texture
    var texture: SDL.Texture = try utils.sdlTextureFromImage(renderer, img);

    // Create a Rectangle onto which the texture will be mapped
    const dst_rect = SDL.Rectangle{ .x = 0, .y = 0, .width = @intCast(img.width), .height = @intCast(img.height) };

    try renderer.setColor(SDL.Color{ .r = 128, .g = 128, .b = 128, .a = 0 });
    try renderer.clear();

    // Render the texture onto the rectangle
    try renderer.copy(texture, null, dst_rect);

    // Display the result
    renderer.present();

    mainloop: while (true) {
        while (SDL.pollEvent()) |ev| {
            switch (ev) {
                .quit => break :mainloop,
                else => {},
            }
        }
    }
}

const utils = struct {
    /// Create an SDL texture from an STB Image
    pub fn sdlTextureFromImage(renderer: SDL.Renderer, image: stb.Image) !SDL.Texture {
        const pixel_info = try PixelInfo.from(image);
        const data: *anyopaque = image.data;

        const surface_ptr = SDL.c.SDL_CreateRGBSurfaceFrom(data, @as(c_int, @intCast(image.width)), @as(c_int, @intCast(image.height)), pixel_info.bits, pixel_info.pitch, pixel_info.pixelmask.red, pixel_info.pixelmask.green, pixel_info.pixelmask.blue, pixel_info.pixelmask.alpha);
        if (surface_ptr == null) {
            return error.CreateRgbSurface;
        }

        const surface = SDL.Surface{ .ptr = surface_ptr.? };
        defer surface.destroy();

        return try SDL.createTextureFromSurface(renderer, surface);
    }

    /// Helper structure that contains some info about the pixel layout
    const PixelInfo = struct {
        const Self = @This();
        /// Bits per pixel
        bits: c_int,
        /// Image pitch (bytes per row within the image, e.g. width * n_channels)
        pitch: c_int,
        /// The pixelmask for the (A)RGB storage
        pixelmask: PixelMask,

        pub fn from(image: stb.Image) !Self {
            if (image.nchan < 0 or image.nchan > 4)
                return error.UnknownPixelFormat;

            return Self{
                .bits = @as(c_int, image.nchan * 8),
                .pitch = @as(c_int, @intCast(image.width * image.nchan)),
                .pixelmask = try PixelMask.fromNumChannels(@intCast(image.nchan)),
            };
        }
    };

    /// helper structure for getting the pixelmasks out of an image
    const PixelMask = struct {
        const Self = @This();
        red: u32,
        green: u32,
        blue: u32,
        alpha: u32,

        pub fn fromNumChannels(nchan: usize) !Self {
            return switch (nchan) {
                1 => Self{
                    // Grayscale
                    .red = 0xff,
                    .green = 0xff,
                    .blue = 0xff,
                    .alpha = 0,
                },
                2 => Self{
                    // Grayscale
                    .red = 0x00ff,
                    .green = 0x00ff,
                    .blue = 0x00ff,
                    .alpha = 0xff00,
                },
                3 => Self{
                    // Grayscale
                    .red = 0x0000ff,
                    .green = 0x00ff00,
                    .blue = 0xff0000,
                    .alpha = 0,
                },
                4 => Self{
                    // Grayscale
                    .red = 0x000000ff,
                    .green = 0x0000ff00,
                    .blue = 0x00ff0000,
                    .alpha = 0xff000000,
                },
                else => error.UnknownPixelFormat,
            };
        }
    };
};
