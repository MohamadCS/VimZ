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

        const init_size = 5;
        const min_gap_size = 3;

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

        pub fn moveGap(self: *Self, new_cursor_idx: usize) !void {
            if (self.gap_start - 1 == new_cursor_idx) {
                return;
            }

            const gap_size = self.gapSize();

            // old cursor pos = gap_start - 1
            // -----c-----
            //  From cursor +1 to gap_start copy to cursror +1 + gap_size
            //  0 1 2 3 4 5 6 7 8 9 10 11
            // [1,2,3,4,5,6,7,#,#,#,X,Y]
            // [1,2,#,#,#,3,4,5,6,7,X,Y]
            if (self.gap_start - 1 > new_cursor_idx) {

                var from = self.gap_start - 1;

                while(from >= new_cursor_idx + 1) : (from-=1) {
                    const to = from + gap_size;
                    self.buffer[to] = self.buffer[from];
                }

                self.gap_start = new_cursor_idx + 1;
                self.gap_end = self.gap_start + gap_size - 1;
            } else if (self.gap_start - 1 < new_cursor_idx) {
                //  0 1 2 3 4 5 6 7 8 9 10 11
                // [0,1,#,#,#,2,3,4,5,6,X,Y]
                // [0,1,2,3,4,5,6,#,#,#,X,Y]

                const effective_cursor_idx = new_cursor_idx + gap_size;

                for (self.gap_end + 1..effective_cursor_idx + 1) |from| {
                    const to = from - gap_size;
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

        // Returns an array of the left and right buffers
        pub fn getBuffers(self: Self) [2][]T {
            return .{ self.buffer[0..self.gap_start], self.buffer[self.gap_end + 1 ..] };
        }

        pub fn print(self: Self) void {
            const buffers = self.getBuffers();

            std.debug.print("|{s}[{},{}]{s}| length: {}\n", .{ buffers[0], self.gap_start, self.gap_end, buffers[1], self.buffer.len });
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

    try gap_buffer.moveGap(3);

    gap_buffer.print();
}
