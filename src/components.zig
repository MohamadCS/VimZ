const Api = @import("api.zig");
const std = @import("std");
const Vimz = Api.Vimz;

fn updateMode(comp: *Api.StatusLine.Component) !void {
    const mode = try Api.getMode();
    const text = if (mode == Vimz.Mode.Normal) "NORMAL" else "INSERT";
    try comp.setText("{s}", .{text});
}

fn updateRowCol(comp: *Api.StatusLine.Component) !void {
    const cursor_state = try Api.getCursorState();
    try comp.setText("{}:{}", .{cursor_state.row,cursor_state.col});
}

pub fn addComps() !void {
    try Api.addStatusLineComp(.{ .update_func = &updateMode}, .Left);
    try Api.addStatusLineComp(.{ .update_func = &updateRowCol}, .Right);
    try Api.addStatusLineComp(.{ .update_func = &updateRowCol}, .Right);
}
