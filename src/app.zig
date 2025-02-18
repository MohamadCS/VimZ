const std = @import("std");
const vaxis = @import("vaxis");
const Cell = vaxis.Cell;

const Allocator = std.mem.Allocator;

const log = std.log.scoped(.main);

const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
};

const Cursor = struct {
    row: u16 = 0,
    col: u16 = 0,
    color: vaxis.Color = .{ .rgb = .{ 86, 148, 159 } },
};

pub const App = struct {
    tty: vaxis.Tty,
    vx: vaxis.Vaxis,
    alloc: Allocator,

    quit: bool,
    cursor: Cursor,

    const Self = @This();

    pub fn init(alloc: Allocator) !Self {
        return Self{ .alloc = alloc, .tty = try vaxis.Tty.init(), .vx = try vaxis.init(alloc, .{}), .quit = false, .cursor = .{} };
    }

    pub fn deinit(self: *Self) void {
        self.vx.deinit(self.alloc, self.tty.anyWriter());
        self.tty.deinit();
    }

    fn draw(self: *Self) !void {
        const win = self.vx.window();

        // const cell: Cell = .{ .char = .{ .grapheme = " " }, .style = .{
        //     .bg = self.cursor.color,
        // } };
        //
        win.showCursor(self.cursor.col, self.cursor.row);

        try self.vx.render(self.tty.anyWriter());
    }

    fn handleEvent(self: *Self, event: Event) !void {
        switch (event) {
            .winsize => |ws| {
                try self.vx.resize(self.alloc, self.tty.anyWriter(), ws);
            },
            .key_press => |key| {
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
                } else {
                    if (key.text) |text| {
                        self.vx.window().writeCell(self.cursor.col, self.cursor.row, Cell{
                            .char = .{ .grapheme = text },
                        });

                        self.cursor.col +|= 1;
                    }
                }
            },
        }
    }

    pub fn run(self: *Self) !void {
        var loop: vaxis.Loop(Event) = .{
            .tty = &self.tty,
            .vaxis = &self.vx,
        };

        try loop.init();

        try loop.start();
        defer loop.stop();

        try self.vx.enterAltScreen(self.tty.anyWriter());
        try self.vx.queryTerminal(self.tty.anyWriter(), 1 * std.time.ns_per_s);

        while (!self.quit) {
            loop.pollEvent();

            while (loop.tryEvent()) |event| {
                try self.handleEvent(event);
            }

            try self.draw();
        }
    }
};
