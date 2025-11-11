# Development Guidelines for Coding Agents

## Build Commands
- **Build**: `zig build`
- **Run**: `zig build run -- [args]`
- **Test**: `zig build test`
- **Run single test**: `zig build test --filter "test_name"`
- **Dev test script**: `./test.sh` (runs with debug flags)

## Code Style
- **Language**: Zig (minimum version 0.15.2)
- **Formatting**: Use `zig fmt` for automatic formatting
- **Imports**: Standard library as `const std = @import("std");`
- **Constants**: PascalCase (e.g., `CSI`, `CSIClearScreen`)
- **Types**: PascalCase (e.g., `TryEntry`, `Date`)
- **Variables**: snake_case (e.g., `tries_absolute_path`, `search_query`)
- **Functions**: snake_case (e.g., `tries_absolute_path`, `search_query`)

## Error Handling
- Use Zig's built-in error handling with `!` and `try`

## Memory Management
- Don't cleanup any resources, just allocate it endlessly, and let the Arena clean it up
- Pass allocators explicitly to functions that need them
