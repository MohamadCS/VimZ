const std = @import("std");
const utils = @import("utils.zig");
const vimz = @import("vimz.zig");
const Core = @import("vimz.zig").Core;
const log = @import("logger.zig").Logger.log;

const UserComps = @This();

api: vimz.Api = undefined,

pub fn addComps(self: @This()) !void {
    try self.api.addStatusLineComp(
        .{
            .update_func = &updateMode,
        },
        .Left,
    );

    try self.api.addStatusLineComp(
        .{
            .update_func = &updateGitBranch,
            .async_update = true,
            .icon = "",
        },
        .Left,
    );

    try self.api.addStatusLineComp(
        .{
            .update_func = &updateFileName,
        },
        .Left,
    );

    try self.api.addStatusLineComp(
        .{
            .update_func = &updateRowCol,
        },
        .Right,
    );

    try self.api.addStatusLineComp(
        .{
            .update_func = &updatePendingCommand,
        },
        .Right,
    );
}

fn updateFileName(self: @This(), comp: *vimz.StatusLine.Component) !void {
    var it = std.mem.splitBackwardsAny(u8, try self.api.getCurrBufferName(), "/");

    const file_name = it.next() orelse "no-name";

    try comp.setText("{s}", .{file_name});
    comp.style.?.italic = true;
    comp.icon = if (try self.api.isCurrBufferSaved()) null else "";
}

fn updateMode(self: @This(), comp: *vimz.StatusLine.Component) !void {
    const mode = try self.api.getMode();
    const theme = try self.api.getTheme();
    var text: []const u8 = undefined;

    switch (mode) {
        .Normal => {
            text = "NORMAL";
            comp.style.?.fg = theme.red;
        },
        .Insert => {
            text = "INSERT";
            comp.style.?.fg = theme.blue;
        },
        .Pending => {
            text = "O-PENDING";
            comp.style.?.fg = theme.red;
        },
        .Visual => {
            text = "VISUAL";
            comp.style.?.fg = theme.purple;
        },
    }

    comp.style.?.bold = true;

    try comp.setText("{s}", .{text});
}

fn updateRowCol(self: @This(), comp: *vimz.StatusLine.Component) !void {
    const cursor_pos = try self.api.getAbsCursorPos();
    try comp.setText("{}:{}", .{ cursor_pos.row + 1, cursor_pos.col + 1 });
    const theme = try self.api.getTheme();
    comp.style.?.fg = theme.red;
    comp.style.?.bold = true;
}

fn updatePendingCommand(self: @This(), comp: *vimz.StatusLine.Component) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};

    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) {
            std.debug.print("mem leak", .{});
        }
    }

    const alloc = gpa.allocator();
    const repeat_str = if (try self.api.getRepeatCommandNum()) |num|
        try std.fmt.allocPrint(alloc, "{}{s}", .{ num, try self.api.getPendingCommand() })
    else
        try std.fmt.allocPrint(alloc, "{s}", .{try self.api.getPendingCommand()});

    defer alloc.free(repeat_str);

    try comp.setText("{s}", .{repeat_str});
    comp.style.?.fg = .{ .rgb = .{ 215, 130, 126 } };
}

fn updateGitBranch(self: @This(), comp: *vimz.StatusLine.Component) !void {
    _ = self;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};

    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) {
            std.debug.print("mem leak", .{});
        }
    }

    const alloc = gpa.allocator();
    const text = utils.getGitBranch(alloc) catch {
        comp.hide = true;
        comp.text = null;
        return;
    };

    defer alloc.free(text);

    comp.hide = false;

    try comp.setText("{s}", .{
        text[0..text.len -| 1],
    });
}
