const std = @import("std");
const vaxis = @import("vaxis");
const Cell = vaxis.Cell;

const CharType: type = u8;
const GapBuffer = @import("gap_buffer.zig").GapBuffer(CharType);



fg: vaxis.Color = .{ .rgb = .{ 87, 82, 121 } },
