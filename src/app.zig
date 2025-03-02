const std = @import("std");
const vaxis = @import("vaxis");
const utils = @import("utils.zig");

pub const Comps = @import("components.zig");
pub const Editor = @import("editor.zig").Editor;
pub const Types = @import("types.zig");
pub const StatusLine = @import("status_line.zig").StatusLine;

const Vimz = @This();

const Allocator = std.mem.Allocator;
const log = std.log.scoped(.main);

// Devide to App and State
pub const App = struct {
    tty: vaxis.Tty,

    vx: vaxis.Vaxis,

    allocator: Allocator,

    file: std.fs.File = undefined,

    quit: bool,

    loop: vaxis.Loop(Types.Event) = undefined,

    editor: Editor,

    statusLine: StatusLine,

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const Self = @This();

    fn init() !Self {
        const allocator = App.gpa.allocator();
        return Self{
            .allocator = allocator,
            .tty = try vaxis.Tty.init(),
            .vx = try vaxis.init(allocator, .{}),
            .quit = false,
            .statusLine = try StatusLine.init(allocator),
            .editor = try Editor.init(allocator),
        };
    }

    // Singleton for simplicity.
    // Find a better way later.
    var instance: ?Self = null;
    pub fn getInstance() !*Self {
        if (App.instance) |*app| {
            return app;
        }

        App.instance = try App.init();
        return &App.instance.?;
    }

    pub fn deinit(self: *Self) void {
        self.vx.deinit(self.allocator, self.tty.anyWriter());
        self.tty.deinit();
        self.statusLine.deinit();
        self.editor.deinit();

        const deinit_status = App.gpa.deinit();
        if (deinit_status == .leak) {
            log.err("memory leak", .{});
        }
    }

    fn updateDims(self: *Self) !void {
        const win = self.vx.window();
        self.editor.win_opts = .{
            .x_off = 0,
            .y_off = 0,
            .width = win.width,
            .height = win.height - 2,
            // .border = .{
            //     .glyphs = .single_rounded,
            //     .where = .all
            // }
        };

        self.statusLine.win_opts = .{
            .x_off = 0,
            .y_off = win.height - 2,
            .height = 1,
            .width = win.width,
        };
    }

    fn draw(self: *Self) !void {
        const win = self.vx.window();

        win.clear();

        var statusLineWin = win.child(self.statusLine.win_opts);
        var editorWin = win.child(self.editor.win_opts);

        try self.statusLine.draw(&statusLineWin);
        try self.editor.draw(&editorWin);

        try self.vx.render(self.tty.anyWriter());
    }

    fn handleEvent(self: *Self, event: Types.Event) !void {
        switch (event) {
            .winsize => |ws| {
                try self.vx.resize(self.allocator, self.tty.anyWriter(), ws);
            },
            .key_press => |key| {
                // If other windows can handle input then switch on the current state
                try self.editor.handleInput(key);
            },
            .refresh_status_line => {},
        }
    }

    fn readFile(self: *Self) !void {
        var args = std.process.args();

        _ = args.next().?;

        var file_name: []const u8 = "";
        if (args.next()) |arg| {
            file_name = arg;
        } else {
            return; 
        }

        self.file = std.fs.cwd().openFile(file_name, .{}) catch |err| {
            log.err("Could not open the file", .{});
            return err;
        };
        const file_size = (try self.file.stat()).size;
        const file_contents = try self.file.readToEndAlloc(self.allocator, file_size);
        defer self.allocator.free(file_contents);

        // TODO: App should not access editor's buff directly
        try self.editor.text_buffer.insert(file_contents, self.editor.getAbsRow(), self.editor.getAbsCol());
        try self.editor.text_buffer.moveCursor(0, 0);
    }

    fn update(self: *Self) !void {
        try self.updateDims();
        try self.editor.update();
    }

    pub fn enqueueEvent(self: *Self, event: Types.Event) !void {
        self.loop.postEvent(event);
    }

    pub fn run(self: *Self) !void {
        try self.readFile();

        self.loop = vaxis.Loop(Types.Event){
            .tty = &self.tty,
            .vaxis = &self.vx,
        };

        // Loop Setup
        //
        try self.loop.init();
        try self.loop.start();

        defer self.loop.stop();

        // Settings
        try self.vx.enterAltScreen(self.tty.anyWriter());
        try self.vx.queryTerminal(self.tty.anyWriter(), 0.1 * std.time.ns_per_s);

        try self.statusLine.setup();

        while (!self.quit) {
            self.loop.pollEvent();

            // If there is some event, then handle it
            while (self.loop.tryEvent()) |event| {
                try self.handleEvent(event);
            }

            try self.update();

            try self.draw();
        }
    }
};
