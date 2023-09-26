const std = @import("std");
const gca = @import("gc.zig");

const Allocator = std.mem.Allocator;
const GCAllocator = gca.GCAllocator;
const log = std.log.scoped(.main);

pub const std_options = struct {
    pub const log_level = .info;
};

// ---- Standalone exe test

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};

    log.info("Starting GC test", .{});
    var gc = GCAllocator.init(gpa.allocator());
    defer gc.deinit();
    var alloc = gc.allocator();

    try gca.leaker(u8, alloc, 1024);

    log.info("Before collect(): {d} items alloc'd", .{gc.chunks.items.len});

    gc.collect();

    log.info("After collect(): {d} items alloc'd", .{gc.chunks.items.len});

    try gca.leaker(u64, alloc, 1024);

    log.info("Before collect(): {d} items alloc'd", .{gc.chunks.items.len});

    gc.collect();

    log.info("After collect(): {d} items alloc'd", .{gc.chunks.items.len});

    try gca.leaker2(u32, &gc, alloc, 1024);

    log.info("After leaker2(): {d} items alloc'd", .{gc.chunks.items.len});
}
