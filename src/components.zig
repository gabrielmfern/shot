const std = @import("std");

const Date = @import("main.zig").Date;
const Framework = @import("framework.zig");

pub fn text_input(
    value: *std.ArrayList(u8),
) !bool {
    var changed = false;
    if (Framework.use_last_input()) |input| {
        if (input == .action and input.action == .Backspace) {
            _ = value.pop();
            changed = true;
        } else if (input == .printable_ascii) {
            const char = input.printable_ascii;
            if (char != ' ' or value.items.len != 0) {
                try value.append(Framework.use_allocator(), char);
                changed = true;
            }
        }
    }

    try Framework.print(" > {s}", .{value.items});

    return changed;
}

pub fn list(props: anytype) !void {
    const selected: *usize = props.selected;
    const item_count: usize = props.item_count;
    const starting_row: usize = props.starting_row;

    const render_item_context = props.render_item_context;
    const render_item: fn (
        item_index: usize,
        context: @TypeOf(render_item_context),
    ) anyerror!void = props.render_item;

    const scroll_offset = try Framework.use_state(usize, 0);

    if (item_count > 0) {
        const available_rows = starting_row;
        const item_to_render_count = @min(item_count, available_rows);
        if (item_to_render_count < available_rows) {
            for (0..starting_row) |_| {
                try Framework.write("\n");
            }
        }
        if (item_count >= item_to_render_count) {
            std.debug.assert(scroll_offset.* <= item_count - item_to_render_count);
        }
        for (scroll_offset.*..item_to_render_count + scroll_offset.*) |reversed_i| {
            const i = item_count - 1 - reversed_i;
            if (selected.* == i) {
                try Framework.write(Framework.CSI ++ Framework.CSIForeground(33));
                try Framework.write(Framework.CSI ++ Framework.CSIBackground(240));
            } else {
                try Framework.write(Framework.CSI ++ Framework.CSIForeground(240));
            }
            try Framework.write("▌ ");
            try Framework.write(Framework.CSI ++ Framework.CSIGraphicReset);

            if (selected.* == i) {
                try Framework.write(Framework.CSI ++ Framework.CSIBackground(240));
            }
            try render_item(i, render_item_context);
            try Framework.write(" ");

            try Framework.write(Framework.CSI ++ Framework.CSIGraphicReset);
            try Framework.write("\n");
        }
    }

    if (Framework.use_last_input()) |input| {
        if (input == .action) {
            if (input.action == .ArrowDown) {
                selected.* = if (selected.* == 0) item_count - 1 else selected.* - 1;
            } else if (input.action == .ArrowUp) {
                selected.* = (selected.* + 1) % item_count;
            }
        }
    }
}

pub const Time = union(enum) {
    months: i64,
    days: i64,
    hours: i64,
    minutes: i64,
    moments,

    fn calculate(timestamp: i64) @This() {
        const difference_months = @divTrunc(timestamp, std.time.s_per_day * 30);
        if (difference_months != 0) {
            return Time{
                .months = difference_months,
            };
        }

        const difference_days = @divTrunc(timestamp, std.time.s_per_day);
        if (difference_days != 0) {
            return Time{
                .days = difference_days,
            };
        }

        const difference_hours = @divTrunc(timestamp, std.time.s_per_hour);
        if (difference_hours != 0) {
            return Time{
                .hours = difference_hours,
            };
        }

        const difference_minutes = @divTrunc(timestamp, std.time.s_per_min);
        if (difference_minutes != 0) {
            return Time{
                .minutes = difference_minutes,
            };
        }

        return Time.moments;
    }
};

pub fn time_since(since: i64) !void {
    const now = std.time.timestamp();
    switch (Time.calculate(now - since)) {
        .moments => {
            try Framework.write("moments ago");
        },
        .minutes => |minutes| {
            if (minutes > 1) {
                try Framework.print("{d} minutes ago", .{minutes});
            } else {
                try Framework.write("a minute ago");
            }
        },
        .hours => |hours| {
            if (hours > 1) {
                try Framework.print("{d} hours ago", .{hours});
            } else {
                try Framework.write("an hour ago");
            }
        },
        .days => |days| {
            if (days > 1) {
                try Framework.print("{d} days ago", .{days});
            } else {
                try Framework.write("a day ago");
            }
        },
        .months => |months| {
            if (months > 1) {
                try Framework.print("{d} months ago", .{months});
            } else {
                try Framework.write("a month ago");
            }
        },
    }
}
