# Tree-Sitter example in Zig

## Prerequisites

- Zig 0.12
- TreeSitter installed: `libtree-sitter.so`, `tree_sitter/api.h`
- TreeSitter parsers: `tree-sitter-markdown`, `tree-sitter-markdown-inline`
- Libs & headers assumed to be at `${HOME}/.local/lib/` and `${HOME}/.local/include`, respectively

## What is this?

This is a super basic example of how to use TreeSitter to parse and run querys on some Markdown
text. If I'm feeling motivated enough, my next goal is to:

- Find each code block
- Read the language of the code block
- Get the raw contents of the code block
- Parse the contents using the language we read
- Apply a query to the parsed contents suitable for syntax highlighting
- Iterate over the query matches and map each match to its color
