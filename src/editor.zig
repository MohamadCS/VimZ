const std = @import("std");
const Allocator = std.mem.Allocator;

const vaxis = @import("vaxis");

const utils = @import("utils.zig");
const vimz = @import("app.zig");

const TextBuffer = @import("text_buffer.zig").TextBuffer;
const Trie = @import("trie.zig").Trie;
const log = @import("logger.zig").Logger.log;

// Devide to App and State
pub const Editor = struct {
    allocator: Allocator,

    text_buffer: TextBuffer,

    top: usize,

    left: usize,

    mode: vimz.Types.Mode,

    pending_cmd_queue: std.ArrayList(u8),

    cmd_trie: Trie,

    cursor: vimz.Types.CursorState,

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
            .mode = vimz.Types.Mode.Normal,
            .cursor = .{},
            .cmd_trie = .{},
            .pending_cmd_queue = std.ArrayList(u8).init(allocator),
            .top = 0,
            .left = 0,
        };
    }

    pub fn setup(self: *Self) !void {
        try self.cmd_trie.init(self.allocator, cmds.keys());
    }

    pub fn deinit(self: *Self) void {
        self.text_buffer.deinit();
        self.cmd_trie.deinit();
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
            self.top = row -| self.cursor.row;
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

        if (self.mode == vimz.Types.Mode.Normal) {
            if (self.getAbsCol() >= max_col) {
                self.left = @min(self.left, max_col -| 1);
                self.cursor.col = @intCast(max_col -| self.left -| 1);
            }
        }
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

    const WordType = enum { WORD, word };

    pub const Motion = union(enum) {
        MoveUp: usize,
        MoveDown: usize,
        MoveLeft: usize,
        MoveRight: usize,
        ChangeMode: vimz.Types.Mode,
        Quit: void,
        ScrollHalfPageUp: void,
        ScrollHalfPageDown: void,
        DeleteWord: void,

        EndOfWord: WordType,
        NextWord: WordType,
        PrevWord: WordType,
        DeleteInsideWord: WordType,
        LastLine: void,
        FirstLine: void,
        DeleteAroundWord: void,
        DeleteLine: void,
        MoveToEndOfLine: void,
        MoveToStartOfLine: struct { stopAfterWs: bool },
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
                .MoveToStartOfLine => |res| {
                    const line = try editor.text_buffer.getLineInfo(editor.getAbsRow());
                    var col: usize = 0;

                    if (res.stopAfterWs) {
                        for (0..line.len) |i| {
                            const curr_ch = try editor.text_buffer.getCharAt(editor.getAbsRow(), i);
                            if (curr_ch != ' ') {
                                col = i;
                                break;
                            }
                        }
                    }

                    editor.moveAbs(editor.getAbsRow(), col);
                },
                .Quit => {
                    var app = try vimz.App.getInstance();
                    app.quit = true;
                },
                .ChangeMode => |mode| {
                    editor.mode = mode;
                },
                .DeleteWord => {
                    try editor.text_buffer.deleteWord(editor.getAbsRow(), editor.getAbsCol());
                },
                .DeleteLine => {
                    try editor.text_buffer.deleteLine(editor.getAbsRow());
                },
                .ScrollHalfPageUp => {
                    editor.moveAbs(editor.getAbsRow() -| editor.win_opts.height.? / 2, editor.getAbsCol());
                },
                .ScrollHalfPageDown => {
                    editor.moveAbs(editor.getAbsRow() +| editor.win_opts.height.? / 2, editor.getAbsCol());
                },
                .WirteAtCursor => |text| {
                    try editor.text_buffer.insert(text, editor.getAbsRow(), editor.getAbsCol());
                    editor.moveRight(1);
                },
                .FirstLine => {
                    editor.moveAbs(0, editor.getAbsCol());
                },
                .LastLine => {
                    const line_count = try editor.text_buffer.getLineCount();
                    editor.moveAbs(line_count -| 1, editor.getAbsCol());
                },
                .DeleteInsideWord => |word_t| {
                    const new_pos = try editor.text_buffer.deleteInsideWord(editor.getAbsRow(), editor.getAbsCol(), switch (word_t) {
                        .word => true,
                        .WORD => false,
                    });
                    editor.moveAbs(new_pos.row, new_pos.col);
                },
                .NextWord => |word_t| {
                    const next_pos = try editor.text_buffer.findNextWord(editor.getAbsRow(), editor.getAbsCol(), switch (word_t) {
                        .word => true,
                        .WORD => false,
                    });
                    editor.moveAbs(next_pos.row, next_pos.col);
                },
                .PrevWord => |word_t| {
                    const next_pos = try editor.text_buffer.findWordBeginig(editor.getAbsRow(), editor.getAbsCol(), switch (word_t) {
                        .word => true,
                        .WORD => false,
                    });
                    editor.moveAbs(next_pos.row, next_pos.col);
                },
                .EndOfWord => |word_t| {
                    // TODO: Support jumping to next line
                    const pos = try editor.text_buffer.findWordEnd(editor.getAbsRow(), editor.getAbsCol(), switch (word_t) {
                        .word => true,
                        .WORD => false,
                    });
                    editor.moveAbs(pos.row, pos.col);
                },
                .InsertNewLine => {
                    try editor.text_buffer.insert("\n", editor.getAbsRow(), editor.getAbsCol());
                },

                inline else => {},
            }
        }
    };

    pub fn handleInsertMode(self: *Self, key: vaxis.Key) !void {
        if (key.matches('c', .{ .ctrl = true }) or key.matches(vaxis.Key.escape, .{})) {
            try Motion.exec(.{ .ChangeMode = .Normal }, self);
            try Motion.exec(.{ .MoveLeft = 1 }, self);
        } else if (key.matches(vaxis.Key.enter, .{})) {
            try Motion.exec(.{ .InsertNewLine = {} }, self);
            try Motion.exec(.{ .MoveDown = 1 }, self);
            try Motion.exec(.{ .MoveToStartOfLine = .{ .stopAfterWs = false } }, self);
        } else if (key.text) |text| {
            try Motion.exec(Motion{ .WirteAtCursor = text }, self);
        }
    }

    // Switch is cleaner, but this is the vaxis limitation.
    pub fn handleNormalMode(self: *Self, key: vaxis.Key) !void {
        if (key.matches('l', .{})) {
            try Motion.exec(.{ .MoveRight = 1 }, self);
        } else if (key.matches('j', .{})) {
            try Motion.exec(.{ .MoveDown = 1 }, self);
        } else if (key.matches('h', .{})) {
            try Motion.exec(.{ .MoveLeft = 1 }, self);
        } else if (key.matches('k', .{})) {
            try Motion.exec(.{ .MoveUp = 1 }, self);
        } else if (key.matches('q', .{})) {
            try Motion.exec(.{ .Quit = {} }, self);
        } else if (key.matchesAny(&.{ 'i', 'a' }, .{})) {
            try Motion.exec(.{ .ChangeMode = .Insert }, self);
            if (key.matches('a', .{})) {
                const line = try self.text_buffer.getLineInfo(self.getAbsRow());
                if (line.len > 0) {
                    try Motion.exec(.{ .MoveRight = 1 }, self);
                }
            }
        } else if (key.matches('d', .{ .ctrl = true })) {
            try Motion.exec(.{ .ScrollHalfPageDown = {} }, self);
        } else if (key.matches('e', .{})) {
            try Motion.exec(.{ .EndOfWord = .word }, self);
        } else if (key.matches('E', .{})) {
            try Motion.exec(.{ .EndOfWord = .WORD }, self);
        } else if (key.matches('u', .{ .ctrl = true })) {
            try Motion.exec(.{ .ScrollHalfPageUp = {} }, self);
        } else if (key.matches('b', .{})) {
            try Motion.exec(.{ .PrevWord = .word }, self);
        } else if (key.matches('A', .{})) {
            try Motion.exec(.{ .ChangeMode = .Insert }, self);
            try Motion.exec(.{ .MoveToEndOfLine = {} }, self);
            const line = try self.text_buffer.getLineInfo(self.getAbsRow());
            if (line.len > 0) {
                try Motion.exec(.{ .MoveRight = 1 }, self);
            }
        } else if (key.matches('I', .{})) {
            try Motion.exec(.{ .MoveToStartOfLine = .{ .stopAfterWs = true } }, self);
            try Motion.exec(.{ .ChangeMode = .Insert }, self);
        } else if (key.matches('B', .{})) {
            try Motion.exec(.{ .PrevWord = .WORD }, self);
        } else if (key.matches('$', .{})) {
            try Motion.exec(.{ .MoveToEndOfLine = {} }, self);
        } else if (key.matches('0', .{})) {
            try Motion.exec(.{ .MoveToStartOfLine = .{ .stopAfterWs = false } }, self);
        } else if (key.matches('_', .{})) {
            try Motion.exec(.{ .MoveToStartOfLine = .{ .stopAfterWs = true } }, self);
        } else if (key.matches('G', .{})) {
            try Motion.exec(.{ .LastLine = {} }, self);
        } else if (key.matches('w', .{})) {
            try Motion.exec(.{ .NextWord = .word }, self);
        } else if (key.matches('W', .{})) {
            try Motion.exec(.{ .NextWord = .WORD }, self);
        } else if (key.matches('O', .{})) {
            try Motion.exec(.{ .MoveToStartOfLine = .{ .stopAfterWs = false } }, self);
            try Motion.exec(.{ .InsertNewLine = {} }, self);
            try Motion.exec(.{ .ChangeMode = .Insert }, self);
        } else if (key.matches('o', .{})) {
            try Motion.exec(.{ .MoveToEndOfLine = {} }, self);
            try Motion.exec(.{ .ChangeMode = .Insert }, self);
            try Motion.exec(.{ .MoveRight = 1 }, self);
            try Motion.exec(.{ .InsertNewLine = {} }, self);
            try Motion.exec(.{ .MoveDown = 1 }, self);
            try Motion.exec(.{ .MoveToStartOfLine = .{ .stopAfterWs = false } }, self);
        } else {
            try Motion.exec(.{ .ChangeMode = .Pending }, self);
            try self.handlePendingCommand(key);
        }
    }

    pub fn executePendingCommand(self: *Self, cmd_str: []const u8) !void {
        if (cmds.get(cmd_str)) |motions| {
            for (motions) |motion| {
                try Motion.exec(motion, self);
                if (self.mode == vimz.Types.Mode.Pending) {
                    try Motion.exec(Motion{ .ChangeMode = vimz.Types.Mode.Normal }, self);
                }
            }
        }
    }

    // TODO : Find a better command handling system, for example a state machine
    pub fn handlePendingCommand(self: *Self, key: vaxis.Key) !void {
        // New handling System:
        // while its a number caluclate it

        if (key.matches('c', .{ .ctrl = true }) or key.matches(vaxis.Key.escape, .{})) {
            self.cmd_trie.reset();
            try Motion.exec(Motion{ .ChangeMode = vimz.Types.Mode.Normal }, self);
        }

        const key_text = key.text orelse return;
        const result = try self.cmd_trie.step(key_text[0]);
        switch (result) {
            .Accept => {
                try self.executePendingCommand(self.cmd_trie.getCurrentWord());
                self.cmd_trie.reset();
            },
            .Reject => {
                self.cmd_trie.reset();
                try Motion.exec(Motion{ .ChangeMode = vimz.Types.Mode.Normal }, self);
            },
            .Deciding => {},
        }
    }
};

const cmds = std.StaticStringMap([]const Editor.Motion).initComptime(.{
    .{
        "dw",
        &.{
            .DeleteWord,
        },
    },
    .{
        "diw",
        &.{
            .{ .DeleteInsideWord = .word },
        },
    },
    .{
        "diW",
        &.{
            .{ .DeleteInsideWord = .WORD },
        },
    },
    .{
        "cw",
        &.{
            .DeleteWord,
            .{ .ChangeMode = vimz.Types.Mode.Insert },
        },
    },
    .{
        "ciw",
        &.{
            .{ .DeleteInsideWord = .word },
            .{ .ChangeMode = vimz.Types.Mode.Insert },
        },
    },
    .{
        "ciW", &.{
            .{ .DeleteInsideWord = .WORD },
            .{ .ChangeMode = vimz.Types.Mode.Insert },
        },
    },
    .{
        "dd",
        &.{
            .DeleteLine,
        },
    },
    .{
        "gg",
        &.{
            .FirstLine,
        },
    },
});
