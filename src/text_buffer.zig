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

        var curr_col = col;

        var i: usize = col;
        while (i > 0) : (i -= 1) {
            curr_ch = try self.getCharAt(row, i);

            if (curr_ch == ' ') {
                curr_col = i;
            } else {
                break;
            }
        }

        curr_ch = try self.getCharAt(row, curr_col);
        // if the current char is a delimiter, then its the begining of the word
        if (utils.delimters.get(&.{curr_ch})) |_| {
            return .{
                .col = curr_col,
                .row = row,
            };
        }

        i = col;
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

        var curr_col = col;
        for (col..line.len) |i| {
            curr_ch = try self.getCharAt(row, i);

            if (curr_ch == ' ') {
                curr_col = i;
            } else {
                break;
            }
        }

        curr_ch = try self.getCharAt(row, curr_col);
        // if the first is ws, then this will return the last ws,
        // otherwise, the end of delimter is itself.
        if (utils.delimters.get(&.{curr_ch})) |_| {
            return .{
                .col = curr_col,
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

    pub fn findWordBeginigAux(self: *Self, row: usize, col: usize) !vimz.Types.Position {
        if (col > 0) {
            const pos = self.findCurrentWordBegining(row, col - 1);
            return pos;
        }

        if (row == 0) {
            return .{
                .row = 0,
                .col = 0,
            };
        }

        var line_idx = row - 1;
        var curr_row = line_idx; // curr_row >= 0;
        while (curr_row > 0) : (curr_row -= 1) {
            const curr_line = try self.getLineInfo(curr_row);
            if (curr_line.len == 0) {
                continue;
            } else {
                line_idx = curr_row;
                break;
            }
        }

        const line = try self.getLineInfo(line_idx);
        const pos = self.findCurrentWordBegining(line_idx, line.len -| 1);

        return pos;
    }

    pub fn findWordBeginig(self: *Self, row: usize, col: usize) !vimz.Types.Position {
        var res = try self.findWordBeginigAux(row, col);

        // Skip every whitespace line
        while (res.row >= 0) {
            const line = try self.getLineInfo(res.row);

            if (res.row == 0 and res.col == 0) {
                return res;
            }

            if (res.col < line.len) {
                const ch = try self.getCharAt(res.row, res.col);
                if (ch == ' ') {
                    res = try self.findWordBeginigAux(res.row, res.col);
                } else {
                    break;
                }
            } else {
                break;
            }
        }

        return res;
    }

    fn findWordEndAux(self: *Self, row: usize, col: usize) !vimz.Types.Position {
        const line = try self.getLineInfo(row);

        if (col + 1 <= line.len -| 1) {
            const pos = self.findCurrentWordEnd(row, col + 1);
            return pos;
        }

        const line_count = try self.getLineCount();

        if (line_count -| 1 == row) {
            return .{
                .row = row,
                .col = col,
            };
        }

        var line_idx = row + 1;
        for (row + 1..line_count) |curr_row| {
            const curr_line = try self.getLineInfo(curr_row);
            if (curr_line.len == 0) {
                continue;
            } else {
                line_idx = curr_row;
                break;
            }
        }

        // found a non-empty line
        const pos = self.findCurrentWordEnd(line_idx, 0);
        return pos;
    }

    pub fn findWordEnd(self: *Self, row: usize, col: usize) !vimz.Types.Position {
        var res = try self.findWordEndAux(row, col);
        const line_count = try self.getLineCount();

        // Skip every whitespace line
        while (res.row <= line_count -| 1) {
            const line = try self.getLineInfo(res.row);

            if (res.row == line_count -| 1 and res.col == line.len -| 1) {
                return res;
            }

            if (res.col < line.len) {
                const ch = try self.getCharAt(res.row, res.col);
                if (ch == ' ') {
                    res = try self.findWordEndAux(res.row, res.col);
                } else {
                    break;
                }
            } else {
                break;
            }
        }

        return res;
    }
    pub fn findNextWord(self: *Self, row: usize, col: usize) !vimz.Types.Position {
        var word_pos = try self.findCurrentWordEnd(row, col);
        const line_count = try self.getLineCount();

        if (row < line_count -| 1) {
            const next_line = try self.getLineInfo(row + 1);
            if (next_line.len == 0) {
                return .{
                    .row = row + 1,
                    .col = 0,
                };
            }
        }

        word_pos = try self.findWordEnd(word_pos.row, word_pos.col);
        word_pos = try self.findCurrentWordBegining(word_pos.row, word_pos.col);
        return word_pos;
    }
};
