const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

pub const GapBuffer = @import("gap_buffer.zig").GapBuffer(TextBuffer.CharType);

// Abstraction of a Gap buffer
pub const TextBuffer = struct {
    allocator: Allocator,
    gap_buffer: GapBuffer,

    pub const CharType: type = u8;

    const Self = @This();

    pub fn init(allocator: Allocator) !Self {
        return Self{
            .allocator = allocator,
            .gap_buffer = try GapBuffer.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.gap_buffer.deinit();
    }

    pub fn getLineCount(self: *Self) usize {
        return self.gap_buffer.lines.items.len;
    }

    pub inline fn getLineInfo(self: *Self, line: usize) !GapBuffer.Line {
        return try self.gap_buffer.getLineInfo(line);
    }

    pub inline fn getSlicedCharAt(self: *Self, row: usize, col: usize) ![]CharType {
        const idx = try self.gap_buffer.getIdx(row, col);
        return self.gap_buffer.buffer[idx .. idx + 1];
    }

    pub inline fn getCharAt(self: *Self, row: usize, col: usize) !CharType {
        const idx = try self.gap_buffer.getIdx(row, col);
        return self.gap_buffer.buffer[idx];
    }

    pub inline fn moveCursor(self: *Self, row: usize, col: usize) !void {
        const line = try self.gap_buffer.getLineInfo(row);
        try self.gap_buffer.moveGap(line.offset + col);
    }

    pub inline fn insert(self: *Self, text: []const CharType, row: usize, col: usize) !void {
        try self.moveCursor(row, col);
        try self.gap_buffer.write(text);
    }

    pub inline fn deleteLine(self: *Self, row: usize) !void {
        try self.moveCursor(row, 0);
        const line = try self.gap_buffer.getLineInfo(row);
        try self.gap_buffer.deleteForwards(GapBuffer.SearchPolicy{ .Number = line.len + 1 }, true);
    }
};
