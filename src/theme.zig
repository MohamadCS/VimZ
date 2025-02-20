const std = @import("std");
const vaxis = @import("vaxis");
const Color = vaxis.Color;

pub const Theme = @This();

editor: Editor = .{},
statusLine: StatusLine = .{},

const Editor = struct {
    bg: Color,
    fg: Color,
};

const StatusLineComps = enum(usize) {
    Mode = 0,
};

pub const StatusLineComp = struct {
    bg: Color = .{},
    fg: Color = .{},
    icon: ?u32 = null,
};

const StatusLine = struct {
    bg: Color,
    fg: Color,
    segments: []*StatusLineComp,

    mode: StatusLineComp,
    line: StatusLineComp,

};
