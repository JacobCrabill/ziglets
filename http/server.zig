//! Simple HTTP server
//!
//! Modified from: https://blog.orhun.dev/zig-bits-04/
//!   including the comments from 'hajsf'
//!
//! Usage:
//!   Terminal 1: 'zig run server.zig'
//!   Terminal 2: 'curl -G 127.0.0.1:8000/path-to-file'
const std = @import("std");

const Allocator = std.mem.Allocator;
const GPA = std.heap.GeneralPurposeAllocator(.{});
const http = std.http;

const MimeMap = std.StringHashMap([]const u8);
const RouteMap = std.StringHashMap(*const fn (response: *http.Server.Response) void);

const log = std.log.scoped(.server);

const server_addr = "127.0.0.1";
const server_port = 8000;

pub fn main() !void {
    var gpa = GPA{};
    var allocator = gpa.allocator();

    // Initialize the server.
    var server = http.Server.init(allocator, .{ .reuse_address = true });
    defer server.deinit();

    // Log the server address and port
    log.info("Server is running at {s}:{d}", .{ server_addr, server_port });

    // Parse the server address and start the server
    const address = std.net.Address.parseIp(server_addr, server_port) catch unreachable;
    try server.listen(address);

    runServer(&server, allocator) catch |err| {
        // Handle server errors.
        log.err("server error: {}\n", .{err});
        if (@errorReturnTrace()) |trace| {
            std.debug.dumpStackTrace(trace.*);
        }
        std.os.exit(1);
    };
}

// Run the server and handle incoming requests.
fn runServer(server: *http.Server, allocator: Allocator) !void {
    // Setup standard / default MIME types
    var mimeTypes = MimeMap.init(allocator);
    defer mimeTypes.deinit();
    try Mimes.init(&mimeTypes);

    outer: while (true) {
        // Accept incoming connection.
        var response = try server.accept(.{
            .allocator = allocator,
        });
        defer response.deinit();

        while (response.reset() != .closing) {
            // Handle errors during request processing.
            response.wait() catch |err| switch (err) {
                error.HttpHeadersInvalid => continue :outer,
                error.EndOfStream => continue,
                else => return err,
            };

            // Process the request.
            handleRequest(&response, &mimeTypes, allocator) catch |e| {
                std.log.err("Error encountered while handling request: {any}\n", .{e});
            };
        }
    }
}

fn handleRequest(response: *http.Server.Response, mime_types: *MimeMap, allocator: Allocator) !void {
    // Log the request details.
    log.info("{s} {s} {s}", .{ @tagName(response.request.method), @tagName(response.request.version), response.request.target });

    // Read the request body.
    const body = try response.reader().readAllAlloc(allocator, 8192);
    defer allocator.free(body);

    // Set "connection" header to "keep-alive" if present in request headers.
    if (response.request.headers.contains("connection")) {
        try response.headers.append("connection", "keep-alive");
    }

    // The kind of HTTP request we received
    const method: http.Method = response.request.method;
    // The target of the request (e.g. /get)
    const target: []const u8 = response.request.target;

    if (method != .GET) {
        log.err("Unimplemented method: {any}", .{method});
    }

    if (std.mem.startsWith(u8, target, "/favicon.ico")) {
        return error.FaviconNotFound;
    }

    response.transfer_encoding = .chunked;

    // Check if the target is likely a file
    if (std.mem.containsAtLeast(u8, target, 1, ".")) {
        // Set "content-type" header to "text/html".
        const file = std.mem.trimLeft(u8, target, &[_]u8{'/'});

        // Check the MIME type based on the file extension
        const extension = std.fs.path.extension(file);

        if (mime_types.get(extension)) |mime| {
            try response.headers.append("content-type", mime);
            log.debug("Using MIME type {s} for '{s}'\n", .{ mime, extension });
        } else {
            log.err("Unknown extension: {s}", .{extension});
            try response.headers.append("content-type", "text/plain");
        }

        const contents = readFile(allocator, file) catch |err| {
            log.err("Error reading file {s}: {any}", .{ file, err });
            return error.FileNotFound;
        };
        defer allocator.free(contents);
        log.info("file read as: \n{s}", .{contents});

        // Write the response body.
        try response.do();
        if (response.request.method != .HEAD) {
            try response.writeAll(contents);
            try response.finish();
        }
    } else {
        // Some other route than a direct path to a file
        // Use our Routes map to resolve the target
        try response.headers.append("content-type", "text/plain");

        var routes = RouteMap.init(allocator);
        defer routes.deinit();
        try Routes.init(&routes);

        if (routes.get(target)) |handler| {
            // The handler must finish the response
            std.debug.print("Calling handler: {s} for route: {s}\n", .{ handler, target });
            handler(response);
        } else {
            log.err("Unknown route: '{s}'", .{target});
            // Write the response body.
            try response.do();
            if (response.request.method != .HEAD) {
                try response.writeAll("404: ");
                try response.writeAll("Invalid path\n");
                try response.writeAll(target);
                try response.finish();
            }
            return error.ErrorNoEntity;
        }
    }
}

pub fn readFile(allocator: std.mem.Allocator, filename: []const u8) ![]u8 {
    const file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();

    const contents = try file.reader().readAllAlloc(allocator, std.math.maxInt(usize));
    errdefer allocator.free(contents);

    return contents;
}

const Mimes = struct {
    //const std = @import("std");
    pub fn init(mimeTypes: *std.StringHashMap([]const u8)) !void {
        try mimeTypes.put(".html", "text/html");
        try mimeTypes.put(".js", "application/javascript");
        try mimeTypes.put(".css", "text/css");
    }
};

const Routes = struct {
    /// Setup our available routes to resolve
    pub fn init(routes: *RouteMap) !void {
        try routes.put("/load", load);
    }

    pub fn load(response: *http.Server.Response) void {
        std.log.info("handling route '/load' => , {}", .{response});
        response.do() catch |e| {
            std.log.err("{any}", .{e});
        };

        if (response.request.method != .HEAD) {
            writeAll(response, "Hold on ");
            writeAll(response, "will load the route!\n");
            writeAll(response, "I executed the handler :)");

            response.finish() catch |e| {
                std.log.err("{any}", .{e});
            };
        }
    }

    fn writeAll(response: *http.Server.Response, bytes: []const u8) void {
        response.writeAll(bytes) catch |e| {
            std.log.err("{any}", .{e});
        };
    }
};
