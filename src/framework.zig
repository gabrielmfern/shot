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
tty: Tty,

states: std.ArrayList(*anyopaque),
/// The current index that will be used for the call of `use_state` in this tick
state_cursor_index: usize,

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
        ArrowLeft,
        ArrowRight,
        Enter,
        Backspace,
    },
    printable_ascii: u8,
};

pub const Tty = struct {
    file: std.fs.File,
    original_termios: std.posix.termios,

    pub fn init() !@This() {
        const tty = try std.fs.cwd().openFile(
            "/dev/tty",
            .{ .mode = .read_write },
        );
        return .{
            .file = tty,
            .original_termios = try std.posix.tcgetattr(tty.handle),
        };
    }

    pub fn enter_raw_mode(tty: *@This()) !void {
        var raw = tty.original_termios;
        raw.lflag.ECHO = false;
        raw.lflag.ICANON = false;
        raw.lflag.IEXTEN = false;
        raw.iflag.IXON = false;
        raw.iflag.ICRNL = false;
        raw.iflag.INPCK = false;
        raw.iflag.ISTRIP = false;
        try std.posix.tcsetattr(tty.file.handle, .FLUSH, raw);
    }

    pub fn deinit(tty: *@This()) void {
        std.posix.tcsetattr(tty.file.handle, .FLUSH, tty.original_termios) catch |err| {
            std.log.err("Failed to restore original terminal settings: {}", .{err});
        };
        tty.file.close();
    }
};

var self: @This() = undefined;

/// Allocator is expected to be an Arena that clears all of the data it
/// allocates automatically
pub fn init(
    allocator: std.mem.Allocator,
    stderr: *std.io.Writer,
    tty: Tty,
) !void {
    self = .{
        .arena = std.heap.ArenaAllocator.init(allocator),

        .allocator = allocator,
        .stderr = stderr,
        .tty = tty,

        .states = try std.ArrayList(*anyopaque).initCapacity(allocator, 0),
        .state_cursor_index = 0,

        .last_input = null,
    };
}

pub fn get_terminal_size() !struct { width: usize, height: usize } {
    try write(SaveCursorPosition);
    try self.stderr.flush();
    try write(CSI ++ CSIMoveCursorTo(10_000, 10_000));
    try write(CSI ++ CSIRequestCursorPosition);
    try self.stderr.flush();

    // Read until we find the cursor position response (ESC [ row ; col R)
    // This handles the case where user input is in the buffer before the response
    var response_buf: [32]u8 = undefined;
    var response_len: usize = 0;
    var state: enum { waiting_for_esc, waiting_for_bracket, reading_response } = .waiting_for_esc;

    while (response_len < response_buf.len) {
        var byte: [1]u8 = undefined;
        const bytes_read = try self.tty.file.read(&byte);
        if (bytes_read == 0) break;

        switch (state) {
            .waiting_for_esc => {
                if (byte[0] == '\x1b') {
                    state = .waiting_for_bracket;
                }
                // Discard any other input (user typed characters)
            },
            .waiting_for_bracket => {
                if (byte[0] == '[') {
                    state = .reading_response;
                } else {
                    // Not a CSI sequence, go back to waiting
                    state = .waiting_for_esc;
                }
            },
            .reading_response => {
                if (byte[0] == 'R') {
                    // Found the end of the cursor position response
                    break;
                }
                response_buf[response_len] = byte[0];
                response_len += 1;
            },
        }
    }

    try write(RestoreSavedCursorPosition);
    try self.stderr.flush();

    const response = response_buf[0..response_len];
    if (std.mem.indexOf(u8, response, ";")) |semicolon_index| {
        const row_string = response[0..semicolon_index];
        const col_string = response[semicolon_index + 1 ..];

        const height = try std.fmt.parseInt(usize, row_string, 10);
        const width = try std.fmt.parseInt(usize, col_string, 10);

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

pub fn flush() !void {
    try self.stderr.flush();
}

/// Generally is just blocks until there's user input. But, if it's running
/// after input, it goes through, this time with `last_input = null` which
/// makes sure the entire text UI is rendered with respect to the state in sync
pub fn update() !void {
    if (self.last_input == null) {
        var buffer: [8]u8 = undefined;
        const bytes_read = try self.tty.file.read(&buffer);

        var input: ?Input = null;
        if (bytes_read >= 3 and std.mem.eql(u8, buffer[0..3], CSI ++ CSIArrowDown)) {
            input = Input{ .action = .ArrowDown };
        } else if (bytes_read >= 3 and std.mem.eql(u8, buffer[0..3], CSI ++ CSIArrowUp)) {
            input = Input{ .action = .ArrowUp };
        } else if (bytes_read >= 3 and std.mem.eql(u8, buffer[0..3], CSI ++ CSIArrowLeft)) {
            input = Input{ .action = .ArrowLeft };
        } else if (bytes_read >= 3 and std.mem.eql(u8, buffer[0..3], CSI ++ CSIArrowRight)) {
            input = Input{ .action = .ArrowLeft };
        } else if (bytes_read == 1 and buffer[0] == 13) {
            input = Input{ .action = .Enter };
        } else if (bytes_read == 1 and buffer[0] == 127) {
            input = Input{ .action = .Backspace };
        } else if (bytes_read == 1 and buffer[0] >= 32 and buffer[0] <= 126) {
            input = Input{ .printable_ascii = buffer[0] };
        }

        self.last_input = input;
    } else {
        self.last_input = null;
    }

    if (self.state_cursor_index < self.states.items.len) {
        // yes, this is the same as React
        return error.RulesOfHooksViolated;
    }
    self.state_cursor_index = 0;
    defer _ = self.arena.reset(.retain_capacity);
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
