const std = @import("std");
const vaxis = @import("vaxis");
const utils = @import("utils.zig");
const Logger = @import("logger.zig").Logger;
const target = @import("builtin").target;

pub const Api = @import("api.zig");
pub const Theme = @import("theme.zig");
pub const Editor = @import("editor.zig").Editor;
pub const StatusLine = @import("status_line.zig").StatusLine;
pub const CustomComps = @import("components.zig");
const Allocator = std.mem.Allocator;

pub const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
    refresh_status_line: void,
};

// Move to dedicated types file
pub const CursorState = struct {
    row: u16 = 0,
    col: u16 = 0,
};

pub const Position = struct {
    row: usize = 0,
    col: usize = 0,
};

// Move to dedicated types file
pub const Mode = enum {
    Normal,
    Insert,
    Pending,
    Visual,
};

pub const Core = struct {
    tty: vaxis.Tty,

    vx: vaxis.Vaxis,

    loop: vaxis.Loop(Event) = undefined,

    allocator: Allocator,

    curr_theme: Theme,

    quit: bool,

    editor: Editor,

    status_line: StatusLine,

    api: Api,

    const Self = @This();
    pub fn init(allocator: Allocator) !Self {
        return Self{
            .allocator = allocator,
            .tty = try vaxis.Tty.init(),
            .vx = try vaxis.init(allocator, .{}),
            .quit = false,
            .status_line = try StatusLine.init(allocator),
            .curr_theme = .{},
            .editor = try Editor.init(allocator),
            .api = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.vx.deinit(self.allocator, self.tty.anyWriter());
        self.tty.deinit();
        self.status_line.deinit();
        self.editor.deinit();
    }

    fn draw(self: *Self) !void {
        const win = self.vx.window();

        win.clear();

        var status_line_win = win.child(self.status_line.win_opts);
        var editor_win = win.child(self.editor.win_dims.buff_win_dims);

        try self.status_line.draw(&status_line_win);
        try self.editor.draw(&editor_win);
    }

    fn handleEvent(self: *Self, event: Event) !void {
        switch (event) {
            .winsize => |ws| {
                try self.vx.resize(self.allocator, self.tty.anyWriter(), ws);
            },
            .key_press => |key| {
                try self.editor.handleInput(key);
            },
            .refresh_status_line => {},
        }
    }

    fn update(self: *Self) !void {
        try self.status_line.update();
        try self.editor.update();
    }

    pub fn run(self: *Self) !void {
        self.api.core = self;
        self.loop = vaxis.Loop(Event){
            .tty = &self.tty,
            .vaxis = &self.vx,
        };

        // its seems that this has better performence than anyWriter().
        var buffered_writer = self.tty.bufferedWriter();
        const writer = buffered_writer.writer().any();

        // Loop Setup
        //
        try self.loop.init();
        try self.loop.start();

        defer self.loop.stop();

        // Settings
        try self.vx.enterAltScreen(writer);
        try self.vx.queryTerminal(writer, 0.1 * std.time.ns_per_s);
        try self.vx.setTerminalBackgroundColor(writer, self.curr_theme.bg.rgb);
        try self.vx.setTerminalForegroundColor(writer, self.curr_theme.fg.rgb);
        try self.vx.setTerminalCursorColor(writer, self.curr_theme.cursor.rgb);

        try self.status_line.setup(self);
        try self.editor.setup(self);

        while (!self.quit) {
            self.loop.pollEvent();

            // If there is some event, then handle it
            while (self.loop.tryEvent()) |event| {
                try self.handleEvent(event);
            }

            try self.update();

            try self.draw();

            self.vx.queueRefresh();

            try self.vx.render(writer);

            try buffered_writer.flush();
        }
    }
};
