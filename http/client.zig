const std = @import("std");

const GPA = std.heap.GeneralPurposeAllocator(.{});

pub fn main() !void {
    var gpa = GPA{};
    var allocator = gpa.allocator();

    // Get the command-line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var uri_str: []const u8 = undefined;
    if (args.len > 1) {
        uri_str = args[1];
    } else {
        uri_str = "https://example.com";
    }

    // our http client, this can make multiple requests (and is even threadsafe, although individual requests are not).
    var client = std.http.Client{
        .allocator = allocator,
    };

    const uri = std.Uri.parse(uri_str) catch unreachable;

    // these are the headers we'll be sending to the server
    var headers = std.http.Headers{ .allocator = allocator };
    defer headers.deinit();

    try headers.append("accept", "*/*"); // tell the server we'll accept anything

    // make the connection and set up the request
    var req = try client.request(.GET, uri, headers, .{});
    defer req.deinit();

    // I'm making a GET request, so do I don't need this, but I'm sure someone will.
    // req.transfer_encoding = .chunked;

    // send the request and headers to the server.
    try req.start();

    // try req.writer().writeAll("Hello, World!\n");
    // try req.finish();

    // wait for the server to send use a response
    try req.wait();

    // read the content-type header from the server, or default to text/plain
    const content_type = req.response.headers.getFirstValue("content-type") orelse "text/plain";
    _ = content_type;

    // read the entire response body, but only allow it to allocate 8kb of memory
    const body = req.reader().readAllAlloc(allocator, 655350) catch unreachable;

    std.debug.print("Body:\n{s}\n", .{body});

    defer allocator.free(body);
}
