const Api = @import("api.zig");
const std = @import("std");
const utils = @import("utils.zig");
const Vimz = Api.Vimz;

pub fn addComps() !void {
    try Api.addStatusLineComp(.{ .update_func = &updateMode }, .Left);
    try Api.addStatusLineComp(.{ .update_func = &updateGitBranch }, .Left);
    try Api.addStatusLineComp(.{ .update_func = &updateRowCol }, .Right);
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
    }

    comp.style.?.bold = true;

    try comp.setText("{s}", .{text});
}

fn updateRowCol(comp: *Api.StatusLine.Component) !void {
    const cursor_state = try Api.getAbsCursorState();
    try comp.setText("{}:{}", .{ cursor_state.row, cursor_state.col });
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
    const text = try utils.getGitBranch(alloc);

    try comp.setText(" {s}", .{
        text,
    });

    alloc.free(text);
}
