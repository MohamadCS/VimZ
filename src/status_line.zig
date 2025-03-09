const std = @import("std");
const vaxis = @import("vaxis");
const utils = @import("utils.zig");
const vimz = @import("vimz.zig");
const addComps = @import("components.zig").addComps;
const log = @import("logger.zig").Logger.log;
const UserComps = @import("components.zig");

pub const StatusLine = struct {
    left_comps: std.ArrayList(Component),
    right_comps: std.ArrayList(Component),
    allocator: std.mem.Allocator,
    win_opts: vaxis.Window.ChildOptions,
    mutex: std.Thread.Mutex,
    core: *vimz.Core = undefined,
    user_comps: UserComps = .{},

    async_thread: struct {
        thread: std.Thread = undefined,
        enabled: bool = false,
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

    const Self = @This();

    pub fn work(core: *vimz.Core) !void {
        while (!core.quit) {
            core.status_line.mutex.lock();
            try core.status_line.updateAsync();
            core.status_line.mutex.unlock();
            try core.api.enqueueEvent(vimz.Event{ .refresh_status_line = void{} });

            std.time.sleep(1 * std.time.ns_per_s);
        }
    }

    pub fn setup(self: *Self, core: *vimz.Core) !void {
        self.core = core;
        self.user_comps.api = self.core.api;
        try self.async_thread.setup();
        try addComps(self.user_comps);
        _ = self.win_opts;

        if (self.async_thread.enabled) {
            self.async_thread.thread = try std.Thread.spawn(.{}, StatusLine.work, .{self.core});
        }
    }

    pub fn init(allocator: std.mem.Allocator) !Self {
        return Self{
            .allocator = allocator,
            .left_comps = std.ArrayList(Component).init(allocator),
            .right_comps = std.ArrayList(Component).init(allocator),
            .win_opts = .{},
            .mutex = .{},
        };
    }

    pub const Position = enum {
        Left,
        Right,
    };

    pub const Component = struct {
        const UpdateFunction = *const fn (self: UserComps, comp: *StatusLine.Component) anyerror!void;
        update_func: UpdateFunction,

        icon: ?[]const u8 = null,
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

        const comp_lists_arr = [_][]Component{ self.left_comps.items, self.right_comps.items };

        for (&comp_lists_arr) |comp_list| {
            for (comp_list) |*comp| {
                if (comp.text) |text| {
                    if (comp.async_update) {
                        self.async_thread.allocator.free(text);
                    } else {
                        self.allocator.free(text);
                    }
                }
            }
        }

        self.left_comps.deinit();
        self.right_comps.deinit();
        self.async_thread.deinit();
    }

    pub fn addComp(self: *Self, comp: Component, pos: Position) !void {
        var newComp = comp;

        newComp.style = newComp.style orelse vaxis.Style{
            .bg = self.core.curr_theme.status_line.bg,
            .fg = self.core.curr_theme.status_line.fg,
        };
        newComp.allocator = if (newComp.async_update) self.async_thread.allocator else self.allocator;

        if (newComp.async_update) {
            self.async_thread.enabled = true;
        }

        switch (pos) {
            .Left => {
                try self.left_comps.append(newComp);
            },
            .Right => {
                try self.right_comps.append(newComp);
            },
        }
    }

    fn updateAsync(self: *Self) !void {
        const comp_lists_arr = [_][]Component{ self.left_comps.items, self.right_comps.items };

        for (&comp_lists_arr) |comp_list| {
            for (comp_list) |*comp| {
                if (comp.async_update) {
                    try comp.update_func(self.user_comps, comp);
                }
            }
        }
    }

    pub fn update(self: *Self) !void {
        const win = self.core.vx.window();

        self.win_opts = .{
            .x_off = 0,
            .y_off = win.height - 2,
            .height = 1,
            .width = win.width,
        };
    }

    pub fn draw(self: *Self, win: *vaxis.Window) !void {
        const theme = try self.core.api.getTheme();
        win.fill(.{ .style = vaxis.Style{
            .bg = theme.status_line.bg,
            .fg = theme.status_line.fg,
        } });

        self.mutex.lock();

        var curr_col_offset: u16 = 0;
        for (self.left_comps.items) |*comp| {
            if (!comp.async_update) {
                try comp.update_func(self.user_comps, comp);
            }

            if (!comp.hide) {
                curr_col_offset += comp.left_padding;

                if (comp.icon) |icon| {
                    _ = win.printSegment(vaxis.Segment{
                        .text = icon,
                        .style = comp.style.?,
                    }, .{ .col_offset = curr_col_offset });

                    curr_col_offset += 2;
                }

                _ = win.printSegment(vaxis.Segment{
                    .text = comp.text orelse "",
                    .style = comp.style.?,
                }, .{ .col_offset = curr_col_offset });

                const text_len = if (comp.text) |text| text.len else 0;
                curr_col_offset += @intCast(text_len + comp.right_padding);
            }
        }

        curr_col_offset = win.width;

        for (self.right_comps.items) |*comp| {
            if (!comp.async_update) {
                try comp.update_func(self.user_comps, comp);
            }

            if (!comp.hide) {
                const text_len = if (comp.text) |text| text.len else 0;
                const col_offset: u16 = @intCast(curr_col_offset -| comp.right_padding -| text_len);
                _ = win.printSegment(vaxis.Segment{
                    .text = comp.text orelse "",
                    .style = comp.style.?,
                }, .{ .col_offset = @intCast(col_offset) });

                if (comp.icon) |icon| {
                    _ = win.printSegment(vaxis.Segment{
                        .text = icon,
                        .style = comp.style.?,
                    }, .{ .col_offset = curr_col_offset });

                    curr_col_offset -= 2;
                }

                curr_col_offset = col_offset -| comp.left_padding;
            }
        }

        self.mutex.unlock();
    }
};
