const std = @import("std");

const CSI = "\x1b";
const CSIClearScreen = "[2J";
const CSICursorToStart = "[H";

pub fn main() !void {
    // This is the total amount of allocations. It also includes the writer buffer for stdout.
    var buffer: [32768]u8 = undefined;

    var fba = std.heap.FixedBufferAllocator.init(buffer[0..]);
    const allocator = fba.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var stdout_writer = std.fs.File.stdout().writer(try allocator.alloc(u8, 16384));
    const stdout = &stdout_writer.interface;

    var path_flag: ?[:0]u8 = null;
    var debug_flag = false;
    var search_query: ?[]const u8 = null;

    std.debug.assert(args.len >= 1);
    var i: usize = 1;
    while (i < args.len) {
        defer i += 1;
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            _ = try stdout.write(
                \\A zig-written version of try (https://github.com/tobi/try). It's also compatible with try.
                \\
                \\Usage:
                \\  shot [SEARCH_TERM] [--path PATH]
                \\  shot --help
                \\
                \\Options:
                \\  --path PATH    Use PATH as the base directory (default: ~/src/tries or $TRY_PATH)
                \\  --help, -h     Show this help message
                \\  --debug
                \\
                \\Examples:
                \\  shot                    # Interactive directory selector
                \\  shot web                # Search for directories containing "web"
                \\  shot --path ./experiments
                \\
                \\Environment Variables:
                \\  TRY_PATH      Default path for try directories
                \\
            );
            try stdout.flush();
            return;
        }
        if (std.mem.eql(u8, arg, "--path")) {
            if (args.len == i + 1) {
                _ = try stdout.write("Missing value for --path.");
                try stdout.flush();
                return;
            }
            path_flag = args[i + 1];
            i += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--debug")) {
            debug_flag = true;
            continue;
        }

        if (search_query == null) {
            search_query = arg;
        }
    }

    if (debug_flag and search_query != null) {
        std.log.debug("search query: {s}", .{search_query.?});
    }

    if (debug_flag and path_flag != null) {
        std.log.debug("--path: {s}", .{path_flag.?});
    }

    const env_map = try std.process.getEnvMap(allocator);

    const cwd = try std.process.getCwdAlloc(allocator);
    if (debug_flag) {
        std.log.debug("CWD: {s}", .{cwd});
    }

    var tries_absolute_path: []const u8 = try std.fs.path.join(allocator, &.{ cwd, "tries" });
    if (path_flag) |path| {
        if (std.fs.path.isAbsolute(path)) {
            tries_absolute_path = path;
        } else {
            tries_absolute_path = try std.fs.path.resolve(allocator, &.{ cwd, path });
        }
    } else if (env_map.get("TRY_PATH")) |TRY_PATH| {
        if (debug_flag) {
            std.log.debug("TRY_PATH {s}", .{TRY_PATH});
        }
        tries_absolute_path = TRY_PATH;
    } else if (env_map.get("HOME")) |HOME| {
        if (debug_flag) {
            std.log.debug("HOME {s}", .{HOME});
        }
        tries_absolute_path = try std.fs.path.join(allocator, &.{ HOME, "src/tries" });
    }

    if (debug_flag) {
        std.log.debug("final tries absolute path: {s}", .{tries_absolute_path});
    }

    std.fs.makeDirAbsolute(
        tries_absolute_path,
    ) catch |err| {
        if (err == error.PathAlreadyExists) {
            if (debug_flag) {
                std.log.debug("tries directory exists", .{});
            }
        } else {
            return err;
        }
    };

    const tries_directory = try std.fs.openDirAbsolute(
        tries_absolute_path,
        .{ .iterate = true, .access_sub_paths = false },
    );

    const try_entries = std.ArrayList(TryEntry).initBuffer(buffer: []T)

    try render_search(search_query orelse "", tries_directory, stdout);
}

const TryEntry = struct {
    name: []const u8,
    path: []const u8,
    mtime: i64,
    score: f64,
};

fn render_search(search_query: []const u8, tries_directory: std.fs.Dir, writer: *std.io.Writer) !void {
    _ = try writer.write(CSI ++ CSICursorToStart);
    _ = try writer.write(CSI ++ CSIClearScreen);
    _ = try writer.write(search_query);
    _ = tries_directory;

    // var iterator = tries_directory.iterate();
    // while (try iterator.next()) |entry| {
    //     if (entry.kind == .directory) {
    //         try writer.print("> {s} ({s})", .{entry.name, formatRelativeTime(entry.mtime)});
    //     }
    // }

    try writer.flush();
}

fn calculateScore(text: []const u8, query: []const u8, mtime: i64) f64 {
    var score: f64 = 0.0;

    // Boost for date-prefixed directories
    if (text.len >= 11 and std.mem.startsWith(u8, text, "20") and
        text[4] == '-' and text[7] == '-' and text[10] == '-')
    {
        score += 2.0;
    }

    if (query.len > 0) {
        score += matchScore(text, query);
        if (score <= 0) return 0.0;
    } else {
        score += 1.0; // Base score when not searching
    }

    // Time-based scoring
    const now = std.time.timestamp();
    const hours_since_access = @as(f64, @floatFromInt(now - mtime)) / 3600.0;
    score += 3.0 / @sqrt(hours_since_access + 1.0);

    return score;
}

fn matchScore(text: []const u8, query: []const u8) f64 {
    if (std.ascii.indexOfIgnoreCase(text, query) != null) {
        return 10.0;
    }

    var score: f64 = 0.0;
    var query_idx: usize = 0;

    for (text, 0..) |char, pos| {
        if (query_idx >= query.len) break;

        const text_char = std.ascii.toLower(char);
        const query_char = std.ascii.toLower(query[query_idx]);

        if (text_char == query_char) {
            score += 1.0;
            if (pos == 0) score += 0.5; // Bonus for starting match
            query_idx += 1;
        }
    }

    if (query_idx < query.len) return 0.0;

    return score;
}

fn formatRelativeTime(timestamp: i64) []const u8 {
    const now = std.time.timestamp();
    const seconds = now - timestamp;
    const minutes = @divTrunc(seconds, 60);
    const hours = @divTrunc(minutes, 60);
    const days = @divTrunc(hours, 24);

    if (seconds < 10) {
        return "now";
    } else if (minutes < 60) {
        return "recent";
    } else if (hours < 24) {
        return "today";
    } else if (days < 7) {
        return "week";
    } else {
        return "old";
    }
}
