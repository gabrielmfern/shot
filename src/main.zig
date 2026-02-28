const std = @import("std");

const nerd = @import("nerd");
const components = @import("components.zig");
const time_since = components.time_since;
const text_input = components.text_input;
const list = components.list;

const Args = struct {
    const Flags = struct {
        path: ?[]const u8,
        help: ?void,
        pipe: ?void,
    };

    const Command = enum { search, new, clone };

    command: Command,
    flags: Flags,

    varying_arguments: []u8,

    fn deinit(self: @This(), allocator: std.mem.Allocator) void {
        if (self.flags.path) |path| {
            allocator.free(path);
        }
        allocator.free(self.varying_arguments);
    }

    fn parse(allocator: std.mem.Allocator, args: [][:0]u8) !@This() {
        var flags = Flags{
            .path = null,
            .help = null,
            .pipe = null,
        };

        var varying_arguments = try std.ArrayList(u8).initCapacity(allocator, 0);
        errdefer varying_arguments.deinit(allocator);

        var command: Command = .search;

        std.debug.assert(args.len >= 1);
        var i: usize = 1;
        while (i < args.len) {
            defer i += 1;
            const arg = args[i];

            if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
                flags.help = void{};
                break;
            }
            if (std.mem.eql(u8, arg, "--pipe") or std.mem.eql(u8, arg, "-p")) {
                flags.pipe = void{};
                break;
            }
            if (std.mem.eql(u8, arg, "--path")) {
                if (args.len == i + 1) {
                    return error.MissingPathValue;
                }
                flags.path = args[i + 1];
                i += 1;
                continue;
            }

            if (varying_arguments.items.len == 0) {
                if (std.mem.eql(u8, arg, "new")) {
                    command = .new;
                    continue;
                } else if (std.mem.eql(u8, arg, "clone")) {
                    command = .clone;
                    continue;
                }
            }

            if (varying_arguments.items.len > 0) {
                try varying_arguments.append(allocator, ' ');
            }
            try varying_arguments.appendSlice(allocator, arg);
        }

        return @This(){
            .command = command,
            .flags = flags,
            .varying_arguments = varying_arguments.items,
        };
    }
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);

    var stderr_writer = std.fs.File.stderr().writer(try allocator.alloc(u8, 16384));
    const stderr = &stderr_writer.interface;

    var stdout_writer = std.fs.File.stdout().writer(try allocator.alloc(u8, 256));
    const stdout = &stdout_writer.interface;

    var parsed_args = Args.parse(allocator, args) catch |err| {
        switch (err) {
            error.MissingPathValue => {
                _ = try stderr.write("Missing value for --path.\n");
                try stderr.flush();
                return;
            },
            else => {
                return err;
            },
        }
    };
    defer parsed_args.deinit(allocator);

    if (parsed_args.flags.help != null) {
        _ = try stderr.write(
            \\A zig-written version of try (https://github.com/tobi/try). It's also compatible with try.
            \\
            \\Usage:
            \\  shot [SEARCH_TERM] [--path PATH]
            \\  shot new NAME [--path PATH]
            \\  shot clone  [--path PATH]
            \\  npx create-next-app@latest $(shot new test-app)
            \\  shot --help
            \\
            \\Commands:
            \\  new NAME       Create a new directory with date-prefixed name
            \\  clone GIT_URL  Clone a git repository into a date-prefixed directory
            \\
            \\Options:
            \\  --path PATH    Use PATH as the base directory (default: ~/src/tries or $TRY_PATH)
            \\  --help, -h     Show this help message
            \\  --pipe, -p     Returns the selected path instead of navigating to it
            \\
            \\Examples:
            \\  shot                                        # Interactive directory selector
            \\  shot web                                    # Search for directories containing "web"
            \\  shot --path ./experiments
            \\  shot new my-project                         # Create a new try directory with the name "my-project"
            \\  shot clone https://github.com/user/repo.git # Clone a git repository into a new try directory
            \\
            \\Environment Variables:
            \\  TRY_PATH      Default path for try directories
            \\
        );
        try stderr.flush();
        return;
    }

    const env_map = try std.process.getEnvMap(allocator);
    var key_iterator = env_map.hash_map.keyIterator();
    while (key_iterator.next()) |key| {
        std.log.debug("env {s}", .{key.*});
    }

    const cwd = try std.process.getCwdAlloc(allocator);

    var tries_absolute_path: []const u8 = try std.fs.path.join(
        allocator,
        &.{ cwd, "tries" },
    );
    if (parsed_args.flags.path) |path| {
        if (std.fs.path.isAbsolute(path)) {
            tries_absolute_path = path;
        } else {
            tries_absolute_path = try std.fs.path.resolve(
                allocator,
                &.{ cwd, path },
            );
        }
    } else if (env_map.get("TRY_PATH")) |TRY_PATH| {
        tries_absolute_path = TRY_PATH;
    } else if (env_map.get("HOME")) |HOME| {
        tries_absolute_path = try std.fs.path.join(
            allocator,
            &.{ HOME, "src/tries" },
        );
    }
    std.log.debug("final tries absolute path {s}", .{tries_absolute_path});

    var component_iterator = try std.fs.path.componentIterator(tries_absolute_path);
    while (component_iterator.next()) |component| {
        std.log.debug("ensuring that the component of the tries absolute path exists {s}", .{component.path});
        std.fs.makeDirAbsolute(component.path) catch |err| {
            if (err == error.PathAlreadyExists) {} else {
                return err;
            }
        };
    }

    if (parsed_args.command == .new) {
        const new_try_name = try TryEntry.generate_unique_dir_name(
            allocator,
            parsed_args.varying_arguments,
            tries_absolute_path,
        );

        const path = try std.fs.path.join(allocator, &.{
            tries_absolute_path,
            new_try_name,
        });

        if (parsed_args.flags.pipe != null) {
            _ = try stdout.print("echo {s}", .{path});
            try stdout.flush();
        } else {
            try std.fs.makeDirAbsolute(path);
            try stdout.print("cd {s}", .{path});
            try stdout.flush();
        }

        return;
    }

    if (parsed_args.command == .clone) {
        if (parsed_args.flags.pipe != null) {
            _ = try stderr.write("Can't clone with the --pipe option enabled");
            try stderr.flush();
            return;
        }

        var segments_backwards_iterator = std.mem.splitBackwardsScalar(
            u8,
            parsed_args.varying_arguments,
            '/',
        );
        const last_segment = segments_backwards_iterator.first();
        const new_try_name = try TryEntry.generate_unique_dir_name(
            allocator,
            if (last_segment.len >= 4 and std.mem.endsWith(u8, last_segment, ".git"))
                last_segment[0 .. last_segment.len - 4]
            else
                last_segment,
            tries_absolute_path,
        );
        const path = try std.fs.path.join(allocator, &.{
            tries_absolute_path,
            new_try_name,
        });

        try stdout.print(
            "git clone {s} {s} && cd {s}",
            .{ parsed_args.varying_arguments, path, path },
        );
        try stdout.flush();
        return;
    }

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
        parsed_args.varying_arguments,
    );

    var tty = try nerd.Tty.init();
    defer tty.deinit();
    try tty.enter_raw_mode();

    try nerd.init(allocator, stderr, tty);

    var search_query_buffer = std.ArrayList(u8).fromOwnedSlice(
        parsed_args.varying_arguments,
    );

    while (true) {
        const should_exit = try nerd.component(app, AppProps{
            .allocator = allocator,
            .tries_absolute_path = tries_absolute_path,
            .tries_iterator = &tries_iterator,
            .try_entries = &try_entries,
            .search_query_buffer = &search_query_buffer,
            .parsed_args = &parsed_args,
            .stdout = stdout,
            .stderr = stderr,
        });

        if (should_exit) {
            break;
        }

        try nerd.update();
    }
}

const AppProps = struct {
    allocator: std.mem.Allocator,
    tries_absolute_path: []const u8,
    tries_iterator: *std.fs.Dir.Iterator,
    try_entries: *std.ArrayList(TryEntry),
    search_query_buffer: *std.ArrayList(u8),
    parsed_args: *const Args,
    stdout: *std.io.Writer,
    stderr: *std.io.Writer,
};

fn app(props: AppProps) !bool {
    try nerd.write(nerd.CSI ++ nerd.CSICursorToStart);
    try nerd.write(nerd.CSI ++ nerd.CSIClearScreen);

    const can_create = props.search_query_buffer.items.len > 0;
    const try_name_from_search = try TryEntry.generate_unique_dir_name(
        props.allocator,
        props.search_query_buffer.items,
        props.tries_absolute_path,
    );

    const terminal_size = try nerd.get_terminal_size();
    const selected = try nerd.use_state(usize, 0);

    try nerd.component(list, .{
        .selected = selected,
        .item_count = if (can_create) props.try_entries.items.len + 1 else props.try_entries.items.len,
        .starting_row = terminal_size.height - 2,
        .render_item_context = .{ props.try_entries.items, try_name_from_search },
        .render_item = (struct {
            fn render_entry(
                index: usize,
                context: std.meta.Tuple(&.{ []TryEntry, []const u8 }),
            ) anyerror!void {
                const entries, const new_entry_name = context;
                if (index == 0) {
                    try nerd.print("Create {s}", .{new_entry_name});
                } else {
                    const entry: TryEntry = entries[index - 1];
                    try nerd.write(nerd.CSI ++ nerd.CSIDim);
                    try nerd.write(entry.name[0.."YYYY-mm-dd-".len]);
                    try nerd.write(nerd.CSI ++ nerd.CSIDimAndBoldReset);
                    try nerd.write(entry.name["YYYY-mm-dd-".len..]);
                    try nerd.write(nerd.CSI ++ nerd.CSIDim);
                    try nerd.write(" (accessed ");
                    try time_since(entry.last_access_timestamp);
                    try nerd.write(")");
                    try nerd.write(nerd.CSI ++ nerd.CSIDimAndBoldReset);
                }
            }
        }).render_entry,
    });

    try nerd.write(" " ++ "─" ** 40 ++ "\n");

    if (try nerd.component(text_input, props.search_query_buffer)) {
        try get_entries(
            nerd.use_allocator(),
            props.tries_absolute_path,
            props.tries_iterator,
            props.try_entries,
            props.search_query_buffer.items,
        );
        if (props.try_entries.items.len > 0) {
            selected.* = 0;
        }
    }

    try props.stderr.flush();

    if (nerd.use_last_input()) |last_input| {
        if (last_input == .action and last_input.action == .Enter) {
            if (can_create and selected.* == props.try_entries.items.len) {
                const path = try std.fs.path.join(props.allocator, &.{
                    props.tries_absolute_path,
                    try_name_from_search,
                });
                if (props.parsed_args.flags.pipe != null) {
                    _ = try props.stdout.print("echo {s}", .{path});
                    try props.stdout.flush();
                    return true;
                }
                try std.fs.makeDirAbsolute(path);

                try props.stdout.print("cd {s}", .{path});
                try props.stdout.flush();
                return true;
            }

            if (props.try_entries.items.len > 0) {
                const path = props.try_entries.items[selected.*].path;
                if (props.parsed_args.flags.pipe != null) {
                    _ = try props.stdout.print("echo {s}", .{path});
                    try props.stdout.flush();
                    return true;
                }

                try props.stdout.print("cd {s}", .{path});
                try props.stdout.flush();
                return true;
            }
        }
    }

    return false;
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
            var dir = try std.fs.openDirAbsolute(path, .{});
            defer dir.close();
            const stat = try dir.stat();
            const last_access_timestamp: i64 = @intCast(@divTrunc(stat.atime, std.time.ns_per_s));

            const creation_date = try Date.from_descending_format(entry.name);
            try try_entries.append(allocator, .{
                .name = try allocator.dupe(u8, entry.name),
                .path = path,
                .creation_date = creation_date,
                .last_access_timestamp = last_access_timestamp,
                .score = calculate_try_score(
                    entry.name,
                    search_query,
                    last_access_timestamp,
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
                return a.score > b.score;
            }
        }).lessThan,
    );
}

const TryEntry = struct {
    name: []const u8,
    path: []const u8,
    creation_date: Date,
    last_access_timestamp: i64,
    score: f64,

    fn generate_unique_dir_name(
        allocator: std.mem.Allocator,
        name: []const u8,
        base_path: []const u8,
    ) ![]const u8 {
        const date = Date.from_timestamp(std.time.timestamp());
        const trimmed_name = std.mem.trim(u8, name, " ");
        var date_prefixed_name: []u8 = undefined;
        if (trimmed_name.len > 0) {
            date_prefixed_name = try std.mem.concat(allocator, u8, &.{
                try date.to_descending_format(allocator),
                "-",
                name,
            });
        } else {
            date_prefixed_name = try std.mem.concat(
                allocator,
                u8,
                &.{ try date.to_descending_format(allocator), "-unnamed" },
            );
        }

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

pub const Date = struct {
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

    fn to_descending_format(self: @This(), allocator: std.mem.Allocator) ![]u8 {
        return try std.fmt.allocPrint(
            allocator,
            "{0:04}-{1:02}-{2:02}",
            .{ self.year, self.month, self.date },
        );
    }

    fn from_descending_format(text: []const u8) !@This() {
        const year = text[0.."YYYY".len];
        const month = text["YYYY-".len.."YYYY-mm".len];
        const date = text["YYYY-mm-".len.."YYYY-mm-dd".len];

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

fn calculate_try_score(try_name: []const u8, query: []const u8, last_access_timestamp: i64) f64 {
    var score: f64 = 0.0;

    if (query.len > 0) {
        score += searching_score(try_name, query);
        if (score <= 0) return 0.0;
    } else {
        score += 1.0;
    }

    const now = std.time.timestamp();
    const hours_since_access = @as(f64, @floatFromInt(now - last_access_timestamp)) / std.time.s_per_hour;
    score += 3.0 / @sqrt(hours_since_access + 1.0);

    return score;
}

test "calculate_try_score" {
    {
        const score1 = calculate_try_score(
            "2024-01-01-stuff",
            "",
            std.time.timestamp() - (2 * std.time.s_per_hour),
        );
        const score2 = calculate_try_score(
            "2024-01-01-stuff-2",
            "",
            std.time.timestamp() - (2 * std.time.s_per_hour),
        );
        try std.testing.expect(score1 == score2);
    }

    {
        const score1 = calculate_try_score(
            "2024-01-01-try",
            "",
            std.time.timestamp() - (10 * std.time.s_per_hour),
        );
        const score2 = calculate_try_score(
            "2024-01-01-try-2",
            "",
            std.time.timestamp() - (2 * std.time.s_per_hour),
        );
        try std.testing.expect(score2 > score1);
    }
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
