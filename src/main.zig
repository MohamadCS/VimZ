const std = @import("std");
const vaxis = @import("vaxis");
const Logger = @import("logger.zig").Logger;
const builtin = @import("builtin");

const Vimz = @import("app.zig").App;

pub fn main() !void {

    if (builtin.mode == .Debug) {
        _ = try Logger.getInstance();
    }

    defer Logger.deinit(); // would not deinit

    var app = try Vimz.getInstance();
    defer app.deinit();

    try app.run();

}
