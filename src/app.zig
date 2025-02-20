const std = @import("std");
const vaxis = @import("vaxis");
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

const StatusLine = struct {
    bg: vaxis.Color = .{ .rgb = .{ 255, 250, 243 } },
    fg: vaxis.Color = .{ .rgb = .{ 87, 82, 121 } },
};

const Editor = struct {
    fg: vaxis.Color = .{ .rgb = .{ 87, 82, 121 } },
};

pub const App = struct {
    tty: vaxis.Tty,
    vx: vaxis.Vaxis,

    allocator: Allocator,

    file: std.fs.File = undefined,
    buff: GapBuffer,

    top: usize,

    mode: Mode,

    quit: bool,
    cursor: Cursor,

    statusLine: StatusLine = .{},
    editor: Editor = .{},

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
        };
    }

    pub fn deinit(self: *Self) void {
        self.vx.deinit(self.allocator, self.tty.anyWriter());
        self.tty.deinit();
        self.buff.deinit();
    }

    fn draw(self: *Self) !void {
        const win = self.vx.window();

        win.clear();

        const editorWin = win.child(.{
            .x_off = 0,
            .y_off = 0,
            .width = win.width,
            .height = win.height - 2,
        });

        const statusLineWin = win.child(.{
            .x_off = 0,
            .y_off = win.height - 2,
            .height = 1,
            .width = win.width,
        });
        statusLineWin.fill(.{ .style = .{
            .bg = self.statusLine.bg,
        } });

        _ = statusLineWin.printSegment(vaxis.Segment{
            .text = "",
            .style = .{ .bg = self.statusLine.bg, .bold = true, .fg = self.statusLine.fg },
        }, .{});

        _ = statusLineWin.printSegment(vaxis.Segment{
            .text = if (self.mode == Mode.Normal) "NORMAL" else "INSERT",
            .style = .{ .bg = self.statusLine.bg, .bold = true, .fg = self.statusLine.fg },
        }, .{});

        const buffers = self.buff.getBuffers();

        var buff = try self.allocator.alloc(CharType, buffers[0].len + buffers[1].len);
        defer self.allocator.free(buff);

        // TODO: Remove buff, and loop over the two buffers instead of allocating
        // memory on the heap

        // add the two buffers to the array;
        for (0..buffers[0].len) |i| {
            buff[i] = buffers[0][i];
        }

        for (buffers[0].len..buffers[0].len + buffers[1].len, 0..buffers[1].len) |i, j| {
            buff[i] = buffers[1][j];
        }

        var splits = std.mem.split(CharType, buff, "\n");

        var row: u16 = 0;
        var idx: u16 = 0; // Current Cell
        var virt_row: u16 = 0;

        // Render each cell individually
        while (splits.next()) |chunk| : (row +|= 1) {
            if (row < self.top) {
                idx += @intCast(chunk.len + 1);
                continue;
            }

            // TODO: Change when implementing scrolling
            if (row > self.top + editorWin.height) {
                break;
            }

            if (chunk.len == 0) {
                if (self.cursor.row == virt_row) {
                    if (virt_row >= editorWin.height - 1) {
                        self.top += 1;
                        self.cursor.row -|= 1;
                    } else if(virt_row == 0 and self.top > 0){
                        self.top -= 1;
                        self.cursor.row +|= 1;
                    }


                    try self.buff.moveCursor(idx);
                    self.cursor.col = 0;
                }
            }

            for (0..chunk.len) |col| {
                editorWin.writeCell(@intCast(col), virt_row, Cell{ .char = .{
                    .grapheme = buff[idx .. idx + 1],
                }, .style = .{ .fg = self.editor.fg } });

                if (virt_row == self.cursor.row) {
                    if (virt_row >= editorWin.height - 1) {
                        self.top += 1;
                        self.cursor.row -|= 1;
                    } else if(virt_row == 0 and self.top > 0){
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
            }

            virt_row += 1;
            // skip '\n'
            idx += 1;
        }

        // because of the last + 1 of the while.
        self.cursor.row = @min(row - 2, self.cursor.row);

        editorWin.showCursor(self.cursor.col, self.cursor.row);

        try self.vx.render(self.tty.anyWriter());
    }

    fn handleNormalMode(self: *Self, key: vaxis.Key) !void {
        // Needs much more work, will stay like that just for testing.

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
        } else if (key.matches('d', .{})) {
            try self.buff.deleteForwards(GapBuffer.SearchPolicy{ .Number = 5 });
        } else if (key.matches('x', .{})) {
            try self.buff.deleteForwards(GapBuffer.SearchPolicy{ .Number = 1 });
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
        try self.vx.queryTerminal(self.tty.anyWriter(), 0.1 * std.time.ns_per_s);

        while (!self.quit) {
            loop.pollEvent();

            // If there is some event, then handle it
            while (loop.tryEvent()) |event| {
                try self.handleEvent(event);
            }

            try self.draw();
        }
    }
};
