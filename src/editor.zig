const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const vaxis = @import("vaxis");

const utils = @import("utils.zig");
const vimz = @import("vimz.zig");

const TextBuffer = @import("text_buffer.zig").TextBuffer;
const Trie = @import("trie.zig").Trie;
const log = @import("logger.zig").Logger.log;

// Devide to App and State
pub const Editor = struct {
    allocator: Allocator,

    core: *vimz.Core = undefined,

    text_buffer: TextBuffer,

    file_name: [:0]const u8,

    last_cmd: ?[]const u8,

    clipboard_buff: ?[]TextBuffer.CharType,

    repeat: ?usize,

    mode: vimz.Mode,

    cmd_trie: Trie,

    cursor: vimz.CursorState,

    vis_start: vimz.Position,

    top: usize,

    left: usize,

    win_dims: struct {
        buff_win_dims: vaxis.Window.ChildOptions = .{},
        text_win_dims: vaxis.Window.ChildOptions = .{},
        lines_col_dims: vaxis.Window.ChildOptions = .{},
    } = .{},

    row_numbers: ?[]const []const TextBuffer.CharType,

    pub const indent_size: usize = 4;

    const Self = @This();

    pub fn init(allocator: Allocator) !Self {
        return Self{
            .allocator = allocator,
            .text_buffer = try TextBuffer.init(allocator),
            .mode = .Normal,
            .cursor = .{},
            .cmd_trie = .{},
            .top = 0,
            .left = 0,
            .row_numbers = null,
            .file_name = "",
            .last_cmd = null,
            .repeat = null,
            .vis_start = .{},
            .clipboard_buff = null,
        };
    }

    pub fn setup(self: *Self, core: *vimz.Core) !void {
        self.core = core;
        try self.cmd_trie.init(self.allocator, cmds.keys());
        try self.readFile();
    }

    pub fn deinit(self: *Self) void {
        self.text_buffer.deinit();
        self.cmd_trie.deinit();
        if (self.clipboard_buff) |buff| self.allocator.free(buff);

        if (self.row_numbers) |row_numbers| {
            for (row_numbers) |num_slice| {
                self.allocator.free(num_slice);
            }
            self.allocator.free(row_numbers);
        }
    }

    pub inline fn getAbsCursorPos(self: Self) vimz.Position {
        return .{
            .row = self.getAbsRow(),
            .col = self.getAbsCol(),
        };
    }

    pub inline fn getAbsCol(self: Self) usize {
        return self.cursor.col + self.left;
    }

    inline fn getAbsRow(self: Self) usize {
        return self.cursor.row + self.top;
    }

    fn tryScroll(self: *Self) void {
        const height = self.win_dims.text_win_dims.height.?;
        const width = self.win_dims.text_win_dims.width.?;
        if (self.cursor.row >= height -| 1) {
            self.top += 1;
            self.cursor.row -|= 1;
        } else if (self.cursor.row == 0 and self.top > 0) {
            self.top -= 1;
            self.cursor.row +|= 1;
        }

        if (self.cursor.col >= width -| 1) {
            self.left += 1;
            self.cursor.col -|= 1;
        } else if (self.cursor.col == 0 and self.left > 0) {
            self.left -= 1;
            self.cursor.col +|= 1;
        }
    }

    pub fn isSaved(self: *Self) bool {
        return !self.text_buffer.changed;
    }

    fn readFile(self: *Self) !void {
        var args = std.process.args();

        _ = args.next().?;

        if (args.next()) |arg| {
            self.file_name = arg;
        } else {
            return;
        }

        var file = std.fs.cwd().openFile(self.file_name, .{}) catch |err| {
            return err;
        };
        defer file.close();

        const file_size = (try file.stat()).size;
        const file_contents = try file.readToEndAlloc(self.allocator, file_size);

        defer self.allocator.free(file_contents);

        try self.text_buffer.insert(file_contents, self.getAbsRow(), self.getAbsCol());
        try self.text_buffer.moveCursor(0, 0);
        self.text_buffer.changed = false;
    }

    pub fn moveAbs(self: *Self, row: usize, col: usize) void {
        const height = self.win_dims.text_win_dims.height.?;
        const width = self.win_dims.text_win_dims.width.?;

        if (row < self.top + height - 1 and row >= self.top) {
            self.cursor.row = @intCast(row -| self.top);
        } else if (row < self.cursor.row) {
            self.top = 0;
            self.cursor.row = @intCast(row);
        } else {
            self.top = row -| self.cursor.row;
        }

        if (col < self.left + width - 1 and col >= self.left) {
            self.cursor.col = @intCast(col -| self.left);
        } else if (col < self.cursor.col) {
            self.left = 0;
            self.cursor.col = @intCast(col);
        } else {
            self.left = col -| self.cursor.col;
        }
    }

    fn moveUp(self: *Self, steps: u16) void {
        self.cursor.row -|= steps;
        self.tryScroll();
    }

    fn moveDown(self: *Self, steps: u16) void {
        self.cursor.row +|= steps;
        self.tryScroll();
    }

    fn moveLeft(self: *Self, steps: u16) void {
        self.cursor.col -|= steps;
        self.tryScroll();
    }

    fn moveRight(self: *Self, steps: u16) void {
        self.cursor.col +|= steps;
        self.tryScroll();
    }

    fn updateDims(self: *Self) !void {
        const win = self.core.vx.window();

        const max_digits = utils.digitNum(usize, try self.text_buffer.getLineCount());

        self.win_dims.buff_win_dims = .{
            .x_off = 0,
            .y_off = 0,
            .width = win.width,
            .height = win.height - 2,
        };

        const x_off = 1;
        self.win_dims.lines_col_dims = .{
            .x_off = x_off,
            .y_off = 0,
            .width = @intCast(max_digits), // should be current line digit num
            .height = self.win_dims.buff_win_dims.height.?,
        };

        self.win_dims.text_win_dims = .{
            .x_off = @intCast(max_digits + 1 + x_off),
            .y_off = 0,
            .width = @intCast(self.win_dims.buff_win_dims.width.? -| max_digits),
            .height = self.win_dims.buff_win_dims.height.?,
        };
    }

    pub fn update(self: *Self) !void {
        try self.updateDims();
        const lines_count = try self.text_buffer.getLineCount();
        const max_row = lines_count -| 1;

        if (self.getAbsRow() >= max_row) {
            self.top = @min(self.top, lines_count -| 2);
            self.cursor.row = @intCast(max_row -| self.top -| 1);
        }

        const line = try self.text_buffer.getLineInfo(self.getAbsRow());
        const max_col = line.len;

        if (self.mode == .Normal or self.mode == .Visual) {
            if (self.getAbsCol() >= max_col) {
                self.left = @min(self.left, max_col -| 1);
                self.cursor.col = @intCast(max_col -| self.left -| 1);
            }
        }

        try self.updateRowNumbers();
    }

    fn updateRowNumbers(self: *Self) !void {
        if (self.row_numbers) |row_numbers| {
            for (row_numbers) |num_slice| {
                self.allocator.free(num_slice);
            }
            self.allocator.free(row_numbers);
        }

        const height = self.win_dims.lines_col_dims.height.?;
        var slices = try self.allocator.alloc([]const TextBuffer.CharType, height);

        for (0..slices.len) |row| {
            const row_num = if (row == self.cursor.row) (self.getAbsRow() + 1) else (@max(row, self.cursor.row) - @min(row, self.cursor.row));

            slices[row] = try std.fmt.allocPrint(self.allocator, "{}", .{row_num});
        }
        self.row_numbers = slices;
    }

    fn highlight(self: Self, row: usize, col: usize) bool {
        switch (self.mode) {
            .Visual => {},
            else => {
                return false;
            },
        }

        const min_row = @min(self.getAbsRow(), self.vis_start.row);
        const max_row = @max(self.getAbsRow(), self.vis_start.row);
        const max_rows_col = if (max_row == self.getAbsRow()) self.getAbsCol() else self.vis_start.col;
        const min_rows_col = if (min_row == self.getAbsRow()) self.getAbsCol() else self.vis_start.col;

        const min_col = @min(self.getAbsCol(), self.vis_start.col);
        const max_col = @max(self.getAbsCol(), self.vis_start.col);

        if (row < max_row and row > min_row) {
            return true;
        } else if (row == max_row and row == min_row) {
            if (col >= min_col and col <= max_col) {
                return true;
            }
        } else if (row == max_row) {
            if (col <= max_rows_col) {
                return true;
            }
        } else if (row == min_row) {
            if (col >= min_rows_col) {
                return true;
            }
        }

        return false;
    }

    fn copy(self: *Self, start: vimz.Position, end: vimz.Position) !void {
        if (self.clipboard_buff) |buff| {
            self.allocator.free(buff);
        }

        self.clipboard_buff = try self.text_buffer.getSliceCopy(self.allocator, start, end);
    }

    pub fn draw(self: *Self, editorWin: *vaxis.Window) !void {
        const text_win = editorWin.child(self.win_dims.text_win_dims);
        const line_win = editorWin.child(self.win_dims.lines_col_dims);
        const theme = try self.core.api.getTheme();

        const line_win_max_row = @min(text_win.height, try self.text_buffer.getLineCount() -| self.top -| 1);
        for (0..line_win_max_row) |row| {
            const num_width = self.row_numbers.?[row].len;
            for (0..num_width) |i| {
                const col = line_win.width + i -| num_width;
                line_win.writeCell(@intCast(col), @intCast(row), vaxis.Cell{ .char = .{
                    .grapheme = self.row_numbers.?[row][i .. i + 1],
                }, .style = .{
                    .fg = theme.fg,
                    .bg = theme.bg,
                } });
            }
        }

        const text_win_max_row = @min(self.top + text_win.height, try self.text_buffer.getLineCount());
        for (self.top..text_win_max_row, 0..) |row, virt_row| {
            const line = try self.text_buffer.getLineInfo(row);

            if (line.len < self.left) {
                continue;
            }

            // to ensure that we only draw what the screen can show
            const start = self.left;
            const end = @min(start + text_win.width, line.len);

            if (line.len == 0 and self.highlight(row, 0)) {
                text_win.writeCell(0, @intCast(virt_row), vaxis.Cell{ .char = .{
                    .grapheme = " ",
                }, .style = .{
                    .fg = theme.fg,
                    .bg = theme.highlight,
                } });
            }

            for (start..end, 0..) |col, virt_col| {
                text_win.writeCell(@intCast(virt_col), @intCast(virt_row), vaxis.Cell{ .char = .{
                    .grapheme = try self.text_buffer.getSlicedCharAt(row, col),
                }, .style = .{
                    .fg = theme.text,
                    .bg = if (self.highlight(row, col)) theme.highlight else theme.bg,
                } });
            }
        }

        text_win.showCursor(self.cursor.col, self.cursor.row);
    }

    pub fn handleInput(self: *Self, key: vaxis.Key) !void {

        // For some reason, vaxis enters with this key pressed
        if (key.codepoint == vaxis.Key.f3) {
            return;
        }
        switch (self.mode) {
            .Normal => try self.handleNormalMode(key),
            .Insert => try self.handleInsertMode(key),
            .Pending => try self.handlePendingCommand(key),
            .Visual => try self.handleVisualMode(key),
        }
    }

    const WordType = enum { WORD, word };

    pub const Motion = union(enum) {
        MoveUp: usize,
        MoveDown: usize,
        MoveLeft: usize,
        MoveRight: usize,
        ChangeMode: vimz.Mode,
        Quit: void,
        ScrollHalfPageUp: void,
        ScrollHalfPageDown: void,
        DeleteWord: void,
        EndOfWord: WordType,
        NextWord: WordType,
        PrevWord: WordType,
        DeleteInsideWord: WordType,
        LastLine: void,
        DeleteUnderCursor: void,
        FirstLine: void,
        Indent: usize,
        DeleteAroundWord: void,
        DeleteLine: struct {
            include_end_line: bool,
            start_idx: usize,
        },
        MoveToEndOfLine: void,
        MoveToStartOfLine: struct {
            stopAfterWs: bool,
        },
        InsertNewLine: void,
        DeleteInterval: struct {
            start: vimz.Position,
            end: vimz.Position,
        },
        AppendNextLine: void,
        Yank: struct {
            start: vimz.Position,
            end: vimz.Position,
        },
        WriteAtCursor: []const TextBuffer.CharType,
        Replicate: struct {
            key: vaxis.Key,
            as_mode: vimz.Mode,
        },
        SaveFile: void,
        Past: enum {
            BeforeCursor,
            AfterCursor,
        },

        pub fn exec(self: Motion, editor: *Editor) anyerror!void {
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

                .Yank => |st| {
                    try editor.copy(st.start, st.end);
                },

                .MoveToStartOfLine => |res| {
                    const line = try editor.text_buffer.getLineInfo(editor.getAbsRow());
                    var col: usize = 0;

                    if (res.stopAfterWs) {
                        for (0..line.len) |i| {
                            const curr_ch = try editor.text_buffer.getCharAt(editor.getAbsRow(), i);
                            col = i;
                            if (curr_ch != ' ') {
                                break;
                            }
                        }
                    }

                    editor.moveAbs(editor.getAbsRow(), col);
                },
                .Quit => {
                    editor.core.quit = true;
                },
                .ChangeMode => |mode| {
                    editor.mode = mode;
                },
                .DeleteLine => |st| {
                    const line = try editor.text_buffer.getLineInfo(editor.getAbsRow());
                    _ = try editor.text_buffer.deleteInterval(
                        .{
                            .row = editor.getAbsRow(),
                            .col = st.start_idx,
                        },
                        .{
                            .row = editor.getAbsRow(),
                            .col = if (st.include_end_line) line.len else line.len -| 1,
                        },
                    );
                },
                .ScrollHalfPageUp => {
                    editor.moveAbs(editor.getAbsRow() -| editor.win_dims.text_win_dims.height.? / 2, editor.getAbsCol());
                },
                .ScrollHalfPageDown => {
                    editor.moveAbs(editor.getAbsRow() +| editor.win_dims.text_win_dims.height.? / 2, editor.getAbsCol());
                },
                .WriteAtCursor => |text| {
                    try editor.text_buffer.insert(text, editor.getAbsRow(), editor.getAbsCol());
                    editor.moveRight(@intCast(text.len));
                },
                .FirstLine => {
                    editor.moveAbs(0, editor.getAbsCol());
                },
                .LastLine => {
                    const line_count = try editor.text_buffer.getLineCount();
                    editor.moveAbs(line_count -| 1, editor.getAbsCol());
                },
                .DeleteInsideWord => |word_t| {
                    const subWord = switch (word_t) {
                        .word => true,
                        .WORD => false,
                    };

                    const start_pos = try editor.text_buffer.findCurrentWordBegining(editor.getAbsRow(), editor.getAbsCol(), subWord);
                    const end_pos = try editor.text_buffer.findCurrentWordEnd(editor.getAbsRow(), editor.getAbsCol(), subWord);
                    const new_pos = try editor.text_buffer.deleteInterval(start_pos, end_pos);
                    editor.moveAbs(new_pos.row, new_pos.col);
                },
                .NextWord => |word_t| {
                    const next_pos = try editor.text_buffer.findNextWord(
                        editor.getAbsRow(),
                        editor.getAbsCol(),
                        switch (word_t) {
                            .word => true,
                            .WORD => false,
                        },
                    );
                    editor.moveAbs(next_pos.row, next_pos.col);
                },
                // BUG: Does not work in last line
                .PrevWord => |word_t| {
                    const next_pos = try editor.text_buffer.findWordBeginig(
                        editor.getAbsRow(),
                        editor.getAbsCol(),
                        switch (word_t) {
                            .word => true,
                            .WORD => false,
                        },
                    );
                    editor.moveAbs(next_pos.row, next_pos.col);
                },
                // BUG: E at last char goes back to the start of the line.
                .EndOfWord => |word_t| {
                    const pos = try editor.text_buffer.findWordEnd(
                        editor.getAbsRow(),
                        editor.getAbsCol(),
                        switch (word_t) {
                            .word => true,
                            .WORD => false,
                        },
                    );
                    editor.moveAbs(pos.row, pos.col);
                },

                .Indent => |num| {
                    const indent = try editor.allocator.alloc(TextBuffer.CharType, num);
                    defer editor.allocator.free(indent);
                    for (indent) |*ch| {
                        ch.* = ' ';
                    }
                    try editor.text_buffer.insert(indent, editor.getAbsRow(), 0);
                },

                .InsertNewLine => {
                    try editor.text_buffer.insert("\n", editor.getAbsRow(), editor.getAbsCol());
                },
                .DeleteUnderCursor => {
                    const pos = vimz.Position{ .row = editor.getAbsRow(), .col = editor.getAbsCol() };
                    _ = try editor.text_buffer.deleteInterval(pos, pos);
                },

                .Replicate => |st| {
                    const last_mode = editor.mode;
                    editor.mode = st.as_mode;
                    try editor.handleInput(st.key);
                    editor.mode = last_mode;
                },

                .DeleteInterval => |st| {
                    const pos = try editor.text_buffer.deleteInterval(st.start, st.end);
                    editor.moveAbs(pos.row, pos.col);
                },

                .AppendNextLine => {
                    const pos = try editor.text_buffer.appendNextLine(editor.getAbsRow(), editor.getAbsCol());
                    editor.moveAbs(pos.row, pos.col);
                },
                .SaveFile => {
                    const buffers = editor.text_buffer.gap_buffer.getBuffers();
                    var file: std.fs.File = try std.fs.cwd().createFile(editor.file_name, .{});
                    defer file.close();
                    for (buffers) |buffer| {
                        try file.writeAll(buffer);
                    }
                    editor.text_buffer.changed = false;
                },

                .Past => |place| {
                    const past_text = editor.clipboard_buff orelse "";
                    try editor.text_buffer.insert(past_text, editor.getAbsRow(), blk: switch (place) {
                        .BeforeCursor => {
                            break :blk editor.getAbsCol();
                        },
                        .AfterCursor => {
                            break :blk editor.getAbsCol() + 1;
                        },
                    });
                    editor.moveRight(@intCast(past_text.len));
                },

                inline else => {},
            }
        }
    };

    fn enterInsertAfter(self: *Self) !void {
        const line = try self.text_buffer.getLineInfo(self.getAbsRow());
        if (line.len > 0) {
            try Motion.exec(.{ .MoveRight = 1 }, self);
        }
    }

    pub fn handleVisualMode(self: *Self, key: vaxis.Key) !void {
        if (std.ascii.isDigit(@intCast(key.codepoint))) {
            const d = (key.codepoint - '0');
            if (self.repeat) |num| {
                self.repeat = num * 10 + d;
            } else {
                self.repeat = d;
            }
            return;
        }

        if (key.matches('c', .{ .ctrl = true }) or key.matches(vaxis.Key.escape, .{})) {
            try Motion.exec(.{ .ChangeMode = .Normal }, self);
        } else if (key.matches('d', .{})) {
            try Motion.exec(.{ .ChangeMode = .Normal }, self);
            try Motion.exec(.{ .DeleteInterval = .{
                .start = self.vis_start,
                .end = .{
                    .row = self.getAbsRow(),
                    .col = self.getAbsCol(),
                },
            } }, self);
        } else if (key.matches('y', .{})) {
            try Motion.exec(.{ .Yank = .{ .start = self.vis_start, .end = self.getAbsCursorPos() } }, self);
            try Motion.exec(.{ .ChangeMode = .Normal }, self);
        } else if (key.matches('v', .{})) {
            try Motion.exec(.{ .ChangeMode = .Normal }, self);
        } else {
            try Motion.exec(.{ .Replicate = .{ .as_mode = .Normal, .key = key } }, self);
        }
    }

    fn handleInsertMode(self: *Self, key: vaxis.Key) !void {
        if (key.matches('c', .{ .ctrl = true }) or key.matches(vaxis.Key.escape, .{})) {
            try Motion.exec(.{ .ChangeMode = .Normal }, self);
            try Motion.exec(.{ .MoveLeft = 1 }, self);
        } else if (key.matches('j', .{ .ctrl = true })) {
            try Motion.exec(.{ .Replicate = .{
                .key = vaxis.Key{ .codepoint = 'o' },
                .as_mode = .Normal,
            } }, self);
        } else if (key.matches(vaxis.Key.tab, .{})) {
            try Motion.exec(.{ .WriteAtCursor = " " ** Editor.indent_size }, self);
        } else if (key.matches(vaxis.Key.backspace, .{})) {
            if (self.getAbsRow() == 0 and self.getAbsCol() == 0) {
                return;
            }
            if (self.getAbsCol() == 0) {
                try Motion.exec(.{ .MoveUp = 1 }, self);
                try Motion.exec(.{ .MoveToEndOfLine = {} }, self);
                try Motion.exec(.{ .AppendNextLine = {} }, self);
                try Motion.exec(.{ .DeleteUnderCursor = {} }, self);
                try Motion.exec(.{ .MoveLeft = 1 }, self);
                try self.enterInsertAfter();
            } else {
                try Motion.exec(.{ .MoveLeft = 1 }, self);
                try Motion.exec(.{ .DeleteUnderCursor = {} }, self);
            }
        } else if (key.matches(vaxis.Key.enter, .{})) {
            const indent = try self.getNextIndent(self.getAbsRow(), true);
            try Motion.exec(.{ .InsertNewLine = {} }, self);
            try Motion.exec(.{ .MoveDown = 1 }, self);
            try Motion.exec(.{ .Indent = indent }, self);
            try Motion.exec(.{ .MoveToStartOfLine = .{ .stopAfterWs = true } }, self);
        } else if (key.text) |text| {
            try Motion.exec(Motion{ .WriteAtCursor = text }, self);
        }
    }

    fn getNextIndent(self: *Self, row: usize, down: bool) !usize {
        const line = try self.text_buffer.getLineInfo(row);
        var indent = line.indent;
        if (line.last_char) |ch| {
            if (utils.open_brak.get(&.{ch}) != null) {
                if (down) {
                    indent += Editor.indent_size;
                }
            }

            if (utils.close_brak.get(&.{ch}) != null) {
                if (!down) {
                    indent += Editor.indent_size;
                }
            }
        }
        return indent;
    }

    // Switch is cleaner, but this is the vaxis limitation.
    fn handleNormalMode(self: *Self, key: vaxis.Key) !void {
        if (key.matches('c', .{ .ctrl = true }) or key.matches(vaxis.Key.escape, .{})) {
            self.repeat = null;
        }

        if (std.ascii.isDigit(@intCast(key.codepoint))) {
            const d = (key.codepoint - '0');
            self.repeat = (self.repeat orelse 0) * 10 + d;

            return;
        }

        const repeat = self.repeat orelse 1;
        var is_pending: bool = false;
        for (0..repeat) |_| {
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
            } else if (key.matches('v', .{})) {
                try Motion.exec(.{ .ChangeMode = .Visual }, self);
                self.vis_start = .{
                    .col = self.getAbsCol(),
                    .row = self.getAbsRow(),
                };
            } else if (key.matches('i', .{})) {
                try Motion.exec(.{ .ChangeMode = .Insert }, self);
            } else if (key.matches('a', .{})) {
                try Motion.exec(.{ .ChangeMode = .Insert }, self);
                try self.enterInsertAfter();
            } else if (key.matches('d', .{ .ctrl = true })) {
                try Motion.exec(.{ .ScrollHalfPageDown = {} }, self);
            } else if (key.matches('e', .{})) {
                try Motion.exec(.{ .EndOfWord = .word }, self);
            } else if (key.matches('J', .{})) {
                try Motion.exec(.{ .AppendNextLine = {} }, self);
            } else if (key.matches('E', .{})) {
                try Motion.exec(.{ .EndOfWord = .WORD }, self);
            } else if (key.matches('u', .{ .ctrl = true })) {
                try Motion.exec(.{ .ScrollHalfPageUp = {} }, self);
            } else if (key.matches('b', .{})) {
                try Motion.exec(.{ .PrevWord = .word }, self);
            } else if (key.matches('A', .{})) {
                try Motion.exec(.{ .ChangeMode = .Insert }, self);
                try Motion.exec(.{ .MoveToEndOfLine = {} }, self);
                try self.enterInsertAfter();
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
            } else if (key.matches('P', .{})) {
                try Motion.exec(.{ .Past = .BeforeCursor }, self);
            } else if (key.matches('p', .{})) {
                try Motion.exec(.{ .Past = .AfterCursor }, self);
            } else if (key.matches('w', .{})) {
                try Motion.exec(.{ .NextWord = .word }, self);
            } else if (key.matches('D', .{})) {
                try Motion.exec(.{ .DeleteLine = .{
                    .start_idx = self.getAbsCol(),
                    .include_end_line = false,
                } }, self);
            } else if (key.matches('W', .{})) {
                try Motion.exec(.{ .NextWord = .WORD }, self);
            } else if (key.matches('x', .{})) {
                try Motion.exec(.{ .DeleteUnderCursor = {} }, self);
            } else if (key.matches('O', .{})) {
                const indent = try self.getNextIndent(self.getAbsRow(), false);
                try Motion.exec(.{ .MoveToStartOfLine = .{ .stopAfterWs = false } }, self);
                try Motion.exec(.{ .InsertNewLine = {} }, self);
                try Motion.exec(.{ .ChangeMode = .Insert }, self);
                try Motion.exec(.{ .Indent = indent }, self);
                try Motion.exec(.{ .MoveToStartOfLine = .{ .stopAfterWs = true } }, self);
                try self.enterInsertAfter();
            } else if (key.matches('o', .{})) {
                const indent = try self.getNextIndent(self.getAbsRow(), true);
                try Motion.exec(.{ .MoveToEndOfLine = {} }, self);
                try Motion.exec(.{ .ChangeMode = .Insert }, self);
                try Motion.exec(.{ .MoveRight = 1 }, self);
                try Motion.exec(.{ .InsertNewLine = {} }, self);
                try Motion.exec(.{ .MoveDown = 1 }, self);
                try Motion.exec(.{ .Indent = indent }, self);
                try Motion.exec(.{ .MoveToStartOfLine = .{ .stopAfterWs = true } }, self);
                try self.enterInsertAfter();
            } else {
                is_pending = true;
                break;
            }
        }

        if (is_pending) {
            try Motion.exec(.{ .ChangeMode = .Pending }, self);
            try self.handlePendingCommand(key);
            return;
        }

        self.repeat = null;
    }

    fn executePendingCommand(self: *Self, cmd_str: []const u8) !void {
        if (cmds.get(cmd_str)) |motions| {
            for (motions) |motion| {
                try Motion.exec(motion, self);
                if (self.mode == .Pending) {
                    try Motion.exec(Motion{ .ChangeMode = .Normal }, self);
                }
            }
        }
    }

    fn handlePendingCommand(self: *Self, key: vaxis.Key) !void {
        // New handling System:
        // while its a number caluclate it

        if (key.matches('c', .{ .ctrl = true }) or key.matches(vaxis.Key.escape, .{})) {
            self.cmd_trie.reset();
            try Motion.exec(Motion{ .ChangeMode = .Normal }, self);
        }

        const key_text = key.text orelse return;
        const result = try self.cmd_trie.step(key_text[0]);
        switch (result) {
            .Accept => {
                const repeat = self.repeat orelse 1;
                for (0..repeat) |_| {
                    try self.executePendingCommand(self.cmd_trie.getCurrentWord());
                }
                self.repeat = null;
                self.last_cmd = self.cmd_trie.getCurrentWord();
                self.cmd_trie.reset();
            },
            .Reject => {
                self.cmd_trie.reset();
                try Motion.exec(Motion{ .ChangeMode = .Normal }, self);
            },
            .Deciding => {},
        }
    }

    fn handleMouseEvent(self: *Self, mouse_event: vaxis.Mouse) !void {
        switch (mouse_event.type) {
            .press => {
                try Motion.exec(.{ .ChangeMode = .Normal }, self);
                self.moveAbs(
                    self.top + mouse_event.row -| @abs(self.win_dims.text_win_dims.y_off),
                    self.left + mouse_event.col -| @abs(self.win_dims.text_win_dims.x_off),
                );
            },
            .drag => {
                self.moveAbs(
                    self.top + mouse_event.row -| @abs(self.win_dims.text_win_dims.y_off),
                    self.left + mouse_event.col -| @abs(self.win_dims.text_win_dims.x_off),
                );

                if (self.mode != .Visual) {
                    try Motion.exec(.{ .ChangeMode = .Visual }, self);
                    self.vis_start = .{
                        .row = self.getAbsRow(),
                        .col = self.getAbsCol(),
                    };
                }
            },
            .release => {},
            else => {},
        }
    }
};

// Pending commands: the order of motions is the order of their exection.
const cmds = std.StaticStringMap([]const Editor.Motion).initComptime(.{
    .{
        "diw",
        &.{
            Editor.Motion{ .DeleteInsideWord = .word },
        },
    },
    .{
        "diW",
        &.{
            Editor.Motion{ .DeleteInsideWord = .WORD },
        },
    },
    .{
        "ciw",
        &.{
            Editor.Motion{ .DeleteInsideWord = .word },
            Editor.Motion{ .ChangeMode = .Insert },
        },
    },
    .{
        "ciW", &.{
            Editor.Motion{ .DeleteInsideWord = .WORD },
            Editor.Motion{ .ChangeMode = .Insert },
        },
    },
    .{
        "dd",
        &.{
            Editor.Motion{
                .DeleteLine = .{
                    .include_end_line = true,
                    .start_idx = 0,
                },
            },
        },
    },
    .{
        "gg",
        &.{
            .FirstLine,
        },
    },
    .{
        ">>",
        &.{
            Editor.Motion{ .Indent = Editor.indent_size },
        },
    },
    .{
        // TODO: Implement command  section
        ":w",
        &.{
            .SaveFile,
        },
    },
});
