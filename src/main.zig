const std = @import("std");
const vaxis = @import("vaxis");

const log = std.log.scoped(.main);

const Vimz = @import("app.zig").App;

pub fn main() !void {

    var app = try Vimz.getInstance();
    defer app.deinit();

    try app.run();
}
