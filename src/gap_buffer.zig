const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;
const assert = std.debug.assert;

const Error = error{
    TypeError,
    NotFound,
};

pub fn GapBuffer(comptime T: type) type {
    comptime switch (@typeInfo(T)) {
        .Int => {},
        else => {
            try std.io.getStdErr().write("Type must be an integer\n");
            std.exit(0);
        },
    };

    return struct {
        /// Memory Allocator
        allocator: Allocator,

        /// Internal buffer data including the gap
        buffer: []T,

        /// The index of the start of the gap
        gap_start: usize,

        /// The index of the end of the gap
        gap_end: usize,

        /// The gap size when init() is called
        const init_size = 10;

        /// Guranteed writing memory before calling resize again
        const min_gap_size = 50;

        const Self = @This();

        pub fn init(allocator: Allocator) !Self {
            return Self{
                .allocator = allocator,
                .buffer = try allocator.alloc(T, init_size),
                .gap_start = 0,
                .gap_end = init_size - 1,
            };
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.buffer);
        }

        inline fn gapSize(self: *Self) usize {
            return self.gap_end - self.gap_start + 1;
        }

        /// Moves the cursror to new_gap_idx,
        /// The function does not alloc memory
        pub fn moveCursor(self: *Self, new_gap_idx: usize) !void {
            if (self.gap_start == new_gap_idx) {
                return;
            }

            const gap_size = self.gapSize();

            if (self.gap_start > new_gap_idx) {
                var from = self.gap_start - 1;

                // Copy backwards to avoid collisions.
                while (from >= new_gap_idx) : (if (from != 0) {
                    from -= 1;
                } else {
                    break;
                }) {
                    const to = from + gap_size;
                    self.buffer[to] = self.buffer[from];
                }

                self.gap_start = new_gap_idx;
                self.gap_end = self.gap_start + gap_size - 1;
            } else {
                const eff_end_idx = new_gap_idx + gap_size;

                // Copy Forwards to avoid collisions.
                for (self.gap_end + 1..eff_end_idx) |from| {
                    const to = from - gap_size;
                    self.buffer[to] = self.buffer[from];
                }

                self.gap_start = new_gap_idx;
                self.gap_end = self.gap_start + gap_size - 1;
            }
        }

        /// Writes a data slice begining at the current cursor index
        /// if there is the gap size is not enought, then it will
        /// allocate new memory and replace the pointer to
        /// the buffer's slice.
        pub fn write(self: *Self, data_slice: []const T) !void {
            if (self.gapSize() <= data_slice.len) {
                try self.expandGap(data_slice.len + min_gap_size);
            }

            assert(data_slice.len <= self.gapSize());

            for (0..data_slice.len, self.gap_start..) |dataIdx, bufferIdx| {
                self.buffer[bufferIdx] = data_slice[dataIdx];
            }

            self.gap_start += data_slice.len;
        }

        pub fn delete(self: *Self, count: usize) !void {
            self.gap_start = @min(0, self.gap_start - count);
        }

        /// Returns an array containing at index 0 the
        /// data to the left of the cursor, and at index 1, the
        /// data to the right of the cursor
        pub fn getBuffers(self: Self) [2][]T {
            return .{ self.buffer[0..self.gap_start], self.buffer[self.gap_end + 1 ..] };
        }

        pub fn getCursorIdx(self: *Self) usize {
            return self.gap_start;
        }

        fn expandGap(self: *Self, new_gap_size: usize) !void {
            const raw_data_size = self.buffer.len - self.gapSize();
            const new_buffer_size = raw_data_size + new_gap_size;
            const new_buffer = try self.allocator.alloc(T, new_buffer_size);

            // [0,1,gapstart,#,#,#,gapend,0,0]
            const new_gap_end = self.gap_start + new_gap_size - 1;

            // Append the prefix
            for (0..self.gap_start) |i| {
                new_buffer[i] = self.buffer[i];
            }

            // Append the suffix
            for (self.gap_end + 1..self.buffer.len, new_gap_end + 1..new_buffer.len) |oldBuffIdx, newBuffIdx| {
                new_buffer[newBuffIdx] = self.buffer[oldBuffIdx];
            }

            self.allocator.free(self.buffer);

            self.gap_end = new_gap_end;
            self.buffer = new_buffer;
        }

        pub const SearchPolicy = union(enum) {
            Number: usize,
            DelimiterSet: std.AutoHashMap(T, u8),
            Char: T,
        };

        // BUG : dont delete the delimter
        pub fn deleteForwards(self: *Self, searchPolicy: SearchPolicy,includeDelimiter : bool) !void {
            // TODO: Shrink the gap after a certain threshold.

            switch (searchPolicy) {
                .Number => |num| {
                    const maxIdx = @min(self.buffer.len - 1, self.gap_end + num);
                    self.gap_end = maxIdx;
                },

                .DelimiterSet => |set| {
                    // if it found the delmiter then we backoff by 1, otherwise, we
                    // delete until of the buffer
                    // If we want to delete until the end of the line simply
                    // include '\n' in the delimter set
                    var deleteToIdx = self.findForwards(
                        SearchPolicy{
                            .DelimiterSet = set,
                        },
                        includeDelimiter,
                    ) catch self.buffer.len;

                    deleteToIdx -|= 1;

                    self.gap_end = deleteToIdx;
                },
                else => unreachable,
            }
        }

        // BUG : dont delete the delimter
        pub fn deleteBackwards(self: *Self, searchPolicy: SearchPolicy, includeDelimiter: bool) !void {
            // TODO: Shrink the gap after a certain threshold.

            switch (searchPolicy) {
                .Number => |num| {
                    const minIdx = @max(0, self.gap_start - num);
                    self.gap_start = minIdx;
                },

                .DelimiterSet => |set| {
                    var deleteToIdx = self.findBackwards(
                        SearchPolicy{
                            .DelimiterSet = set,
                        },
                        includeDelimiter,
                    ) catch 1;

                    deleteToIdx -|= 1;
                    self.gap_start = deleteToIdx;
                },
                else => unreachable,
            }
        }

        pub fn findForwards(self: *Self, searchPolicy: SearchPolicy, includeDelimiter: bool) !usize {
            for (self.gap_end + 1..self.buffer.len) |i| {
                switch (searchPolicy) {
                    .DelimiterSet => |*set| {
                        if (set.contains(self.buffer[i])) return i;
                    },

                    .Char => |ch| {
                        if (self.buffer[i] == ch) {
                            if (includeDelimiter) {
                                return i;
                            } else {
                                return i -| 1;
                            }
                        }
                    },

                    else => unreachable,
                }
            }
            return Error.NotFound;
        }

        pub fn findBackwards(self: *Self, searchPolicy: SearchPolicy, includeDelimiter: bool) !usize {
            var i = self.gap_start;

            if (i == 0) {
                return Error.NotFound;
            }

            while (i > 0) {
                i -= 1;

                switch (searchPolicy) {
                    .DelimiterSet => |*set| {
                        if (set.contains(self.buffer[i])) return i;
                    },
                    .Char => |ch| {
                        if (self.buffer[i] == ch) {
                            if (includeDelimiter) {
                                return i;
                            } else {
                                return i -| 1;
                            }
                        }
                    },
                    else => unreachable,
                }
            }

            return Error.NotFound;
        }

        pub fn print(self: Self) void {
            const buffers = self.getBuffers();

            std.debug.print("|{s}[{},{}]{s}| length: {}\n", .{
                buffers[0],
                self.gap_start,
                self.gap_end,
                buffers[1],
                self.buffer.len,
            });
        }
    };
}

test "Test write" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        _ = gpa.deinit();
    }

    const alloc = gpa.allocator();

    var gap_buffer = try GapBuffer(u8).init(alloc);
    defer gap_buffer.deinit();

    const str: []const u8 = "hello"[0..];

    try gap_buffer.write(str);

    try testing.expectEqualStrings(
        gap_buffer.getBuffers()[0],
        str,
    );
}

test "Move gap" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        _ = gpa.deinit();
    }

    const alloc = gpa.allocator();

    var gap_buffer = try GapBuffer(u8).init(alloc);
    defer gap_buffer.deinit();

    const str: []const u8 = "hello world"[0..];

    gap_buffer.print();

    try gap_buffer.write(str);
    gap_buffer.print();

    try gap_buffer.moveCursor(0);

    gap_buffer.print();
}
