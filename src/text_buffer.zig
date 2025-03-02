const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;
const utils = @import("utils.zig");
const vimz = @import("app.zig");

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

    pub fn getLineCount(self: *Self) !usize {
        const lines = try self.gap_buffer.getLines();
        return lines.len;
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

    pub fn findNextWord(self: *Self, row: usize, col: usize, includeWordDel: bool) !vimz.Types.Position {
        // Start from first_idx, if we found a deliimter return its position,otherwise
        // return the position of the first char after the spaces
        // If we found a new line, then the word return the index of the first word of the line.
        // Even if the line is empty, we point at the first index of the line
        const line = try self.getLineInfo(row);
        const line_count = try self.getLineCount();

        // end of line

        if (col == line.len -| 1) {
            if (row == line_count -| 1) {
                return .{
                    .col = col,
                    .row = row,
                };
            } else {
                return .{
                    .col = 0,
                    .row = row + 1,
                };
            }
        }

        // BUG: last line always goes to the first col
        var stopAtNonWS: bool = false;
        for (col + 1..line.len) |i| {
            const curr_ch = try self.getCharAt(row, i);

            if (i == line.len -| 1) {
                if (row == line_count -| 1) {
                    return .{
                        .col = i,
                        .row = row,
                    };
                } else {
                    return .{
                        .col = 0,
                        .row = row + 1,
                    };
                }
            }

            if (stopAtNonWS and curr_ch != ' ') {
                return .{
                    .col = i,
                    .row = row,
                };
            }

            if (curr_ch == ' ') {
                stopAtNonWS = true;
                continue;
            }

            if (includeWordDel) {
                if (utils.delimters.get(&.{curr_ch})) |_| {
                    return .{
                        .col = i,
                        .row = row,
                    };
                }
            }
        }

        unreachable;

    }
};
