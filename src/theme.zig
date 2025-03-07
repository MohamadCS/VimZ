const std = @import("std");
const vaxis = @import("vaxis");
const Style = vaxis.Style;
const Color = vaxis.Color;

const Theme = @This();

// A theme must specify all the essential colors
// Specific colors, like text can be automatically assigned.

white: Color = .{ .rgb = .{ 255, 250, 243 } },
black: Color = .{ .rgb = .{ 87, 82, 121 } },
red: Color = .{ .rgb = .{ 180, 99, 122 } },
grey: Color = .{ .rgb = .{ 206, 202, 205 } },
blue: Color = .{ .rgb = .{ 40, 105, 131 } },
green: Color = .{ .rgb = .{ 86, 148, 159 } },
purple: Color = .{ .rgb = .{ 144, 122, 169 } },
pink: Color = .{ .rgb = .{ 180, 99, 122 } },
orange: Color = .{ .rgb = .{ 234, 157, 52 } },
yellow: Color = .{ .rgb = .{ 234, 157, 52 } },

cursor: Color = .{ .rgb = .{ 87, 82, 121 } },

bg: Color = .{ .rgb = .{ 250, 244, 237 } },
fg: Color = .{ .rgb = .{ 87, 82, 121 } },

text: Color = .{ .rgb = .{ 87, 82, 121 } },

status_line: struct {
    bg: Color = .{ .rgb = .{ 255, 250, 243 } },
    fg: Color = .{ .rgb = .{ 87, 82, 121 } },
} = .{},
