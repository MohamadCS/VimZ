const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;
const utils = @import("utils.zig");
const vimz = @import("app.zig");
const log = @import("logger.zig").Logger.log;

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

    pub fn deleteWord(self: *Self, row: usize, col: usize) !void {
        try self.moveCursor(row, col);
        try self.gap_buffer.deleteForwards(GapBuffer.SearchPolicy{ .DelimiterSet = utils.delimters }, false);
    }

    // If the current char is whitespace, remove everywhitespace, otherwise
    // go to the begining of the word, and remove until the end of the word
    pub fn deleteInsideWord(self: *Self, row: usize, col: usize) !vimz.Types.Position {
        const start_pos = try self.findCurrentWordBegining(row, col);
        const end_pos = try self.findCurrentWordEnd(row, col);

        try self.moveCursor(start_pos.row, start_pos.col);
        try self.gap_buffer.deleteForwards(GapBuffer.SearchPolicy{ .Number = end_pos.col + 1 - start_pos.col }, false);

        return start_pos;
    }

    pub fn findCurrentWordBegining(self: *Self, row: usize, col: usize) !vimz.Types.Position {
        const line = try self.getLineInfo(row);

        if (line.len == 0) {
            return .{
                .row = row,
                .col = col,
            };
        }

        var curr_ch = try self.getCharAt(row, col);

        // if the current char is a delimiter, then its the begining of the word
        if (utils.delimters.get(&.{curr_ch})) |_| {
            return .{
                .col = col,
                .row = row,
            };
        }

        var i = col;
        while (i > 0) : (i -= 1) {
            curr_ch = try self.getCharAt(row, i);

            if (utils.delimters.get(&.{curr_ch})) |_| {
                return .{
                    // This is never the end of the line, since it
                    .col = i + 1,
                    .row = row,
                };
            }
        }

        return .{
            .col = i,
            .row = row,
        };
    }

    pub fn findCurrentWordEnd(self: *Self, row: usize, col: usize) !vimz.Types.Position {
        const line = try self.getLineInfo(row);

        if (line.len == 0) {
            return .{
                .row = row,
                .col = col,
            };
        }

        var curr_ch = try self.getCharAt(row, col);

        // if the current char is a delimiter, then its the begining of the word
        if (utils.delimters.get(&.{curr_ch})) |_| {
            return .{
                .col = col,
                .row = row,
            };
        }

        for (col..line.len) |i| {
            curr_ch = try self.getCharAt(row, i);

            if (utils.delimters.get(&.{curr_ch})) |_| {
                return .{
                    // This is never the end of the line, since it
                    .col = i - 1,
                    .row = row,
                };
            }
        }

        return .{
            .col = line.len - 1,
            .row = row,
        };
    }

    // BUG: last line out of bounds.
    // TODO: Skip WS 
    pub fn findWordEnd(self: *Self, row: usize, col: usize) !vimz.Types.Position {
        // const line_count = try self.getLineCount();
        const line = try self.getLineInfo(row);

        if (col + 1 <= line.len -| 1) {
            const pos = self.findCurrentWordEnd(row, col + 1);
            return pos;
        }

        const line_count = try self.getLineCount();

        if (line_count -| 1 == row) {
            return .{ .row = row, .col = col };
        }

        var line_idx = row + 1;
        var curr_line = try self.getLineInfo(row + 1);

        while (curr_line.len == 0 and line_idx < line_count) {
            line_idx += 1;
            curr_line = try self.getLineInfo(line_idx);
        }

        // meaning the last line is empty
        if (line_idx == line_count) {
            return .{
                .col = 0,
                .row = line_count -| 1,
            };
        }

        // found a non-empty line
        const pos = self.findWordEnd(line_idx, 0);
        return pos;
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
