const std = @import("std");
const c = @cImport({
    @cInclude("tree_sitter/api.h");
    @cInclude("tree_sitter/tree-sitter-c.h");
    @cInclude("tree_sitter/tree-sitter-markdown.h");
    @cInclude("tree_sitter/tree-sitter-markdown-inline.h");
});

const TSParser = c.TSParser;
const TSTree = c.TSTree;
const TSNode = c.TSNode;
const TSQuery = c.TSQuery;
const TSQueryCapture = c.TSQueryCapture;
const TSQueryCursor = c.TSQueryCursor;
const TSQueryError = c.TSQueryError;
const TSQueryMatch = c.TSQueryMatch;

pub fn main() !void {
    // Create our source to parse
    const source: []const u8 =
        \\# Hello, World!
        \\
        \\- List item
        \\
        \\```c
        \\#include <stdio.h>
        \\int main() {
        \\    printf("Hello, World!\n");
        \\    return 0;
        \\}
        \\```
        \\
        \\```json
        \\{
        \\  "foo": "bar",
        \\  "baz": 2
        \\}
        \\```
        \\
    ;
    const c_source = @as([*c]const u8, &source[0]);

    // Setup TreeSitter
    const parser: *TSParser = c.ts_parser_new().?;
    defer c.ts_parser_delete(parser);

    // Set the language to Markdown (block level, not inline)
    _ = c.ts_parser_set_language(parser, c.tree_sitter_markdown());

    std.debug.print("Source code: {s}\n", .{source});
    const tree: *TSTree = c.ts_parser_parse_string(parser, null, c_source, source.len).?;
    defer c.ts_tree_delete(tree);

    // Get the root node of the syntax tree.
    const doc_node: TSNode = c.ts_tree_root_node(tree);

    // Get some child nodes.
    const root_sec_node: TSNode = c.ts_node_named_child(doc_node, 0);
    const header_node: TSNode = c.ts_node_named_child(root_sec_node, 0);

    std.debug.print("Document node name: {s}\n", .{c.ts_node_type(doc_node)});
    std.debug.print("Root node name: {s}\n", .{c.ts_node_type(root_sec_node)});
    std.debug.print("Child node name: {s}\n", .{c.ts_node_type(header_node)});

    // Print the syntax tree as an S-expression.
    const string: [*c]const u8 = c.ts_node_string(doc_node);
    std.debug.print("Syntax tree: {s}\n", .{string});

    // Let's try to find the inline content to be parsed!
    // TODO

    // Let's try to parse the nested code block using its language!
    const n_nodes: usize = c.ts_node_child_count(root_sec_node);
    const code_block_type = "fenced_code_block";
    //const code_block_type = "code_fence_content";
    for (0..n_nodes) |i| {
        const node: TSNode = c.ts_node_child(root_sec_node, @intCast(i));

        const node_type = c.ts_node_type(node);
        const as_slice: [:0]const u8 = std.mem.span(node_type);
        if (std.mem.eql(u8, as_slice, code_block_type)) {
            // TODO
            std.debug.print("Have code block!\n", .{});
        }
    }

    // Create a query to look for fenced_code_block node with info_string and code_fence_content children
    // The query will return named captures for "infoString" and "codeBlock"
    var error_offset: u32 = undefined;
    var error_type: TSQueryError = undefined;
    const query_string: []const u8 = "(fenced_code_block (info_string) @infoString (code_fence_content) @codeBlock)";
    const c_query_string: [*c]const u8 = @as([*c]const u8, &query_string[0]);
    var query: *TSQuery = undefined;
    if (c.ts_query_new(c.tree_sitter_markdown(), c_query_string, @intCast(query_string.len), &error_offset, &error_type)) |q| {
        query = q;
    } else {
        std.debug.print("ERROR: Unable to create query.\nOffset: {d}\nType: {any}\n", .{ error_offset, error_type });
        return;
    }
    defer c.ts_query_delete(query);

    const cursor: *TSQueryCursor = c.ts_query_cursor_new().?;
    defer c.ts_query_cursor_delete(cursor);

    c.ts_query_cursor_exec(cursor, query, doc_node);

    // Find the capture name for each named capture group
    const capture_count = c.ts_query_capture_count(query);
    for (0..capture_count) |i| {
        std.debug.print("Capture Name: {s}\n", .{captureGroupName(query, i)});
    }

    // Just for demo purposes
    const CodeBlock = struct {
        language: []const u8,
        source: []const u8,
    };

    var match: TSQueryMatch = undefined;
    while (c.ts_query_cursor_next_match(cursor, &match)) {
        std.debug.print("\nQuery match with {d} captures\n", .{match.capture_count});

        var block = CodeBlock{ .language = undefined, .source = undefined };
        for (0..match.capture_count) |i| {
            const capture: TSQueryCapture = match.captures[i];
            const node: TSNode = capture.node;
            const start = c.ts_node_start_byte(node);
            const end = c.ts_node_end_byte(node);
            const capture_name = captureGroupName(query, i);
            const content = source[start..end];
            std.debug.print("Node capture idx: {d}\n", .{capture.index});
            std.debug.print("  Capture name: {s}\n", .{capture_name});
            std.debug.print("  Captured node name: {s} [{d} {d}]\n", .{ c.ts_node_type(node), start, end });
            std.debug.print("  Content: {s}\n", .{content});

            if (std.mem.eql(u8, capture_name, "infoString")) {
                block.language = content;
            } else if (std.mem.eql(u8, capture_name, "codeBlock")) {
                block.source = content;
            }

            // // Find the language tag for the block (the hard way)
            // var sibling = c.ts_node_prev_sibling(node);
            // while (!c.ts_node_is_null(sibling)) : (sibling = c.ts_node_prev_sibling(sibling)) {
            //     if (std.mem.eql(u8, std.mem.span(c.ts_node_type(sibling)), "info_string")) {
            //         std.debug.print("Found info_string of code block! {any}\n", .{sibling});
            //         const child_count = c.ts_node_child_count(sibling);
            //         for (0..child_count) |j| {
            //             // Extract the language from the info_string
            //             const child = c.ts_node_child(sibling, @intCast(j));
            //             std.debug.print("  Child: {s}\n", .{c.ts_node_type(child)});
            //             const language = source[c.ts_node_start_byte(child)..c.ts_node_end_byte(child)];
            //             std.debug.print("  {s}\n", .{language});
            //             // From here, can map 'language' to tree_sitter_<language>()
            //             // and parse the code-block content using it
            //             // I'd probably setup a StringHashMap(TSLanguage)
            //         }
            //     }
            // }
        }

        std.debug.print("Have CodeBlock: {any}\n", .{block});
    }
}

fn captureGroupName(query: *TSQuery, idx: usize) []const u8 {
    var len: u32 = 0;
    return c.ts_query_capture_name_for_id(query, @intCast(idx), &len)[0..len];
}
