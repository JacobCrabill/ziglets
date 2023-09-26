const std = @import("std");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

pub const std_options = struct {
    pub const log_level = .debug;
};

const log = std.log.scoped(.gcalloc);

const Chunk = struct {
    slice: []u8,
    log2_ptr_align: u8,
    reachable: bool = false,
    checked: bool = false,
};

pub const GCAllocator = struct {
    const Self = @This();
    start: [*]const u8,
    backing_allocator: Allocator,
    chunks: ArrayList(Chunk),

    /// Create a new GCAllocator
    /// Note that this MUST be inlined, in order to capture the correct frame address
    pub inline fn init(in_alloc: Allocator) Self {
        return Self{
            .start = @ptrFromInt(@frameAddress()),
            .backing_allocator = in_alloc,
            .chunks = ArrayList(Chunk).init(in_alloc),
        };
    }

    /// Destroy the garbage collector, taking out all the trash first
    pub fn deinit(self: *Self) void {
        for (0..self.chunks.items.len) |i| {
            self.freeChunk(i);
        }
        self.chunks.deinit();
        self.* = undefined;
    }

    /// Get a generic Allocator instance
    pub fn allocator(self: *Self) Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = allocWrap,
                .resize = resizeWrap,
                .free = freeWrap,
            },
        };
    }

    /// Perform the garbage collection
    pub fn collect(self: *Self) void {
        @setAlignStack(@sizeOf(*u8));
        // To have the correct frame address, we must ensure this function is not inlined
        @call(.never_inline, _collect, .{self});
    }

    /// Collect implementation
    fn _collect(self: *Self) void {
        log.debug("\n\t~~ Taking out the trash ~~", .{});

        const end: [*]const u8 = @ptrFromInt(@frameAddress());
        const pi_end: usize = @frameAddress();
        const pi_start: usize = @intFromPtr(self.start);
        std.debug.assert(pi_end < pi_start);

        const frame: []const u8 = end[0 .. pi_start - pi_end];
        self.collectFrame(frame);
    }

    fn collectFrame(self: *Self, frame: []const u8) void {
        log.debug("Collecting frame [{*} -> {*}]", .{ frame.ptr, &frame[frame.len - 1] });
        self.mark(frame);
        self.sweep();
    }

    fn mark(self: *Self, frame: []const u8) void {
        // Convert our raw byte array to a word-aligned array of pointers
        //const word_ptrs: []const *const u8 = @alignCast(std.mem.bytesAsSlice(*const u8, frame));
        //const word_ptrs: []const *const u8 = std.mem.alignInSlice(frame, @sizeOf(*u8)).?;
        //const word_ptrs = std.mem.alignInSlice(std.mem.bytesAsSlice(*u8, @constCast(frame)), @sizeOf(*u8)).?;
        //for (word_ptrs) |ptr| {
        for (0..frame.len - @sizeOf(*u8) + 1) |i| {
            const ptr: *const u8 = @ptrCast(&frame[i]);
            // We make the assumption that the piece of memory is a pointer to an allocation in our heap
            if (self.findPtr(ptr)) |idx| {
                var chunk: *Chunk = &self.chunks.items[idx];
                if (chunk.checked) {
                    continue;
                }
                chunk.reachable = true;
                chunk.checked = true;
                self.mark(chunk.slice);
            }
        }
    }

    fn sweep(self: *Self) void {
        var i: usize = 0;
        while (i < self.chunks.items.len) {
            // If reachable, reset flags and continue to next chunk
            if (self.chunks.items[i].reachable) {
                self.chunks.items[i].reachable = false;
                self.chunks.items[i].checked = false;
                i += 1;
                continue;
            }

            // If not reachable, free it
            self.freeChunk(i);
        }
    }

    fn freeChunk(self: *Self, idx: usize) void {
        const chunk = self.chunks.items[idx];
        log.debug("Freeing {d} bytes with log2 alignment {d} at: {d}", .{
            chunk.slice.len,
            chunk.log2_ptr_align,
            idx,
        });
        self.backing_allocator.rawFree(chunk.slice, chunk.log2_ptr_align, @returnAddress());
        _ = self.chunks.swapRemove(idx);
    }

    /// Allocator.alloc implementation
    fn allocWrap(ctx: *anyopaque, len: usize, log2_ptr_align: u8, ret_addr: usize) ?[*]u8 {
        const self: *Self = @ptrCast(@alignCast(ctx));
        if (self.backing_allocator.rawAlloc(len, log2_ptr_align, ret_addr)) |ptr| {
            log.debug("Adding chunk ptr {*} with alignment {d}", .{ ptr, log2_ptr_align });
            self.chunks.append(.{ .slice = ptr[0..len], .log2_ptr_align = log2_ptr_align }) catch |e| {
                log.err("Error adding alloced chunk: {any}", .{e});
            };
            return ptr;
        } else {
            log.err("Unable to alloc? len: {d}", .{len});
            return null;
        }
    }

    /// Allocator.resize implementation
    fn resizeWrap(ctx: *anyopaque, buf: []u8, buf_align: u8, new_len: usize, ret_addr: usize) bool {
        _ = ret_addr;
        _ = new_len;
        _ = buf_align;
        _ = buf;
        _ = ctx;
        // Comments from the std lib (Allocator.zig):
        //     Requests to modify the size of an allocation. It is guaranteed to not move
        //     the pointer, however the allocator implementation may refuse the resize
        //     request by returning `false`.
        log.err("Allocation resizing is unsupported!", .{});
        return false;
    }

    /// Allocator.free implementation
    fn freeWrap(ctx: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
        _ = ret_addr;
        if (buf.len == 0) return;

        const self: *Self = @ptrCast(@alignCast(ctx));
        if (self.findPtr(&buf[0])) |idx| {
            self.freeChunk(idx);
        } else {
            log.err("Attempt to free unmanaged ptr {*} of size {d}", .{ buf, buf_align });
        }
    }

    fn findPtr(self: *Self, ptr: *const u8) ?usize {
        // Search our list of chunks to find the allocation this points to
        const iptr: usize = @intFromPtr(ptr);
        for (self.chunks.items, 0..) |chunk, i| {
            const ci_start = @intFromPtr(chunk.slice.ptr);
            const ci_end = ci_start + chunk.slice.len;
            if (ci_start <= iptr and iptr < ci_end) {
                return i;
            }
        }
        return null;
    }

    pub fn alloc(self: *Self, comptime T: type, n: usize) Allocator.Error![]T {
        return self.allocator().alloc(T, n);
    }

    pub fn create(self: *Self, comptime T: type) Allocator.Error!*T {
        return self.allocator().create(T);
    }

    pub fn dupe(self: *Self, comptime T: type, in_buf: []const T) Allocator.Error![]T {
        return self.allocator().dupe(T, in_buf);
    }
};

// ----------------------------------------------------------------------------
// Tests
// ----------------------------------------------------------------------------

// Function that leaks memory
pub fn leaker(comptime T: type, alloc: Allocator, n_alloc: usize) !void {
    for (0..n_alloc) |_| {
        _ = try doSomeAllocs(T, alloc);
    }
}

pub fn leaker2(comptime T: type, gc: *GCAllocator, alloc: Allocator, n_alloc: usize) !void {
    // Note that we still find stack pointers to our allocations... TODO: think about this.
    // I think we're somehow off by one stack frame...? Or it's something
    // to do with how Zig creates slices...?  idk
    defer gc.collect();

    for (0..n_alloc) |_| {
        _ = try doSomeAllocs(T, alloc);
    }
}

// Function that allocates (and leaks) some memory
fn doSomeAllocs(comptime T: type, alloc: Allocator) ![]T {
    var buf: []T = try alloc.alloc(T, 1024);
    return buf;
}

pub const BigStruct = struct {
    data: @Vector(256, usize) = @splat(42),
    bigint: u128 = 0,
};

pub const Node = struct {
    data: u8,
    left: ?*Node = null,
    right: ?*Node = null,

    pub fn createLeft(self: *Node, alloc: Allocator) void {
        self.left = alloc.create(Node) catch |e| err: {
            log.err("Error in create: {}", .{e});
            break :err null;
        };
    }

    pub fn createRight(self: *Node, alloc: Allocator) void {
        self.right = alloc.create(Node) catch |e| err: {
            log.err("Error in create: {}", .{e});
            break :err null;
        };
    }
};

test "Ensure no leaks" {
    var gc = GCAllocator.init(std.testing.allocator);
    defer gc.deinit();
    var alloc = gc.allocator();

    const n_alloc: usize = 1024;
    try leaker(u8, alloc, n_alloc);

    try std.testing.expectEqual(n_alloc, gc.chunks.items.len);

    gc.collect();

    try std.testing.expectEqual(@as(usize, 0), gc.chunks.items.len);

    try leaker(BigStruct, alloc, n_alloc);

    try std.testing.expectEqual(n_alloc, gc.chunks.items.len);

    gc.collect();

    try std.testing.expectEqual(@as(usize, 0), gc.chunks.items.len);

    std.debug.print("~~~~ Test Passed ~~~~", .{});
}

fn linkedListTest(gc: *GCAllocator) !void {
    var root: *Node = try gc.create(Node);
    root.createLeft(gc.allocator());
    root.createRight(gc.allocator());
}

test "linked lists" {
    var gc = GCAllocator.init(std.testing.allocator);
    defer gc.deinit();

    try linkedListTest(&gc);

    gc.collect();
}
