const std = @import("std");

const Error = error{
    NotInGitRepo,
};

pub const delimters = [_]u21{
    ' ',
    '\t',
    '\n',
    '.',
    ',',
    ';',
    ':',
    '!',
    '?',
    '(',
    ')',
    '[',
    ']',
    '{',
    '}',
    '-',
    '+',
    '=',
    '/',
    '\\',
    '*',
    '&',
    '|',
    '^',
    '~',
    '$',
    '@',
    '#',
    '%',
    '<',
    '>',
    '_',
};

/// Needs to be freed
pub fn getDelimterSet(allocator: std.mem.Allocator) !std.AutoHashMap(u21, u8) {
    var map = std.AutoHashMap(u21, u8).init(allocator);
    for (delimters) |delimiter| {
        try map.put(delimiter, 0);
    }

    return map;
}

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
