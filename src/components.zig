const std = @import("std");

const Date = @import("main.zig").Date;
const Framework = @import("framework.zig");

pub fn text_input(
    value: *std.ArrayList(u8),
    on_change_context: anytype,
    on_change: fn (context: @TypeOf(on_change_context), new_value: *std.ArrayList(u8)) anyerror!void,
) !void {
    const input_handler_context = .{ .on_change_context = on_change_context, .on_change = on_change, .value = value };
    try Framework.use_input_handler(input_handler_context, (struct {
        fn handler(
            context: *@TypeOf(input_handler_context),
            input: Framework.Input,
        ) anyerror!void {
            if (input == .action and input.action == .Backspace) {
                _ = context.value.pop();
                try context.on_change(context.on_change_context, context.value);
            } else if (input == .printable_ascii) {
                const char = input.printable_ascii;
                if (char != ' ' or context.value.items.len != 0) {
                    try context.value.append(Framework.use_allocator(), char);
                    try context.on_change(context.on_change_context, context.value);
                }
            }
        }
    }).handler);

    try Framework.print(" > {s}", .{value.items});
}

pub fn list(
    selected: *usize,
    item_count: usize,
    render_context: anytype,
    render_item: fn (
        item_index: usize,
        context: @TypeOf(render_context),
    ) anyerror!void,
) !void {
    const input_context = .{ .selected = selected, .item_count = item_count };
    try Framework.use_input_handler(input_context, (struct {
        fn handle(context: *@TypeOf(input_context), input: Framework.Input) anyerror!void {
            if (input == .action) {
                if (input.action == .ArrowDown) {
                    context.selected.* = (context.selected.* + 1) % context.item_count;
                } else if (input.action == .ArrowUp) {
                    context.selected.* = if (context.selected.* == 0) context.item_count - 1 else context.selected.* - 1;
                }
            }
        }
    }).handle);

    if (item_count > 0) {
        for (0..item_count) |i| {
            if (selected.* == i) {
                try Framework.write(Framework.CSI ++ Framework.CSIForeground(33));
                try Framework.write(Framework.CSI ++ Framework.CSIBold);
            } else {
                try Framework.write(Framework.CSI ++ Framework.CSIDim);
            }
            try render_item(i, render_context);
            try Framework.write(Framework.CSI ++ Framework.CSIGraphicReset);
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
