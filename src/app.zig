const std = @import("std");
const vaxis = @import("vaxis");
const utils = @import("utils.zig");
const Cell = vaxis.Cell;

const CharType: type = u8;
const GapBuffer = @import("gap_buffer.zig").GapBuffer(CharType);

const Allocator = std.mem.Allocator;
const log = std.log.scoped(.main);

const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
};

const Mode = enum {
    Normal,
    Insert,
};

const Cursor = struct {
    row: u16 = 0,
    col: u16 = 0,
};

pub const App = struct {
    tty: vaxis.Tty,
    vx: vaxis.Vaxis,

    allocator: Allocator,

    file: std.fs.File = undefined,

    buff: GapBuffer,

    input_queue: std.ArrayList(u21),

    top: usize,

    mode: Mode,

    quit: bool,
    cursor: Cursor,

    statusLine: struct {
        bg: vaxis.Color = .{ .rgb = .{ 255, 250, 243 } },
        fg: vaxis.Color = .{ .rgb = .{ 87, 82, 121 } },
        winOpts: vaxis.Window.ChildOptions = .{},
        segments: std.ArrayList(?[]CharType),
    },

    editor: struct {
        fg: vaxis.Color = .{
            .rgb = .{ 87, 82, 121 },
        },

        winOpts: vaxis.Window.ChildOptions = .{},
    },

    const Self = @This();

    pub fn init(alloc: Allocator) !Self {
        return Self{
            .allocator = alloc,
            .tty = try vaxis.Tty.init(),
            .vx = try vaxis.init(alloc, .{}),
            .quit = false,
            .cursor = .{},
            .buff = try GapBuffer.init(alloc),
            .mode = Mode.Normal,
            .top = 0,
            .statusLine = .{ .segments = std.ArrayList(?[]CharType).init(alloc) },
            .editor = .{},
            .input_queue = std.ArrayList(u21).init(alloc),
        };
    }

    pub fn deinit(self: *Self) void {
        self.vx.deinit(self.allocator, self.tty.anyWriter());
        self.tty.deinit();
        self.buff.deinit();

        for (self.statusLine.segments.items) |segment| {
            if (segment) |value| {
                self.allocator.free(value);
            }
        }
        self.statusLine.segments.deinit();
        self.input_queue.deinit();
    }

    fn allocBuff(self: *Self) ![]const CharType {
        const buffers = self.buff.getBuffers();

        var buff = try self.allocator.alloc(CharType, buffers[0].len + buffers[1].len);

        for (0..buffers[0].len) |i| {
            buff[i] = buffers[0][i];
        }

        for (buffers[0].len..buffers[0].len + buffers[1].len, 0..buffers[1].len) |i, j| {
            buff[i] = buffers[1][j];
        }

        return buff;
    }

    // TODO: Write a struct that abstracts adding a componenet
    // to the statusLine which will be responsible for holding the
    // data and freeing it.
    // In addition, there should be a process, that detect changes in
    // outer data, like git branches.
    fn drawStatusLine(self: *Self, statusLineWin: *vaxis.Window) !void {
        statusLineWin.fill(.{ .style = .{
            .bg = self.statusLine.bg,
        } });

        if (self.statusLine.segments.items.len == 0) {
            try self.statusLine.segments.append(null);
            try self.statusLine.segments.append(null);
        }

        for (self.statusLine.segments.items) |segment| {
            if (segment) |value| {
                self.allocator.free(value);
            }
        }

        // The solution to the memory leakis to create a status line that stores
        // a simulation of a segment, then we free the status line
        // buffer's at each redraw.
        _ = statusLineWin.printSegment(vaxis.Segment{
            .text = " ",
            .style = .{ .bg = self.statusLine.bg, .bold = true, .fg = self.statusLine.fg },
        }, .{ .col_offset = 0 });

        const mode = statusLineWin.printSegment(vaxis.Segment{
            .text = if (self.mode == Mode.Normal) "NORMAL" else "INSERT",
            .style = .{ .bg = self.statusLine.bg, .bold = true, .fg = self.statusLine.fg },
        }, .{ .col_offset = 1 });

        self.statusLine.segments.items[0] = try utils.getGitBranch(self.allocator);

        const branch_icon = statusLineWin.printSegment(vaxis.Segment{
            .text = "",
            .style = .{ .bg = self.statusLine.bg, .bold = false, .fg = self.statusLine.fg },
        }, .{ .col_offset = mode.col + 2 });

        _ = statusLineWin.printSegment(vaxis.Segment{
            .text = self.statusLine.segments.items[0].?,
            .style = .{ .bg = self.statusLine.bg, .bold = false, .fg = self.statusLine.fg },
        }, .{ .col_offset = branch_icon.col + 1 });


        self.statusLine.segments.items[1] = try std.fmt.allocPrint(self.allocator, "{}:{}", .{ self.cursor.row + self.top + 1, self.cursor.col  + 1});

        _ = statusLineWin.printSegment(vaxis.Segment{
            .text = self.statusLine.segments.items[1].?,
            .style = .{ .bg = self.statusLine.bg, .bold = true, .fg = self.statusLine.fg },
        }, .{ .col_offset =  @intCast(statusLineWin.width - self.statusLine.segments.items[1].?.len - 2) });
    }

    fn update(self: *Self) !void {
        const win = self.vx.window();

        self.editor.winOpts = .{
            .x_off = 0,
            .y_off = 0,
            .width = win.width,
            .height = win.height - 2,
        };

        self.statusLine.winOpts = .{
            .x_off = 0,
            .y_off = win.height - 2,
            .height = 1,
            .width = win.width,
        };

        const buff = try self.allocBuff();
        defer self.allocator.free(buff);

        var splits = std.mem.split(CharType, buff, "\n");

        var row: usize = 0;
        var idx: usize = 0; // Current Cell
        var virt_row: u16 = 0;

        const editorHeight = self.editor.winOpts.height.?;

        // State Update
        while (splits.next()) |chunk| : (row +|= 1) {
            if (row < self.top) {
                idx += @intCast(chunk.len + 1);
                continue;
            }

            // TODO: Change when implementing scrolling
            if (row > self.top + editorHeight) {
                break;
            }

            if (chunk.len == 0) {
                if (self.cursor.row == virt_row) {
                    if (virt_row >= editorHeight - 1) {
                        self.top +|= 1;
                        self.cursor.row -|= 1;
                    } else if (virt_row == 0 and self.top > 0) {
                        self.top -|= 1;
                        self.cursor.row +|= 1;
                    }

                    try self.buff.moveCursor(idx);
                    self.cursor.col = 0;
                }
            }

            for (0..chunk.len) |col| {
                if (virt_row == self.cursor.row) {
                    if (virt_row >= editorHeight - 1) {
                        self.top += 1;
                        self.cursor.row -|= 1;
                    } else if (virt_row == 0 and self.top > 0) {
                        self.top -= 1;
                        self.cursor.row +|= 1;
                    }

                    // ensures that the cursor is not outside the row.
                    // chunk len = 1 col = 1

                    if (self.mode == Mode.Normal) {
                        self.cursor.col = @min(chunk.len - 1, self.cursor.col);
                    }

                    // If we are at the cursor position then move
                    // the buffer's position to there.
                    if (self.cursor.col == col) {
                        try self.buff.moveCursor(idx);
                    }
                }
                idx += 1;

                // Solves the case where we press 'a' and the cursor is at the last
                // element in the row
                if (self.cursor.row == virt_row and self.cursor.col == chunk.len) {
                    try self.buff.moveCursor(idx);
                } else {}
            }

            virt_row += 1;
            // skip '\n'
            idx += 1;
        }

        // because of the last + 1 of the while.
        self.cursor.row = @min(virt_row -| 2, self.cursor.row);
        self.top = @min(self.top, row -| 2);
    }

    fn draw(self: *Self) !void {
        const win = self.vx.window();

        win.clear();

        const editorWin = win.child(self.editor.winOpts);
        var statusLineWin = win.child(self.statusLine.winOpts);

        try self.drawStatusLine(&statusLineWin);

        var buff = try self.allocBuff();
        defer self.allocator.free(buff);

        var splits = std.mem.split(CharType, buff, "\n");

        var row: usize = 0;
        var idx: usize = 0; // Current Cell
        var virt_row: u16 = 0;

        while (splits.next()) |chunk| : (row +|= 1) {
            if (row < self.top) {
                idx += @intCast(chunk.len + 1);
                continue;
            }

            if (row > self.top + editorWin.height) {
                break;
            }

            for (0..chunk.len) |col| {
                editorWin.writeCell(@intCast(col), virt_row, Cell{ .char = .{
                    .grapheme = buff[idx .. idx + 1],
                }, .style = .{ .fg = self.editor.fg } });

                idx += 1;
            }

            virt_row += 1;
            // skip '\n'
            idx += 1;
        }

        editorWin.showCursor(self.cursor.col, self.cursor.row);

        try self.vx.render(self.tty.anyWriter());
    }

    fn handleNormalMode(self: *Self, key: vaxis.Key) !void {
        // Needs much more work, will stay like that just for testing.
        //

        var delimtersSet = try utils.getDelimterSet(self.allocator);
        defer delimtersSet.deinit();

        if (key.matches('l', .{})) {
            self.cursor.col +|= 1;
        } else if (key.matches('j', .{})) {
            self.cursor.row +|= 1;
        } else if (key.matches('h', .{})) {
            self.cursor.col -|= 1;
        } else if (key.matches('k', .{})) {
            self.cursor.row -|= 1;
        } else if (key.matches('q', .{})) {
            self.quit = true;
        } else if (key.matches('i', .{})) {
            self.mode = Mode.Insert;
        } else if (key.matches('a', .{})) {
            self.mode = Mode.Insert;
            self.cursor.col +|= 1;
        } else if (key.matches('d', .{ .ctrl = true })) {
            self.top +|= self.vx.window().height / 2;
        } else if (key.matches('u', .{ .ctrl = true })) {
            self.top -|= self.vx.window().height / 2;
        } else if (key.matches('x', .{})) {
            try self.buff.deleteForwards(GapBuffer.SearchPolicy{ .Number = 1 }, true);
        } else {
            try self.input_queue.append(key.codepoint);
        }
    }
    fn handleInsertMode(self: *Self, key: vaxis.Key) !void {
        if (key.matches('c', .{ .ctrl = true }) or key.matches(vaxis.Key.escape, .{})) {
            self.mode = Mode.Normal;
            self.cursor.col -|= 1;
        } else if (key.matches(vaxis.Key.enter, .{})) {
            try self.buff.write("\n");
            self.cursor.row +|= 1;
            self.cursor.col = 0;
        } else if (key.matches(vaxis.Key.backspace, .{})) {
            if (self.cursor.col == 0) {
                self.cursor.row -|= 1;
                // Go to the end of the last line
            } else {
                self.cursor.col -|= 1;
            }

            try self.buff.deleteBackwards(GapBuffer.SearchPolicy{ .Number = 1 }, true);
        } else if (key.text) |text| {
            try self.buff.write(text);
            self.cursor.col +|= 1;
        }
    }

    fn handleEvent(self: *Self, event: Event) !void {
        switch (event) {
            .winsize => |ws| {
                try self.vx.resize(self.allocator, self.tty.anyWriter(), ws);
            },
            .key_press => |key| {
                switch (self.mode) {
                    .Normal => try self.handleNormalMode(key),
                    .Insert => try self.handleInsertMode(key),
                }
            },
        }
    }

    fn readFile(self: *Self) !void {
        var args = std.process.args();

        _ = args.next().?;

        var file_name: []const u8 = "";
        if (args.next()) |arg| {
            file_name = arg;
        } else {
            log.err("Must provide a file", .{});
        }

        self.file = std.fs.cwd().openFile(file_name, .{}) catch |err| {
            log.err("Could not open the file", .{});
            return err;
        };
        const file_size = (try self.file.stat()).size;
        const file_contents = try self.file.readToEndAlloc(self.allocator, file_size);

        try self.buff.write(file_contents);
        try self.buff.moveCursor(0);

        self.allocator.free(file_contents);
    }

    pub fn run(self: *Self) !void {
        try self.readFile();

        var loop: vaxis.Loop(Event) = .{
            .tty = &self.tty,
            .vaxis = &self.vx,
        };

        // Loop Setup
        try loop.init();
        try loop.start();

        defer loop.stop();

        // Settings
        try self.vx.enterAltScreen(self.tty.anyWriter());
        try self.vx.queryTerminal(self.tty.anyWriter(), 1 * std.time.ns_per_s);

        while (!self.quit) {
            loop.pollEvent();

            // If there is some event, then handle it
            while (loop.tryEvent()) |event| {
                try self.handleEvent(event);
            }

            try self.update();

            try self.draw();
        }
    }
};
