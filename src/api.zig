const std = @import("std");

pub const Vimz = @import("app.zig");
pub const StatusLine = @import("status_line.zig").StatusLine;
pub const Types = Vimz.Types;

const Api = @This();

pub fn getMode() !Types.Mode {
    const app = try Vimz.App.getInstance();
    return app.editor.mode;
}

pub fn getTheme() !Vimz.Theme {
    const app = try Vimz.App.getInstance();
    return app.theme;
}

pub fn enqueueEvent(event: Types.Event) !void {
    const app = try Vimz.App.getInstance();
    try app.enqueueEvent(event);
}

pub fn setMode(mode: Types.Mode) !void {
    var app = try Vimz.App.getInstance();
    app.mode = mode;
}

pub fn getCursorState() !Types.CursorState {
    const app = try Vimz.App.getInstance();
    return app.editor.cursor;
}

pub fn getPendingCommand() ![]u8 {
    const app = try Vimz.App.getInstance();
    return app.editor.cmd_trie.curr_seq.items;
}

pub fn getRepeatCommandNum() !?usize {
    const app = try Vimz.App.getInstance();
    return app.editor.repeat;
}

pub fn getCurrBufferName() ![:0]const u8 {
    const app = try Vimz.App.getInstance();
    return app.editor.file_name;
}

pub fn isCurrBufferSaved() !bool {
    const app = try Vimz.App.getInstance();
    return app.editor.isSaved();
}

pub fn getAbsCursorCol() !usize {
    const app = try Vimz.App.getInstance();
    return app.editor.getAbsCol();
}

pub fn getAbsCursorRow() !usize {
    const app = try Vimz.App.getInstance();
    return app.editor.getAbsRow();
}

pub fn getAllocator() !std.mem.Allocator {
    const app = try Vimz.App.getInstance();
    return app.allocator;
}

pub fn addStatusLineComp(comp: StatusLine.Component, pos: StatusLine.Position) !void {
    var app = try Vimz.App.getInstance();
    try app.statusLine.addComp(comp, pos);
}
