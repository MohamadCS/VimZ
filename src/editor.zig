const std = @import("std");
const vaxis = @import("vaxis");
const utils = @import("utils.zig");
const Vimz = @import("app.zig");
const TextBuffer = @import("text_buffer.zig").TextBuffer;

const Allocator = std.mem.Allocator;
const log = std.log.scoped(.main);

const Cmds = std.StaticStringMap(Editor.Motion).initComptime(.{
    .{ "diw", .DeleteWord },
    .{ "daw", .DeleteAroundWord },
    .{ "dd", .DeleteLine },
});

// Devide to App and State
pub const Editor = struct {
    allocator: Allocator,

    text_buffer: TextBuffer,

    top: usize,

    left: usize,

    mode: Vimz.Types.Mode,

    pending_cmd_queue: std.ArrayList(u8),

    cursor: Vimz.Types.CursorState,

    // TODO: change to theme
    fg: vaxis.Color = .{
        .rgb = .{ 87, 82, 121 },
    },

    win_opts: vaxis.Window.ChildOptions = .{},

    const Self = @This();

    pub fn init(allocator: Allocator) !Self {
        return Self{
            .allocator = allocator,
            .text_buffer = try TextBuffer.init(allocator),
            .mode = Vimz.Types.Mode.Normal,
            .cursor = .{},
            .pending_cmd_queue = std.ArrayList(u8).init(allocator),
            .top = 0,
            .left = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        self.text_buffer.deinit();
        self.pending_cmd_queue.deinit();
    }

    pub inline fn getAbsCol(self: Self) usize {
        return self.cursor.col + self.left;
    }

    pub inline fn getAbsRow(self: Self) usize {
        return self.cursor.row + self.top;
    }

    fn tryScroll(self: *Self) void {
        if (self.cursor.row >= self.win_opts.height.? - 1) {
            self.top += 1;
            self.cursor.row -|= 1;
        } else if (self.cursor.row == 0 and self.top > 0) {
            self.top -= 1;
            self.cursor.row +|= 1;
        }

        if (self.cursor.col >= self.win_opts.width.? - 1) {
            self.left += 1;
            self.cursor.col -|= 1;
        } else if (self.cursor.col == 0 and self.left > 0) {
            self.left -= 1;
            self.cursor.col +|= 1;
        }
    }

    pub fn moveAbs(self: *Self, row: usize, col: usize) void {
        if (row < self.top + self.win_opts.height.? - 1 and row >= self.top) {
            self.cursor.row = @intCast(row -| self.top);
        } else if (row < self.cursor.row) {
            self.top = 0;
            self.cursor.row = @intCast(row);
        } else {
            self.top = row -| self.cursor.col;
        }

        if (col < self.left + self.win_opts.width.? - 1 and col >= self.left) {
            self.cursor.col = @intCast(col -| self.left);
        } else if (col < self.cursor.col) {
            self.left = 0;
            self.cursor.col = @intCast(col);
        } else {
            self.left = col -| self.cursor.col;
        }
    }

    pub fn moveUp(self: *Self, steps: u16) void {
        self.cursor.row -|= steps;
        self.tryScroll();
    }

    pub fn moveDown(self: *Self, steps: u16) void {
        self.cursor.row +|= steps;
        self.tryScroll();
    }

    pub fn moveLeft(self: *Self, steps: u16) void {
        self.cursor.col -|= steps;
        self.tryScroll();
    }

    pub fn moveRight(self: *Self, steps: u16) void {
        self.cursor.col +|= steps;
        self.tryScroll();
    }

    pub fn update(self: *Self) !void {

        // need additional checking
        const lines_count = try self.text_buffer.getLineCount();
        const max_row = lines_count -| 1;

        if (self.getAbsRow() >= max_row) {
            self.top = @min(self.top, lines_count -| 2);
            self.cursor.row = @intCast(max_row -| self.top -| 1);
        }

        const line = try self.text_buffer.getLineInfo(self.getAbsRow());
        const max_col = line.len;

        if (self.mode == Vimz.Types.Mode.Normal) {
            if (self.getAbsCol() >= max_col) {
                self.left = @min(self.left, max_col -| 1);
                self.cursor.col = @intCast(max_col -| self.left -| 1);
            }
        }

        try self.text_buffer.moveCursor(self.getAbsRow(), self.getAbsCol());
    }

    pub fn draw(self: *Self, editorWin: *vaxis.Window) !void {
        const max_row = @min(self.top + editorWin.height, try self.text_buffer.getLineCount());

        for (self.top..max_row, 0..) |row, virt_row| {
            const line = try self.text_buffer.getLineInfo(row);

            if (line.len < self.left) {
                continue;
            }

            // to ensure that we only draw what the screen can show
            const start = self.left;
            const end = @min(start + editorWin.width, line.len);
            for (start..end, 0..) |col, virt_col| {
                editorWin.writeCell(@intCast(virt_col), @intCast(virt_row), vaxis.Cell{ .char = .{
                    .grapheme = try self.text_buffer.getSlicedCharAt(row, col),
                }, .style = .{ .fg = self.fg } });
            }
        }

        editorWin.showCursor(self.cursor.col, self.cursor.row);
    }

    pub fn handleInput(self: *Self, key: vaxis.Key) !void {
        switch (self.mode) {
            .Normal => try self.handleNormalMode(key),
            .Insert => try self.handleInsertMode(key),
            .Pending => try self.handlePendingCommand(key),
        }
    }

    // TODO: Define Actions enum, and then call a function with the
    // actions we want to do, this prevents code duplications
    //

    pub const Motion = union(enum) {
        MoveUp: usize,
        MoveDown: usize,
        MoveLeft: usize,
        MoveRight: usize,
        ChangeMode: Vimz.Types.Mode,
        Quit: void,
        ScrollHalfPageUp: void,
        ScrollHalfPageDown: void,
        DeleteWord: void,
        DeleteAroundWord: void,
        DeleteLine: void,
        NextWord: enum {
            WORD,
            word,
        },
        MoveToEndOfLine: void,
        MoveToStartOfLine: void,
        DeleteInsideWord: void,
        InsertNewLine: void,
        WirteAtCursor: []const TextBuffer.CharType,

        pub fn exec(self: Motion, editor: *Editor) !void {
            switch (self) {
                .MoveLeft => |x| {
                    editor.moveLeft(@intCast(x));
                },
                .MoveRight => |x| {
                    editor.moveRight(@intCast(x));
                },
                .MoveDown => |x| {
                    editor.moveDown(@intCast(x));
                },
                .MoveUp => |x| {
                    editor.moveUp(@intCast(x));
                },
                .MoveToEndOfLine => {
                    const line = try editor.text_buffer.getLineInfo(editor.getAbsRow());
                    editor.moveAbs(editor.getAbsRow(), line.len -| 1);
                },
                .MoveToStartOfLine => {
                    editor.moveAbs(editor.getAbsRow(), 0);
                },
                .Quit => {
                    var app = try Vimz.App.getInstance();
                    app.quit = true;
                },
                .ChangeMode => |mode| {
                    editor.mode = mode;
                },
                .DeleteLine => {
                    try editor.text_buffer.deleteLine(editor.getAbsRow());
                },
                .ScrollHalfPageUp => {
                    editor.top -|= editor.win_opts.height.? / 2;
                    editor.tryScroll();
                },
                .ScrollHalfPageDown => {
                    editor.top +|= editor.win_opts.height.? / 2;
                    editor.tryScroll();
                },
                .WirteAtCursor => |text| {
                    try editor.text_buffer.insert(text, editor.getAbsRow(), editor.getAbsCol());
                    editor.moveRight(1);
                },
                .NextWord => |t| {
                    const next_pos = try editor.text_buffer.findNextWord(editor.getAbsRow(), editor.getAbsCol(), switch (t) {
                        .word => true,
                        .WORD => false,
                    });
                    editor.moveAbs(next_pos.row, next_pos.col);
                },
                inline else => {},
            }
        }
    };

    pub fn handleInsertMode(self: *Self, key: vaxis.Key) !void {
        if (key.matches('c', .{ .ctrl = true }) or key.matches(vaxis.Key.escape, .{})) {
            try Motion.exec(Motion{ .ChangeMode = Vimz.Types.Mode.Normal }, self);
            try Motion.exec(.{ .MoveLeft = 1 }, self);
        } else if (key.matches(vaxis.Key.enter, .{})) {
            try self.text_buffer.insert("\n", self.getAbsRow(), self.getAbsCol());
            try Motion.exec(.{ .MoveDown = 1 }, self);
        }
        // else if (key.matches(vaxis.Key.backspace, .{})) {
        //     if (self.cursor.col == 0) {
        //         self.moveUp(1);
        //         // Go to the end of the last line
        //     } else {
        //         self.moveLeft(1);
        //     }
        //     try self.buff.deleteBackwards(GapBuffer.SearchPolicy{ .Number = 1 }, true);
        // }
        else if (key.text) |text| {
            try Motion.exec(Motion{ .WirteAtCursor = text }, self);
        }
    }

    pub fn handleNormalMode(self: *Self, key: vaxis.Key) !void {
        if (key.matches('l', .{})) {
            try Motion.exec(Motion{ .MoveRight = 1 }, self);
        } else if (key.matches('j', .{})) {
            try Motion.exec(Motion{ .MoveDown = 1 }, self);
        } else if (key.matches('h', .{})) {
            try Motion.exec(Motion{ .MoveLeft = 1 }, self);
        } else if (key.matches('k', .{})) {
            try Motion.exec(Motion{ .MoveUp = 1 }, self);
        } else if (key.matches('q', .{})) {
            try Motion.exec(Motion{ .Quit = void{} }, self);
        } else if (key.matchesAny(&.{ 'i', 'a' }, .{})) {
            try Motion.exec(Motion{ .ChangeMode = Vimz.Types.Mode.Insert }, self);
            if (key.matches('a', .{})) {
                const line = try self.text_buffer.getLineInfo(self.getAbsRow());
                if (line.len > 0) {
                    try Motion.exec(.{ .MoveRight = 1 }, self);
                }
            }
        } else if (key.matches('d', .{ .ctrl = true })) {
            try Motion.exec(Motion{ .ScrollHalfPageDown = void{} }, self);
        } else if (key.matches('u', .{ .ctrl = true })) {
            try Motion.exec(Motion{ .ScrollHalfPageUp = void{} }, self);
        } else if (key.matches('$', .{})) {
            try Motion.exec(Motion{ .MoveToEndOfLine = void{} }, self);
        } else if (key.matches('0', .{})) {
            try Motion.exec(Motion{ .MoveToStartOfLine = void{} }, self);
        } else if (key.matches('d', .{})) {
            try Motion.exec(Motion{ .ChangeMode = Vimz.Types.Mode.Pending }, self);
            try self.pending_cmd_queue.append(@intCast(key.codepoint));
        } else if (key.matches('w', .{})) {
            try Motion.exec(Motion{ .NextWord = .word }, self);
        } else if (key.matches('W', .{})) {
            try Motion.exec(Motion{ .NextWord = .WORD }, self);
        }
    }

    // TODO : Find a better command handling system, for example a state machine
    pub fn handlePendingCommand(self: *Self, key: vaxis.Key) !void {
        try self.pending_cmd_queue.append(@intCast(key.codepoint));
        // For testing purposes
        if (self.pending_cmd_queue.items.len > 5) {
            self.pending_cmd_queue.deinit();
            self.pending_cmd_queue = std.ArrayList(u8).init(self.allocator);

            try Motion.exec(Motion{ .ChangeMode = Vimz.Types.Mode.Normal }, self);
            return;
        }

        if (Cmds.get(self.pending_cmd_queue.items)) |cmd| {
            try Motion.exec(cmd, self);
            try Motion.exec(Motion{ .ChangeMode = Vimz.Types.Mode.Normal }, self);

            self.pending_cmd_queue.deinit();
            self.pending_cmd_queue = std.ArrayList(u8).init(self.allocator);
        }
    }
};
