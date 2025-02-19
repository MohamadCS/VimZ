const std = @import("std");
const vaxis = @import("vaxis");
const Cell = vaxis.Cell;
const GapBuffer = @import("gap_buffer.zig").GapBuffer(u8);

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
    color: vaxis.Color = .{ .rgb = .{ 86, 148, 159 } },
};

pub const App = struct {
    tty: vaxis.Tty,
    vx: vaxis.Vaxis,
    allocator: Allocator,

    file: std.fs.File = undefined,
    buff: GapBuffer,

    max_width: u16 = 0,

    mode: Mode,

    quit: bool,
    cursor: Cursor,

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

        const buffers = self.buff.getBuffers();

        var buff = try self.allocator.alloc(u8, buffers[0].len + buffers[1].len);
        defer self.allocator.free(buff);

        for (0..buffers[0].len) |i| {
            buff[i] = buffers[0][i];
        }

        for (buffers[0].len..buffers[0].len + buffers[1].len, 0..buffers[1].len) |i, j| {
            buff[i] = buffers[1][j];
        }

        var splits = std.mem.split(u8, buff, "\n");

        var row: u16 = 0;
        var idx: u16 = 0;



        while (splits.next()) |chunk| : (row +|= 1) {
            for (0..chunk.len) |col| {
                win.writeCell(@intCast(col), row, Cell{
                    .char = .{
                        .grapheme = buff[idx .. idx + 1],
                    },
                });

                if (row == self.cursor.row) {
                    self.cursor.col = @min(chunk.len - 1 , self.cursor.col);
                    if(self.cursor.col == col) {
                        try self.buff.moveCursor(idx);
                    }
                }

                idx += 1;
            }
            idx += 1;
        }

        self.cursor.row = @min(row - 2, self.cursor.row);

        win.showCursor(self.cursor.col, self.cursor.row);

        try self.vx.render(self.tty.anyWriter());
    }

    fn handleNormalMode(self: *Self, key: vaxis.Key) !void {
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
            try self.buff.deleteForwards(GapBuffer.DelPolicy{ .Number = 5 });
        } else if (key.matches('x', .{})) {
            try self.buff.deleteForwards(GapBuffer.DelPolicy{ .Number = 1 });
        }
    }

    fn handleInsertMode(self: *Self, key: vaxis.Key) !void {
        if (key.matches('c', .{ .ctrl = true }) or key.matches(vaxis.Key.escape, .{})) {
            self.mode = Mode.Normal;
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

        // self.file = try std.fs.cwd().openFile("", .{});
        // defer self.file.close();

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

            try self.draw();
        }
    }
};
