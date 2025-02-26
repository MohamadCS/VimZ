const std = @import("std");
const vaxis = @import("vaxis");
const utils = @import("utils.zig");
const Vimz = @import("app.zig");

const CharType: type = u8;
pub const GapBuffer = @import("gap_buffer.zig").GapBuffer(CharType);

const Allocator = std.mem.Allocator;
const log = std.log.scoped(.main);

// Devide to App and State
pub const Editor = struct {
    allocator: Allocator,

    buff: GapBuffer,

    top: usize,

    left: usize,

    mode: Vimz.Types.Mode,

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
            .buff = try GapBuffer.init(allocator),
            .mode = Vimz.Types.Mode.Normal,
            .cursor = .{},
            .top = 0,
            .left = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        self.buff.deinit();
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

        self.cursor.abs_col = self.left + self.cursor.col;
        self.cursor.abs_row = self.top + self.cursor.row;
    }

    pub fn moveAbs(self: *Self, col: u16, row: u16) !void {
        self.cursor.row = row;
        self.cursor.col = col;
        self.tryScroll();
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
        const lines_count = self.buff.lines.items.len;

        if (self.cursor.abs_row > lines_count -| 1) {
            self.cursor.abs_row = lines_count -| 2;
            self.top = @min(self.top, lines_count -| 2);
            self.cursor.row = @intCast(self.cursor.abs_row -| self.top);
        }

        const line = try self.buff.getLineInfo(self.cursor.abs_row);

        if (line.len == 0) {}
        if (self.cursor.abs_col > line.len) {
            self.cursor.abs_col = line.len -| 1;
            self.left = @min(self.left, line.len -| 1);
            self.cursor.col = @intCast(self.cursor.abs_col -| self.left);
        }

        if (self.mode == Vimz.Types.Mode.Normal) {
            self.cursor.col = @min(line.len -| 1 -| self.left, self.cursor.col);
            self.cursor.abs_col = self.cursor.col + self.left;
        }

        try self.buff.moveGap(line.offset + self.cursor.abs_col);
    }

    pub fn draw(self: *Self, editorWin: *vaxis.Window) !void {
        const max_row = @min(self.top + editorWin.height, self.buff.lines.items.len -| 1);

        for (self.top..max_row, 0..) |row, virt_row| {
            const line = try self.buff.getLineInfo(row);

            if (line.len < self.left) {
                continue;
            }

            // to ensure that we only draw what the screen can show
            const start = self.left;
            const end = @min(start + editorWin.width, line.len);
            for (start..end, 0..) |col, virt_col| {
                editorWin.writeCell(@intCast(virt_col), @intCast(virt_row), vaxis.Cell{ .char = .{
                    .grapheme = try self.buff.getSlicedCharAt(row, col),
                }, .style = .{ .fg = self.fg } });
            }
        }

        editorWin.showCursor(self.cursor.col, self.cursor.row);
    }

    pub fn handleInput(self: *Self, key: vaxis.Key) !void {
        switch (self.mode) {
            .Normal => try self.handleNormalMode(key),
            .Insert => try self.handleInsertMode(key),
        }
    }

    // TODO: Define Actions enum, and then call a function with the
    // actions we want to do, this prevents code duplications
    //

    pub const Action = union(enum) {
        MoveUp: usize,
        MoveDown: usize,
        MoveLeft: usize,
        MoveRight: usize,
        ChangeMode: Vimz.Types.Mode,
        Quit: void,
        ScrollHalfPageUp: void,
        ScrollHalfPageDown: void,
        DeleteWord: void,
        DeleteInsideWord: void,
        InsertNewLine: void,
        Write: []const CharType,
        DeleteAroundWord: void,
        DeleteBackwards: struct { searchPolicy: GapBuffer.SearchPolicy },
        DeleteForwards: struct { searchPolicy: GapBuffer.SearchPolicy },

        pub fn execute(self: Action, editor: *Editor) !void {
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
                .Quit => {
                    var app = try Vimz.App.getInstance();
                    app.quit = true;
                },
                .ChangeMode => |mode| {
                    editor.mode = mode;
                },
                .ScrollHalfPageUp => {
                    editor.top -|= editor.win_opts.height.? / 2;
                    editor.tryScroll();
                },
                .ScrollHalfPageDown => {
                    editor.top +|= editor.win_opts.height.? / 2;
                    editor.tryScroll();
                },
                .Write => |text| {
                    try editor.buff.write(text);
                    editor.moveRight(1);
                },
                inline else => {},
            }
        }
    };

    pub fn handleInsertMode(self: *Self, key: vaxis.Key) !void {
        if (key.matches('c', .{ .ctrl = true }) or key.matches(vaxis.Key.escape, .{})) {
            try Action.execute(Action{ .ChangeMode = Vimz.Types.Mode.Normal }, self);
            try Action.execute(.{ .MoveLeft = 1 }, self);
        } else if (key.matches(vaxis.Key.enter, .{})) {
            try self.buff.write("\n");
            self.moveDown(1);
            self.left = 0;
            self.cursor.col = 0;
        } else if (key.matches(vaxis.Key.backspace, .{})) {
            if (self.cursor.col == 0) {
                self.moveUp(1);
                // Go to the end of the last line
            } else {
                self.moveLeft(1);
            }
            try self.buff.deleteBackwards(GapBuffer.SearchPolicy{ .Number = 1 }, true);
        } else if (key.text) |text| {
            try Action.execute(Action{ .Write = text }, self);
        }
    }
    pub fn handleNormalMode(self: *Self, key: vaxis.Key) !void {
        if (key.matches('l', .{})) {
            try Action.execute(Action{ .MoveRight = 1 }, self);
        } else if (key.matches('j', .{})) {
            try Action.execute(Action{ .MoveDown = 1 }, self);
        } else if (key.matches('h', .{})) {
            try Action.execute(Action{ .MoveLeft = 1 }, self);
        } else if (key.matches('k', .{})) {
            try Action.execute(Action{ .MoveUp = 1 }, self);
        } else if (key.matches('q', .{})) {
            try Action.execute(Action{ .Quit = void{} }, self);
        } else if (key.matchesAny(&.{ 'i', 'a' }, .{})) {
            try Action.execute(Action{ .ChangeMode = Vimz.Types.Mode.Insert }, self);
            if (key.matches('a', .{})) try Action.execute(.{ .MoveRight = 1 }, self);
        } else if (key.matches('d', .{ .ctrl = true })) {
            try Action.execute(Action{ .ScrollHalfPageDown = void{} }, self);
        } else if (key.matches('u', .{ .ctrl = true })) {
            try Action.execute(Action{ .ScrollHalfPageUp = void{} }, self);
        }
    }
};
