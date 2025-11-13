const std = @import("std");

const Framework = @import("framework.zig");
const components = @import("components.zig");
const text_input = components.text_input;
const list = components.list;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);

    var stdout_writer = std.fs.File.stdout().writer(try allocator.alloc(u8, 16384));
    const stdout = &stdout_writer.interface;

    var path_flag: ?[:0]u8 = null;
    var debug_flag = false;
    var search_query_buffer = try std.ArrayList(u8).initCapacity(allocator, 8);

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

        if (search_query_buffer.items.len == 0) {
            try search_query_buffer.appendSlice(allocator, arg);
        }
    }

    std.log.debug("search query: {s}", .{search_query_buffer.items});

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
    var try_entries = try std.ArrayList(TryEntry).initCapacity(allocator, 32);
    var tries_iterator = tries_directory.iterate();
    try get_entries(
        allocator,
        tries_absolute_path,
        &tries_iterator,
        &try_entries,
        search_query_buffer.items,
    );

    var tty = try std.fs.cwd().openFile(
        "/dev/tty",
        .{ .mode = .read_write },
    );
    defer tty.close();
    const original = try std.posix.tcgetattr(tty.handle);
    defer std.posix.tcsetattr(tty.handle, .FLUSH, original) catch {};
    var raw = original;
    raw.lflag.ECHO = false;
    raw.lflag.ICANON = false;
    // raw.lflag.ISIG = false;
    raw.lflag.IEXTEN = false;
    raw.iflag.IXON = false;
    raw.iflag.ICRNL = false;
    raw.iflag.INPCK = false;
    raw.iflag.ISTRIP = false;
    try std.posix.tcsetattr(tty.handle, .FLUSH, raw);

    try Framework.init(allocator, stdout, tty);

    while (true) {
        try Framework.write(Framework.CSI ++ Framework.CSICursorToStart);
        try Framework.write(Framework.CSI ++ Framework.CSIClearScreen);

        const can_create = search_query_buffer.items.len > 0;
        const try_name_from_search = try TryEntry.generate_unique_dir_name(
            allocator,
            search_query_buffer.items,
            tries_absolute_path,
        );

        const selected = try Framework.use_state(usize, 1);

        try list(
            selected,
            if (can_create) try_entries.items.len + 1 else try_entries.items.len,
            .{ try_entries.items, try_name_from_search },
            (struct {
                fn render_entry(
                    index: usize,
                    context: std.meta.Tuple(&.{ []TryEntry, []const u8 }),
                ) anyerror!void {
                    const entries, const new_entry_name = context;
                    if (index < entries.len) {
                        try Framework.print("  > {s}\n", .{entries[index].name});
                    } else {
                        try Framework.print("  Create {s}\n", .{new_entry_name});
                    }
                }
            }).render_entry,
        );

        try Framework.write("─────────────────────────────────────────────\n");
        const search_changed = try text_input(&search_query_buffer);
        if (search_changed) {
            try get_entries(
                allocator,
                tries_absolute_path,
                &tries_iterator,
                &try_entries,
                search_query_buffer.items,
            );
            if (can_create) {
                selected.* = try_entries.items.len;
            } else {
                selected.* = 0;
            }
        }

        try stdout.flush();

        try Framework.tick();
    }
}

fn get_entries(
    allocator: std.mem.Allocator,
    tries_absolute_path: []const u8,
    tries_iterator: *std.fs.Dir.Iterator,
    try_entries: *std.ArrayList(TryEntry),
    search_query: []const u8,
) !void {
    tries_iterator.reset();
    try_entries.clearRetainingCapacity();
    while (try tries_iterator.next()) |entry| {
        if (entry.kind == .directory) {
            const path = try std.fs.path.join(
                allocator,
                &.{ tries_absolute_path, entry.name },
            );
            const creation_date = try Date.from_american_format(entry.name);
            try try_entries.append(allocator, .{
                .name = entry.name,
                .path = path,
                .creation_date = creation_date,
                .score = calculate_try_score(
                    entry.name,
                    search_query,
                    creation_date,
                ),
            });
        }
    }

    std.mem.sort(
        TryEntry,
        try_entries.items,
        void{},
        (struct {
            fn lessThan(_: void, a: TryEntry, b: TryEntry) bool {
                return a.score < b.score;
            }
        }).lessThan,
    );
}

const TryEntry = struct {
    name: []const u8,
    path: []const u8,
    creation_date: Date,
    score: f64,

    fn generate_unique_dir_name(
        allocator: std.mem.Allocator,
        name: []const u8,
        base_path: []const u8,
    ) ![]const u8 {
        const date = Date.from_timestamp(std.time.timestamp());
        const date_prefixed_name = try std.mem.concat(
            allocator,
            u8,
            &.{
                try date.to_american_format(allocator),
                "-",
                name,
            },
        );

        const date_prefixed_path = try std.fs.path.join(
            allocator,
            &.{ base_path, date_prefixed_name },
        );

        std.fs.accessAbsolute(
            date_prefixed_path,
            .{},
        ) catch |err| {
            if (err == error.FileNotFound) {
                return date_prefixed_name;
            }
            return err;
        };

        var candidate_number: usize = 2;
        while (file_doesnt_exist: {
            const candidate_name = try std.fmt.allocPrint(
                allocator,
                "{s}-{d}",
                .{ date_prefixed_name, candidate_number },
            );
            const candidate_path = try std.fs.path.join(
                allocator,
                &.{ base_path, candidate_name },
            );
            std.fs.accessAbsolute(candidate_path, .{}) catch |err| {
                if (err == error.FileNotFound) {
                    return candidate_name;
                }
                return err;
            };
            break :file_doesnt_exist true;
        }) {
            candidate_number += 1;
        }
    }
};

const Date = struct {
    year: u16,
    month: u8,
    date: u8,

    fn get_timestamp(self: @This()) i64 {
        var days: u32 = 0;

        // Calculate days for complete years
        for (std.time.epoch.epoch_year..self.year) |year| {
            days += if (is_leap_year(@intCast(year))) 366 else 365;
        }

        // Calculate days for complete months in the current year
        const days_in_months = if (is_leap_year(self.year))
            [_]u16{ 31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
        else
            [_]u16{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };

        for (0..self.month - 1) |month_index| {
            days += days_in_months[month_index];
        }

        // Add days in the current month
        days += @as(u32, self.date - 1);

        return @as(i64, days) * std.time.s_per_day;
    }

    fn to_american_format(self: @This(), allocator: std.mem.Allocator) ![]u8 {
        return try std.fmt.allocPrint(
            allocator,
            "{0:02}-{1:02}-{2:04}",
            .{ self.month, self.date, self.year },
        );
    }

    fn from_american_format(text: []const u8) !@This() {
        const month = text[0.."mm".len];
        const date = text["mm-".len.."mm-dd".len];
        const year = text["mm-dd-".len.."mm-dd-YYYY".len];

        return .{
            .year = try std.fmt.parseInt(u16, year, 10),
            .month = try std.fmt.parseInt(u8, month, 10),
            .date = try std.fmt.parseInt(u8, date, 10),
        };
    }

    fn from_timestamp(timestamp: i64) @This() {
        const epoch_days = @divTrunc(timestamp, std.time.s_per_day);

        const days_since_epoch = @as(u32, @intCast(epoch_days));

        // Calculate year, month, day using calendar arithmetic
        var year: u16 = std.time.epoch.epoch_year;
        var remaining_days = days_since_epoch;

        // Handle leap years and calculate year
        while (true) {
            const days_in_year: u32 = if (is_leap_year(year)) @intCast(366) else @intCast(365);
            if (remaining_days < days_in_year) break;
            remaining_days -= days_in_year;
            year += 1;
        }

        // Calculate month and day
        const days_in_months = if (is_leap_year(year))
            [_]u16{ 31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
        else
            [_]u16{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };

        var month: u8 = 1;
        for (days_in_months) |days_in_month| {
            if (remaining_days < days_in_month) break;
            remaining_days -= days_in_month;
            month += 1;
        }

        const day = @as(u8, @intCast(remaining_days + 1));

        return .{ .year = year, .month = month, .date = day };
    }
};

test "Date.from" {
    const timestamp: i64 = 1762801629;
    const date = Date.from_timestamp(timestamp);
    try std.testing.expectEqual(Date{
        .year = 2025,
        .month = 11,
        .date = 10,
    }, date);
    try std.testing.expectEqual(date, Date.from_timestamp(date.get_timestamp()));
}

fn is_leap_year(year: u16) bool {
    return (year % 4 == 0 and year % 100 != 0) or (year % 400 == 0);
}

fn calculate_try_score(try_name: []const u8, query: []const u8, date: Date) f64 {
    var score: f64 = 0.0;

    if (query.len > 0) {
        score += searching_score(try_name, query);
        if (score <= 0) return 0.0;
    } else {
        score += 1.0;
    }

    const now = std.time.s_per_day;
    const hours_since_access = @as(f64, @floatFromInt(now - date.get_timestamp())) / std.time.s_per_hour;
    score += 3.0 / @sqrt(hours_since_access + 1.0);

    return score;
}

fn searching_score(text: []const u8, query: []const u8) f64 {
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
