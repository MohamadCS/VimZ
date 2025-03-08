const Api = @import("api.zig");
const std = @import("std");
const utils = @import("utils.zig");
const Vimz = Api.Vimz;
const log = @import("logger.zig").Logger.log;

pub fn addComps() !void {
    try Api.addStatusLineComp(
        .{
            .update_func = &updateMode,
        },
        .Left,
    );

    try Api.addStatusLineComp(
        .{
            .update_func = &updateGitBranch,
            .async_update = true,
            .icon = "",
        },
        .Left,
    );

    try Api.addStatusLineComp(
        .{
            .update_func = &updateFileName,
        },
        .Left,
    );

    try Api.addStatusLineComp(
        .{
            .update_func = &updateRowCol,
        },
        .Right,
    );

    try Api.addStatusLineComp(
        .{
            .update_func = &updatePendingCommand,
        },
        .Right,
    );
}

fn updateFileName(comp: *Api.StatusLine.Component) !void {
    var it = std.mem.splitBackwardsAny(u8, try Api.getCurrBufferName(), "/");

    const file_name = it.next() orelse "no-name";

    try comp.setText("{s}", .{file_name});
    comp.style.?.italic = true;
    comp.icon = if (try Api.isCurrBufferSaved()) null else "";
}

fn updateMode(comp: *Api.StatusLine.Component) !void {
    const mode = try Api.getMode();
    const theme = try Api.getTheme();
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

fn updateRowCol(comp: *Api.StatusLine.Component) !void {
    try comp.setText("{}:{}", .{ try Api.getAbsCursorRow() + 1, try Api.getAbsCursorCol() + 1 });
    const theme = try Api.getTheme();
    comp.style.?.fg = theme.red;
    comp.style.?.bold = true;
}

fn updatePendingCommand(comp: *Api.StatusLine.Component) !void {
    try comp.setText("{s}", .{try Api.getPendingCommand()});
    comp.style.?.fg = .{ .rgb = .{ 215, 130, 126 } };
}

fn updateGitBranch(comp: *Api.StatusLine.Component) !void {
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
