const std = @import("std");

const Error = error{
    NotInGitRepo,
};

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
    .{ "_", {} },
});

// TODO: add a process that checks if the  branch has changed
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
