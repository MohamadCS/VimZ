const std = @import("std");
const vaxis = @import("vaxis");
const utils = @import("utils.zig");

// Add async
pub const StatusLine = struct {
    left_comps: std.ArrayList(Component),
    right_comps: std.ArrayList(Component),
    allocator: std.mem.Allocator,
    win_opts: vaxis.Window.ChildOptions,

    style: vaxis.Style = .{
        .bg = .{ .rgb = .{ 255, 250, 243 } },
        .fg = .{ .rgb = .{ 87, 82, 121 } },
    },

    const Self = @This();

    pub const Position = enum {
        Center,
        Left,
        Right,
    };

    pub const Component = struct {
        const UpdateFunction = *const fn (comp: *StatusLine.Component) anyerror!void;
        text: ?[]const u8 = null,
        id: u16 = 0,
        style: ?vaxis.Style = null,
        left_padding: u16 = 1,
        right_padding: u16 = 1,
        allocator: std.mem.Allocator = undefined,
        hide: bool = false,
        needs_update: bool = false, // should be write protected
        update_func: UpdateFunction,

        pub fn setText(self: *Component, comptime fmt: []const u8, args: anytype) !void {
            if (self.text) |text| self.allocator.free(text);
            self.text = try std.fmt.allocPrint(self.allocator, fmt, args);
        }
    };

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{ .allocator = allocator, .left_comps = std.ArrayList(Component).init(allocator), .right_comps = std.ArrayList(Component).init(allocator), .win_opts = .{} };
    }

    pub fn deinit(self: *Self) void {
        for (self.left_comps.items) |*comp| {
            if (comp.text) |text| self.allocator.free(text);
        }

        for (self.right_comps.items) |*comp| {
            if (comp.text) |text| self.allocator.free(text);
        }

        self.left_comps.deinit();
        self.right_comps.deinit();
    }

    pub fn addComp(self: *Self, comp: Component, pos: Position) std.mem.Allocator.Error!void {
        var newComp = comp;

        newComp.style = newComp.style orelse self.style;
        newComp.allocator = self.allocator;

        switch (pos) {
            .Left => {
                try self.left_comps.append(newComp);
            },
            .Right => {
                try self.right_comps.append(newComp);
            },
            else => unreachable,
        }
    }

    pub fn draw(self: *Self, win: *vaxis.Window) !void {
        win.fill(.{ .style = self.style });

        for (self.left_comps.items) |*comp| {
            try comp.update_func(comp);
        }
        for (self.right_comps.items) |*comp| {
            try comp.update_func(comp);
        }

        var curr_col_offset: u16 = 0;

        for (self.left_comps.items) |comp| {
            curr_col_offset += comp.left_padding;
            _ = win.printSegment(vaxis.Segment{
                .text = comp.text.?,
                .style = comp.style.?,
            }, .{ .col_offset = curr_col_offset });

            curr_col_offset += @intCast(comp.text.?.len + comp.right_padding) ;
        }

        curr_col_offset = win.width;

        for (self.right_comps.items) |comp| {
            const col_offset: u16 = @intCast(curr_col_offset -| comp.right_padding -| (if (comp.text) |text| text.len else 0));
            _ = win.printSegment(vaxis.Segment{
                .text = comp.text orelse "Error",
                .style = comp.style.?,
            }, .{ .col_offset = @intCast(col_offset) });

            curr_col_offset = col_offset -| comp.left_padding;
        }
    }
};
