const std = @import("std");

pub const CSI = "\x1b[";
pub const CSIClearScreen = "2J";
pub const CSICursorToStart = "H";
pub const CSIDim = "2m";
pub const CSIBold = "1m";
pub const CSIDimAndBoldReset = "22m";
pub inline fn CSIForeground(comptime color_id: u8) *const [std.fmt.count("38;5;{d}m", .{color_id})]u8 {
    return std.fmt.comptimePrint("38;5;{d}m", .{color_id});
}
pub inline fn CSIBackground(comptime color_id: u8) *const [std.fmt.count("48;5;{d}m", .{color_id})]u8 {
    return std.fmt.comptimePrint("48;5;{d}m", .{color_id});
}
pub const CSIGraphicReset = "0m";

pub const CSIArrowUp = "A";
pub const CSIArrowDown = "B";
pub const CSIArrowRight = "C";
pub const CSIArrowLeft = "D";

arena: std.heap.ArenaAllocator,

allocator: std.mem.Allocator,
stdout: *std.io.Writer,
tty: std.fs.File,

states: std.ArrayList(*anyopaque),
/// The current index that will be used for the call of `use_state` in this tick
state_cursor_index: usize,

tick_input_handlers: std.ArrayList(InputHandler),

const InputHandler = struct {
    context: *anyopaque,
    call_handler: fn (context: *anyopaque, input: Input) !void,
};

/// This only includes the few keys that we're using, it does not at all, include all of the possible values
pub const Input = union(enum) {
    action: enum {
        ArrowDown,
        ArrowUp,
        Enter,
        Backspace,
    },
    printable_ascii: u8,
};

var self: @This() = undefined;

/// Allocator is expected to be an Arena that clears all of the data it
/// allocates automatically
pub fn init(
    allocator: std.mem.Allocator,
    stdout: *std.io.Writer,
    tty: std.fs.File,
) !void {
    self = .{
        .arena = std.heap.ArenaAllocator.init(allocator),

        .allocator = allocator,
        .stdout = stdout,
        .tty = tty,

        .states = try std.ArrayList(*anyopaque).initCapacity(allocator, 0),
        .state_cursor_index = 0,

        .tick_input_handlers = try std.ArrayList(*anyopaque).initCapacity(allocator, 0),
    };
}

pub fn use_stdout() *std.io.Writer {
    return self.stdout;
}

pub fn use_allocator() std.mem.Allocator {
    return self.allocator;
}

/// thin wrapper around stdout.write, for convenience
pub fn write(bytes: []const u8) !void {
    _ = try self.stdout.write(bytes);
}

/// thin wrapper around stdout.print, for convenience
pub fn print(comptime fmt: []const u8, args: anytype) !void {
    try self.stdout.print(fmt, args);
}

pub fn tick() !void {
    if (self.state_cursor_index < self.states.items.len) {
        // yes, this is the same as React
        return error.RulesOfHooksViolated;
    }
    self.state_cursor_index = 0;

    var buffer: [8]u8 = undefined;
    const bytes_read = try self.tty.read(&buffer);

    if (blk: {
        if (bytes_read >= 3 and std.mem.eql(u8, buffer[0..3], CSI ++ CSIArrowDown)) {
            break :blk .{ .action = .ArrowDown };
        } else if (bytes_read >= 3 and std.mem.eql(u8, buffer[0..3], CSI ++ CSIArrowUp)) {
            break :blk .{ .action = .ArrowUp };
        } else if (bytes_read == 1 and buffer[0] == 13) {
            break :blk .{ .action = .Enter };
        } else if (bytes_read == 1 and buffer[0] == 127) {
            break :blk .{ .action = .Backspace };
        } else if (bytes_read == 1 and buffer[0] >= 32 and buffer[0] <= 126) {
            break :blk .{ .printable_ascii = buffer[0] };
        }
        break :blk null;
    }) |input| {
        for (self.tick_input_handlers.items) |handler| {
            try handler.call_handler(handler.context, input.?);
        }
    }

    self.tick_input_handlers.clearRetainingCapacity();
    self.arena.reset(.retain_capacity);
}

pub fn use_state(T: type, initial_value: T) !*T {
    defer self.state_cursor_index += 1;
    if (self.state_cursor_index < self.states.items.len) {
        return @ptrCast(@alignCast(self.states.items[self.state_cursor_index]));
    } else {
        const actual_state = try self.allocator.create(T);
        actual_state.* = initial_value;
        try self.states.append(self.allocator, @ptrCast(@alignCast(actual_state)));

        return actual_state;
    }
}

pub fn use_input_handler(
    context: anytype,
    comptime handler: fn (context: @TypeOf(context), input: Input) anyerror!void,
) !void {
    const allocator = self.arena.allocator();
    const owned_context = try allocator.create(@TypeOf(context));
    owned_context.* = context;

    try self.tick_input_handlers.append(
        self.allocator,
        .{
            .context = @ptrCast(@alignCast(owned_context)),
            .handler = (struct {
                fn call_handler(any_ctx: *anyopaque, input: Input) anyerror!void {
                    try handler(@ptrCast(@alignCast(any_ctx)), input);
                }
            }).call_handler,
        },
    );
}
