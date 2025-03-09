const std = @import("std");
const vaxis = @import("vaxis");
const Logger = @import("logger.zig").Logger;
const builtin = @import("builtin");

const vimz = @import("vimz.zig");

pub fn main() !void {
    if (builtin.mode == .Debug) {
        _ = try Logger.getInstance();
    }
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) {
            std.debug.print("mem leak", .{});
        }
    }

    const alloc = gpa.allocator();
    defer Logger.deinit(); // would not deinit

    var app = try vimz.Core.init(alloc);
    defer app.deinit();

    try app.run();
}
