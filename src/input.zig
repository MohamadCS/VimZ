const std = @import("std");
const vaxis = @import("vaxis");
const utils = @import("utils.zig");
const Vimz = @import("app.zig");

pub const Input = struct {
    input_queue: std.ArrayList(u21),

    allocator: std.mem.Allocator,

    const Self = @This();
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .input_queue = std.ArrayList(u21).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.input_queue.deinit();
    }

    pub fn handleInsertMode(key: vaxis.Key) !void {
        var glState = try Vimz.App.getInstance();

        glState.need_realloc = true;
        if (key.matches('c', .{ .ctrl = true }) or key.matches(vaxis.Key.escape, .{})) {
            glState.mode = Vimz.Mode.Normal;
            glState.moveLeft(1);
        } else if (key.matches(vaxis.Key.enter, .{})) {
            try glState.buff.write("\n");
            glState.moveDown(1);
            glState.left = 0;
            glState.cursor.col = 0;
        } else if (key.matches(vaxis.Key.backspace, .{})) {
            if (glState.cursor.col == 0) {
                glState.moveUp(1);
                // Go to the end of the last line
            } else {
                glState.moveLeft(1);
            }
            try glState.buff.deleteBackwards(Vimz.GapBuffer.SearchPolicy{ .Number = 1 }, true);
        } else if (key.text) |text| {
            try glState.buff.write(text);
            glState.moveRight(1);
        }
    }
    pub fn handleNormalMode(key: vaxis.Key) !void {
        var glState = try Vimz.App.getInstance();

        if (key.matches('l', .{})) {
            glState.moveRight(1);
        } else if (key.matches('j', .{})) {
            glState.moveDown(1);
        } else if (key.matches('h', .{})) {
            glState.moveLeft(1);
        } else if (key.matches('k', .{})) {
            glState.moveUp(1);
        } else if (key.matches('q', .{})) {
            glState.quit = true;
        } else if (key.matches('i', .{})) {
            glState.mode = Vimz.Mode.Insert;
        } else if (key.matches('a', .{})) {
            glState.mode = Vimz.Mode.Insert;
            glState.moveRight(1);
        } else if (key.matches('d', .{ .ctrl = true })) {
            glState.top +|= glState.vx.window().height / 2;
        } else if (key.matches('u', .{ .ctrl = true })) {
            glState.top -|= glState.vx.window().height / 2;
        } else if (key.matches('x', .{})) {
            try glState.buff.deleteForwards(Vimz.GapBuffer.SearchPolicy{ .Number = 1 }, false);
        }
    }
};
