const std = @import("std");
const vaxis = @import("vaxis");
const Logger = @import("logger.zig").Logger;
const builtin = @import("builtin");

const Vimz = @import("app.zig").App;

pub fn main() !void {
    var logger: *Logger = undefined;

    if (builtin.mode == .Debug) {
        logger = try Logger.getInstance();
    }

    var app = try Vimz.getInstance();
    defer app.deinit();
    defer Logger.deinit();

    try app.run();

    if (builtin.mode == .Debug) {
        Logger.deinit();
    }
}
