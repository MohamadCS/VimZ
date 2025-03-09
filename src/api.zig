const vimz = @import("vimz.zig");
const std = @import("std");

const Api = @This();

core: *vimz.Core = undefined,

pub fn getMode(self: @This()) !vimz.Mode {
    return self.core.editor.mode;
}

pub fn getTheme(self: @This()) !vimz.Theme {
    return self.core.curr_theme;
}

pub fn enqueueEvent(self: @This(), event: vimz.Event) !void {
    self.core.loop.postEvent(event);
}

pub fn setMode(self: *@This(), mode: vimz.Mode) void {
    self.core.editor.mode = mode;
}

pub fn getCursorState(self: @This()) !vimz.CursorState {
    return self.core.editor.cursor;
}

pub fn getAbsCursorPos(self: @This()) !vimz.Position {
    return self.core.editor.getAbsCursorPos();
}

pub fn getPendingCommand(self: @This()) ![]u8 {
    return self.core.editor.cmd_trie.curr_seq.items;
}

pub fn getRepeatCommandNum(self: @This()) !?usize {
    return self.core.editor.repeat;
}

pub fn getCurrBufferName(self: @This()) ![:0]const u8 {
    return self.core.editor.file_name;
}

pub fn isCurrBufferSaved(self: @This()) !bool {
    return self.core.editor.isSaved();
}

pub fn getAllocator(self: @This()) !std.mem.Allocator {
    return self.core.allocator;
}

pub fn addStatusLineComp(self: @This(), comp: vimz.StatusLine.Component, pos: vimz.StatusLine.Position) !void {
    try self.core.status_line.addComp(comp, pos);
}

