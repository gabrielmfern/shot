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
- **Constants**: SCREAMING_SNAKE_CASE (e.g., `CSI`, `CSIClearScreen`)
- **Functions**: camelCase (e.g., `calculateScore`, `matchScore`)
- **Variables**: snake_case (e.g., `tries_absolute_path`, `search_query`)
- **Types**: PascalCase (e.g., `TryEntry`, `Date`)

## Error Handling
- Use Zig's built-in error handling with `!` and `try`
- Handle specific errors with catch blocks when needed
- Use `defer` for cleanup (e.g., `defer arena.deinit()`)

## Memory Management
- Use arena allocators for short-lived allocations
- Always defer cleanup of resources
- Pass allocators explicitly to functions that need them