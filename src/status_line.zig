const std = @import("std");
const vaxis = @import("vaxis");
const Cell = vaxis.Cell;

const CharType: type = u8;
const GapBuffer = @import("gap_buffer.zig").GapBuffer(CharType);

const Allocator = std.mem.Allocator;



pub const StatusLine = @This();


fg: vaxis.Color = .{ .rgb = .{ 87, 82, 121 } },




fn draw(self : *StatusLine )



