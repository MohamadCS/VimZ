const std = @import("std");
const CharType: type = u8;
const GapBuffer = @import("gap_buffer.zig").GapBuffer(CharType);

/// Abstraction of GapBuffer
/// With support for common text buffer manipulations
const TextBuffer = struct {
    gap_buffer: GapBuffer,
    allocator: std.mem.Allocator,
    lines: []CharType,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !Self {
        return Self{
            .gap_buffer = try GapBuffer.init(allocator),
            .allocator = allocator,
            .lines = allocator.alloc([]CharType, 0),
        };
    }


    pub fn deinit(self: *Self) void {
        self.gap_buffer.deinit();
        self.allocator.free(self.buffer);
    }

    pub fn getLine(self: *Self, line_idx: usize) []CharType {
        var splits = std.mem.split(CharType, self.buffer, "\n");

        var curr_line: usize = 0;
        while (splits.next()) |line| : (curr_line += 1) {
            if (curr_line == line_idx) {
                return line;
            }
        }
    }



    pub fn write(self: *Self, slice: []CharType) !void {
        self.gap_buffer.write(slice);
        self.updateBuffer();
    }
};
