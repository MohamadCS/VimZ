const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;
const utils = @import("utils.zig");
const vimz = @import("vimz.zig");
const log = @import("logger.zig").Logger.log;
const Position = vimz.Position;

pub const GapBuffer = @import("gap_buffer.zig").GapBuffer(TextBuffer.CharType);

// Abstraction of a Gap buffer
pub const TextBuffer = struct {
    allocator: Allocator,
    gap_buffer: GapBuffer,

    changed: bool,

    pub const CharType: type = u8;

    const Self = @This();

    pub fn init(allocator: Allocator) !Self {
        return Self{
            .allocator = allocator,
            .gap_buffer = try GapBuffer.init(allocator),
            .changed = false,
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
        const idx = try self.gap_buffer.getAbsIdx(row, col);
        return self.gap_buffer.buffer[idx .. idx + 1];
    }

    pub inline fn getCharAt(self: *Self, row: usize, col: usize) !CharType {
        const idx = try self.gap_buffer.getAbsIdx(row, col);
        return self.gap_buffer.buffer[idx];
    }

    pub inline fn moveCursor(self: *Self, row: usize, col: usize) !void {
        const line = try self.gap_buffer.getLineInfo(row);
        self.gap_buffer.moveGap(line.offset + col);
    }

    pub inline fn insert(self: *Self, text: []const CharType, row: usize, col: usize) !void {
        self.changed = true;
        try self.moveCursor(row, col);
        try self.gap_buffer.write(text);
    }

    /// Deletes the interval between start and end, returns the begining.
    pub fn deleteInterval(self: *Self, start: Position, end: Position) !Position {
        self.changed = true;
        const start_idx = try self.gap_buffer.getRelIdx(start.row, start.col);
        const end_idx = try self.gap_buffer.getRelIdx(end.row, end.col);
        const begin_pos = if (start_idx < end_idx) start else end;
        try self.moveCursor(begin_pos.row, begin_pos.col);
        const size = @max(start_idx, end_idx) - @min(start_idx, end_idx) + 1;
        try log("From {} to {}\n", .{ start_idx, end_idx });
        try self.gap_buffer.deleteForwards(GapBuffer.SearchPolicy{ .Number = size }, false);
        return begin_pos;
    }

    pub fn findCurrentWordBegining(self: *Self, row: usize, col: usize, subWord: bool) !Position {
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

        if ((subWord and utils.delimters.get(&.{curr_ch}) != null) or curr_ch == ' ') {
            return .{
                .col = curr_col,
                .row = row,
            };
        }

        i = col;
        while (i > 0) : (i -= 1) {
            curr_ch = try self.getCharAt(row, i);

            if ((subWord and utils.delimters.get(&.{curr_ch}) != null) or curr_ch == ' ') {
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

    pub fn findCurrentWordEnd(self: *Self, row: usize, col: usize, subWord: bool) !vimz.Position {
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
        if ((subWord and utils.delimters.get(&.{curr_ch}) != null) or curr_ch == ' ') {
            return .{
                .col = curr_col,
                .row = row,
            };
        }

        for (col..line.len) |i| {
            curr_ch = try self.getCharAt(row, i);

            if ((subWord and utils.delimters.get(&.{curr_ch}) != null) or curr_ch == ' ') {
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

    pub fn findWordBeginigAux(self: *Self, row: usize, col: usize, subWord: bool) !vimz.Position {
        if (col > 0) {
            const pos = self.findCurrentWordBegining(row, col - 1, subWord);
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
        const pos = self.findCurrentWordBegining(line_idx, line.len -| 1, subWord);

        return pos;
    }

    pub fn findWordBeginig(self: *Self, row: usize, col: usize, subWord: bool) !vimz.Position {
        var res = try self.findWordBeginigAux(row, col, subWord);

        // Skip every whitespace line
        while (res.row >= 0) {
            const line = try self.getLineInfo(res.row);

            if (res.row == 0 and res.col == 0) {
                return res;
            }

            if (res.col < line.len) {
                const ch = try self.getCharAt(res.row, res.col);
                if (ch == ' ') {
                    res = try self.findWordBeginigAux(res.row, res.col, subWord);
                } else {
                    break;
                }
            } else {
                break;
            }
        }

        return res;
    }

    fn findWordEndAux(self: *Self, row: usize, col: usize, subWord: bool) !vimz.Position {
        const line = try self.getLineInfo(row);
        const line_count = try self.getLineCount();

        if (col + 1 <= line.len -| 1) {
            const pos = self.findCurrentWordEnd(row, col + 1, subWord);
            return pos;
        }

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
        const pos = self.findCurrentWordEnd(line_idx, 0, subWord);
        return pos;
    }

    pub fn findWordEnd(self: *Self, row: usize, col: usize, subWord: bool) !vimz.Position {
        var res = try self.findWordEndAux(row, col, subWord);
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
                    res = try self.findWordEndAux(res.row, res.col, subWord);
                } else {
                    break;
                }
            } else {
                break;
            }
        }

        return res;
    }

    pub fn findNextWord(self: *Self, row: usize, col: usize, subWord: bool) !vimz.Position {
        var word_pos = try self.findCurrentWordEnd(row, col, subWord);
        const line_count = try self.getLineCount();

        const line = try self.getLineInfo(row);
        // BUG: this happens even if the next word is in the same line
        if (word_pos.col == line.len -| 1) {
            if (row < line_count -| 1) {
                const next_line = try self.getLineInfo(row + 1);
                if (next_line.len == 0) {
                    return .{
                        .row = row + 1,
                        .col = 0,
                    };
                }
            }
        }

        word_pos = try self.findWordEnd(word_pos.row, word_pos.col, subWord);
        word_pos = try self.findCurrentWordBegining(word_pos.row, word_pos.col, subWord);
        return word_pos;
    }

    pub fn appendNextLine(self: *Self, row: usize, col: usize) !vimz.Position {
        const line_count = try self.getLineCount();
        if (row == line_count -| 1) {
            return .{
                .row = row,
                .col = col,
            };
        }

        const curr_line = try self.getLineInfo(row);
        const end_line_pos = Position{
            .row = row,
            .col = curr_line.len,
        };
        _ = try self.deleteInterval(end_line_pos, end_line_pos);
        try self.insert(" ", row, curr_line.len); // remove \n
        return .{
            .row = row,
            .col = curr_line.len,
        };
    }
};
