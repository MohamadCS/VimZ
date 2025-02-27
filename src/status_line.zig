const std = @import("std");
const vaxis = @import("vaxis");
const utils = @import("utils.zig");
const Vimz = @import("app.zig");
const comps = @import("components.zig");

// TODO:
// 1. Async
// 2. Custom theme insteaf of vaxis style
// allowing for more control when no theme is selected
// and for more customizable option.

pub const StatusLine = struct {
    left_comps: std.ArrayList(Component),
    right_comps: std.ArrayList(Component),
    allocator: std.mem.Allocator,
    win_opts: vaxis.Window.ChildOptions,
    mutex: std.Thread.Mutex = .{},

    async_thread: struct {
        thread: std.Thread = undefined,
        allocator: std.mem.Allocator = undefined,
        gpa: std.heap.GeneralPurposeAllocator(.{}) = .{},

        pub fn setup(self: *@This()) !void {
            self.allocator = self.gpa.allocator();
        }

        pub fn deinit(self: *@This()) void {
            const status = self.gpa.deinit();
            if (status == .leak) {
                std.debug.print("memory leak", .{});
            }
        }
    } = .{},

    style: vaxis.Style = .{
        .bg = .{ .rgb = .{ 255, 250, 243 } },
        .fg = .{ .rgb = .{ 87, 82, 121 } },
    },

    const Self = @This();

    pub fn work() !void {
        var app = try Vimz.App.getInstance();

        while (!app.quit) {
            app.statusLine.mutex.lock();
            try app.statusLine.updateAsync();
            app.statusLine.mutex.unlock();
            try app.enqueueEvent(Vimz.Types.Event{ .refresh_status_line = void{} });
            std.time.sleep(1 * std.time.ns_per_s);
        }
    }

    pub fn setup(self: *Self) !void {
        try self.async_thread.setup();
        try comps.addComps();
        _ = self.win_opts;
        self.async_thread.thread = try std.Thread.spawn(.{}, StatusLine.work, .{});
    }

    pub fn init(allocator: std.mem.Allocator) !Self {
        return Self{
            .allocator = allocator,
            .left_comps = std.ArrayList(Component).init(allocator),
            .right_comps = std.ArrayList(Component).init(allocator),
            .win_opts = .{},
        };
    }

    pub const Position = enum {
        Left,
        Right,
    };

    pub const Component = struct {
        const UpdateFunction = *const fn (comp: *StatusLine.Component) anyerror!void;
        update_func: UpdateFunction,

        text: ?[]const u8 = null,

        id: u16 = 0,

        style: ?vaxis.Style = null,
        left_padding: u16 = 1,
        right_padding: u16 = 1,

        async_update: bool = false,
        allocator: std.mem.Allocator = undefined,
        hide: bool = false,

        pub fn setText(self: *Component, comptime fmt: []const u8, args: anytype) !void {
            if (self.text) |text| self.allocator.free(text);
            self.text = try std.fmt.allocPrint(self.allocator, fmt, args);
        }
    };

    pub fn deinit(self: *Self) void {
        // self.async_thread.thread.join();

        for (self.left_comps.items) |*comp| {
            if (comp.text) |text| {
                if (comp.async_update) {
                    self.async_thread.allocator.free(text);
                } else {
                    self.allocator.free(text);
                }
            }
        }

        for (self.right_comps.items) |*comp| {
            if (comp.text) |text| {
                if (comp.async_update) {
                    self.async_thread.allocator.free(text);
                } else {
                    self.allocator.free(text);
                }
            }
        }

        self.left_comps.deinit();
        self.right_comps.deinit();
        self.async_thread.deinit();
    }

    pub fn addComp(self: *Self, comp: Component, pos: Position) !void {
        var newComp = comp;

        newComp.style = newComp.style orelse self.style;
        newComp.allocator = if (newComp.async_update) self.async_thread.allocator else self.allocator;

        switch (pos) {
            .Left => {
                try self.left_comps.append(newComp);
            },
            .Right => {
                try self.right_comps.append(newComp);
            },
        }
    }

    pub fn updateAsync(self: *Self) !void {
        for (self.left_comps.items) |*comp| {
            if (comp.async_update) {
                try comp.update_func(comp);
            }
        }

        for (self.right_comps.items) |*comp| {
            if (comp.async_update) {
                try comp.update_func(comp);
            }
        }
    }

    pub fn draw(self: *Self, win: *vaxis.Window) !void {
        win.fill(.{ .style = self.style });

        self.mutex.lock();

        var curr_col_offset: u16 = 0;
        for (self.left_comps.items) |*comp| {
            if (!comp.async_update) {
                try comp.update_func(comp);
            }
            if (!comp.hide) {
                curr_col_offset += comp.left_padding;
                _ = win.printSegment(vaxis.Segment{
                    .text = comp.text orelse "",
                    .style = comp.style.?,
                }, .{ .col_offset = curr_col_offset });

                curr_col_offset += @intCast(if (comp.text) |text| text.len else 0 + comp.right_padding);
            }
        }

        curr_col_offset = win.width;

        for (self.right_comps.items) |*comp| {
            if (!comp.async_update) {
                try comp.update_func(comp);
            }

            if (!comp.hide) {
                const col_offset: u16 = @intCast(curr_col_offset -| comp.right_padding -| (if (comp.text) |text| text.len else 0));
                _ = win.printSegment(vaxis.Segment{
                    .text = comp.text orelse "",
                    .style = comp.style.?,
                }, .{ .col_offset = @intCast(col_offset) });

                curr_col_offset = col_offset -| comp.left_padding;
            }
        }

        self.mutex.unlock();
    }
};
