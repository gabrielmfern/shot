const std = @import("std");

const Framework = @import("framework.zig");

pub fn text_input(value: *std.ArrayList(u8)) !bool {
    const allocator = Framework.use_allocator();

    var did_change = false;
    if (Framework.use_input()) |input| {
        if (input == .action and input.action == .Backspace) {
            _ = value.pop();
        } else if (input == .printable_ascii) {
            const char = input.printable_ascii;
            if (char != ' ' or value.items.len != 0) {
                try value.append(allocator, char);
                did_change = true;
            }
        }
    }

    try Framework.print(" > {s}", .{value.items});

    return did_change;
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
    if (Framework.use_input()) |input| {
        if (input == .action) {
            if (input.action == .ArrowDown) {
                selected.* = (selected.* + 1) % item_count;
            } else if (input.action == .ArrowUp) {
                selected.* = if (selected.* == 0) item_count - 1 else selected.* - 1;
            }
        }
    }

    if (item_count > 0) {
        for (0..item_count) |i| {
            if (selected.* == i) {
                try Framework.write(Framework.CSI ++ Framework.CSIForeground(228));
                try Framework.write(Framework.CSI ++ Framework.CSIBold);
            } else {
                try Framework.write(Framework.CSI ++ Framework.CSIDim);
            }
            try render_item(i, render_context);
            try Framework.write(Framework.CSI ++ Framework.CSIGraphicReset);
        }
    }
}
