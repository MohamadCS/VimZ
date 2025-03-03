const std = @import("std");
const vaxis = @import("vaxis");
const Logger = @import("logger.zig").Logger;

const Vimz = @import("app.zig").App;

pub fn main() !void {

    _ = try Logger.getInstance();
    var app = try Vimz.getInstance();
    defer app.deinit();
    defer Logger.deinit();

    try app.run();
}
