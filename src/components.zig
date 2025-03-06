const Api = @import("api.zig");
const std = @import("std");
const utils = @import("utils.zig");
const Vimz = Api.Vimz;

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
    const file_name = try Api.getCurrBufferName();
    const saved_text = if (try Api.isCurrBufferSaved()) "" else "[+]";
    try comp.setText("{s} {s}", .{ file_name, saved_text });
    comp.style.?.italic = true;
}

fn updateMode(comp: *Api.StatusLine.Component) !void {
    const mode = try Api.getMode();
    var text: []const u8 = undefined;

    switch (mode) {
        .Normal => {
            text = "NORMAL";
            comp.style.?.fg = .{ .rgb = .{ 215, 130, 126 } };
        },
        .Insert => {
            text = "INSERT";
            comp.style.?.fg = .{ .rgb = .{ 86, 148, 159 } };
        },
        .Pending => {
            text = "O-PENDING";
            comp.style.?.fg = .{ .rgb = .{ 215, 130, 126 } };
        },
    }

    comp.style.?.bold = true;

    try comp.setText("{s}", .{text});
}

fn updateRowCol(comp: *Api.StatusLine.Component) !void {
    try comp.setText("{}:{}", .{ try Api.getAbsCursorRow() + 1, try Api.getAbsCursorCol() + 1 });
    comp.style.?.fg = .{ .rgb = .{ 215, 130, 126 } };
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

    try comp.setText(" {s}", .{
        text,
    });
}
