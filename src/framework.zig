const std = @import("std");

pub const CSI = "\x1b[";
pub const CSIClearScreen = "2J";
pub const CSICursorToStart = "H";
pub const SaveCursorPosition = "\x1b7";
pub const RestoreSavedCursorPosition = "\x1b8";
pub const CSIRequestCursorPosition = "6n";
pub inline fn CSIMoveCursorTo(
    comptime row: usize,
    comptime column: usize,
) *const [std.fmt.count("{d};{d}H", .{ row, column })]u8 {
    return std.fmt.comptimePrint("{d};{d}H", .{ row, column });
}
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
stderr: *std.io.Writer,
tty: std.fs.File,

states: std.ArrayList(*anyopaque),
/// The current index that will be used for the call of `use_state` in this tick
state_cursor_index: usize,

tick_input_handlers: std.ArrayList(InputHandler),
last_input: ?Input,

const InputHandler = struct {
    context: *anyopaque,
    call_handler: *const fn (context: *anyopaque, input: Input) anyerror!void,
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
    stderr: *std.io.Writer,
    tty: std.fs.File,
) !void {
    self = .{
        .arena = std.heap.ArenaAllocator.init(allocator),

        .allocator = allocator,
        .stderr = stderr,
        .tty = tty,

        .states = try std.ArrayList(*anyopaque).initCapacity(allocator, 0),
        .state_cursor_index = 0,

        .tick_input_handlers = try std.ArrayList(InputHandler).initCapacity(allocator, 0),
        .last_input = null,
    };
}

pub fn get_terminal_size() !struct { width: usize, height: usize } {
    try write(SaveCursorPosition);
    try self.stderr.flush();
    try write(CSI ++ CSIMoveCursorTo(10_000, 10_000));
    try write(CSI ++ CSIRequestCursorPosition);
    try self.stderr.flush();

    var buffer: [(CSI ++ "10000;10000R").len]u8 = undefined;
    const bytes_read = try self.tty.read(&buffer);
    const input = buffer[0..bytes_read];

    try write(RestoreSavedCursorPosition);
    try self.stderr.flush();

    if (std.mem.indexOf(
        u8,
        input,
        ";",
    )) |semicolon_index| {
        const column_string = input[2..semicolon_index];
        const row_string = input[semicolon_index + 1 .. bytes_read - 1];

        const height = try std.fmt.parseInt(usize, column_string, 10);
        const width = try std.fmt.parseInt(usize, row_string, 10);

        return .{
            .width = width,
            .height = height,
        };
    } else {
        return error.CouldNotDetermineTerminalSize;
    }
}

pub fn use_stderr() *std.io.Writer {
    return self.stderr;
}

pub fn use_allocator() std.mem.Allocator {
    return self.allocator;
}

/// thin wrapper around stderr.write, for convenience
pub fn write(bytes: []const u8) !void {
    _ = try self.stderr.write(bytes);
}

/// thin wrapper around stderr.print, for convenience
pub fn print(comptime fmt: []const u8, args: anytype) !void {
    try self.stderr.print(fmt, args);
}

pub fn tick() !void {
    if (self.state_cursor_index < self.states.items.len) {
        // yes, this is the same as React
        return error.RulesOfHooksViolated;
    }
    self.state_cursor_index = 0;

    var buffer: [8]u8 = undefined;
    const bytes_read = try self.tty.read(&buffer);

    var input: ?Input = null;
    if (bytes_read >= 3 and std.mem.eql(u8, buffer[0..3], CSI ++ CSIArrowDown)) {
        input = Input{ .action = .ArrowDown };
    } else if (bytes_read >= 3 and std.mem.eql(u8, buffer[0..3], CSI ++ CSIArrowUp)) {
        input = Input{ .action = .ArrowUp };
    } else if (bytes_read == 1 and buffer[0] == 13) {
        input = Input{ .action = .Enter };
    } else if (bytes_read == 1 and buffer[0] == 127) {
        input = Input{ .action = .Backspace };
    } else if (bytes_read == 1 and buffer[0] >= 32 and buffer[0] <= 126) {
        input = Input{ .printable_ascii = buffer[0] };
    }

    self.last_input = input;

    if (input != null) {
        for (self.tick_input_handlers.items) |handler| {
            try handler.call_handler(handler.context, input.?);
        }
    }

    self.tick_input_handlers.clearRetainingCapacity();
    _ = self.arena.reset(.retain_capacity);
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

pub fn use_last_input() ?Input {
    return self.last_input;
}

pub fn use_input_handler(
    context: anytype,
    comptime handler: fn (context: *@TypeOf(context), input: Input) anyerror!void,
) !void {
    const allocator = self.arena.allocator();
    const owned_context = try allocator.create(@TypeOf(context));
    owned_context.* = context;

    try self.tick_input_handlers.append(
        self.allocator,
        .{
            .context = @ptrCast(@alignCast(owned_context)),
            .call_handler = &(struct {
                fn call_handler(any_ctx: *anyopaque, input: Input) anyerror!void {
                    try handler(@ptrCast(@alignCast(any_ctx)), input);
                }
            }).call_handler,
        },
    );
}
