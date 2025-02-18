const std = @import("std");
const vaxis = @import("vaxis");

const log = std.log.scoped(.main);

const App = @import("app.zig").App;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) {
            log.err("memory leak", .{});
        }
    }
    const alloc = gpa.allocator();

    var app = try App.init(alloc);
    defer app.deinit();

    try app.run();
}
