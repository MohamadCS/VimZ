const std = @import("std");

const Error = error{
    NotInGitRepo,
};

pub const open_brak = std.StaticStringMap(void).initComptime(.{
    .{ "[", {} },
    .{ "{", {} },
    .{ "(", {} },
    .{ "[", {} },
});

pub const close_brak = std.StaticStringMap(void).initComptime(.{
    .{ "]", {} },
    .{ "}", {} },
    .{ ")", {} },
    .{ "]", {} },
});

pub const delimters = std.StaticStringMap(void).initComptime(.{
    .{ " ", {} },
    .{ "\t", {} },
    .{ "\n", {} },
    .{ ".", {} },
    .{ ",", {} },
    .{ ";", {} },
    .{ ":", {} },
    .{ "!", {} },
    .{ "?", {} },
    .{ "(", {} },
    .{ ")", {} },
    .{ "[", {} },
    .{ "]", {} },
    .{ "{", {} },
    .{ "}", {} },
    .{ "-", {} },
    .{ "+", {} },
    .{ "=", {} },
    .{ "/", {} },
    .{ "\\", {} },
    .{ "*", {} },
    .{ "&", {} },
    .{ "|", {} },
    .{ "^", {} },
    .{ "~", {} },
    .{ "$", {} },
    .{ "@", {} },
    .{ "#", {} },
    .{ "%", {} },
    .{ "<", {} },
    .{ ">", {} },
    .{ "\"", {} },
    .{ "\'", {} },
});

pub fn digitNum(comptime T: type, x: T) usize {
    comptime switch (@typeInfo(T)) {
        .int => {},
        inline else => {
            std.process.exit(1);
        },
    };

    var y = x;
    var digits_num: usize = 1;

    while (y / 10 != 0) : (y /= 10) {
        digits_num += 1;
    }
    return digits_num;
}

pub fn getGitBranch(allocator: std.mem.Allocator) ![]u8 {
    const argv = [_][]const u8{ "git", "rev-parse", "--abbrev-ref", "HEAD" };
    const process = try std.process.Child.run(.{ .argv = &argv, .allocator = allocator });
    defer allocator.free(process.stderr);
    errdefer allocator.free(process.stdout);

    if (process.stderr.len > 0) {
        return Error.NotInGitRepo;
    }

    return process.stdout;
}
