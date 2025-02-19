const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;
const assert = std.debug.assert;

const Error = error{
    TypeError,
};

pub fn GapBuffer(comptime T: type) type {
    comptime switch (@typeInfo(T)) {
        .Int => {},
        else => {
            try std.io.getStdErr().write("Type must be uN or iN\n");
            std.exit(0);
        },
    };

    return struct {
        allocator: Allocator,

        buffer: []T,
        gap_start: usize,
        gap_end: usize,

        const init_size = 10;
        const min_gap_size = 0;

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

        // old cursor pos = gap_start - 1
        // -----c-----
        // [1,2,3,#,#,4,6]
        // [1,2,3,#,#,]
        fn moveGap(self: *Self, new_cursor_idx: usize) !void {
            if (self.gap_start - 1 == new_cursor_idx) {
                return;
            }

            const gap_size = self.gapSize();

            if (self.gap_start - 1 > new_cursor_idx) {
                const copy_data_size = self.gap_start - new_cursor_idx - 1;
                std.debug.print("Need to copy: {}\n", .{copy_data_size});

                const copy_to_idx_start = self.gap_end - copy_data_size + 1;

                for (new_cursor_idx + 1..self.gap_start, copy_to_idx_start..self.gap_end + 1) |from, to| {
                    self.buffer[to] = self.buffer[from];
                }

                self.gap_start = new_cursor_idx + 1;
                self.gap_end = self.gap_start + gap_size - 1;
            } else if (self.gap_start - 1 < new_cursor_idx) {
                const effective_cursor_idx = new_cursor_idx + gap_size;
                const copy_data_size = effective_cursor_idx - self.gap_end;
                std.debug.print("Need to copy: {}\n", .{copy_data_size});

                for (self.gap_end + 1..effective_cursor_idx + 1, self.gap_start..self.gap_start + copy_data_size) |from, to| {
                    self.buffer[to] = self.buffer[from];
                }

                self.gap_start = new_cursor_idx + 1;
                self.gap_end = self.gap_start + gap_size - 1;
            }
        }

        fn expandGap(self: *Self, new_gap_size: usize) !void {
            const raw_data_size = self.buffer.len - self.gapSize();
            const new_buffer_size = raw_data_size + new_gap_size;
            const new_buffer = try self.allocator.alloc(T, new_buffer_size);

            // [0,1,gapstart,#,#,#,gapend,0,0]
            const new_gap_end = self.gap_start + new_gap_size - 1;

            // Append the prefix
            for (0..self.gap_start) |i| {
                new_buffer[i] = self.buffer[0];
            }

            // Append the suffix
            for (self.gap_end + 1..self.buffer.len, new_gap_end + 1..new_buffer.len) |oldBuffIdx, newBuffIdx| {
                new_buffer[newBuffIdx] = self.buffer[oldBuffIdx];
            }

            self.allocator.free(self.buffer);

            self.gap_end = new_gap_end;
            self.buffer = new_buffer;
        }

        pub fn write(self: *Self, data_slice: []const T) !void {
            if (self.gapSize() < data_slice.len) {
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

        // Returns an array of the left and right buffers
        pub fn getBuffers(self: Self) [2][]T {
            return .{ self.buffer[0..self.gap_start], self.buffer[self.gap_end + 1 ..] };
        }

        fn print(self: Self) void {
            const buffers = self.getBuffers();
            std.debug.print("{s}[Gap]{s}\n", .{ buffers[0], buffers[1] });
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


}
