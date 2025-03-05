const std = @import("std");
const builtin = @import("builtin");

const Allocator = std.mem.Allocator;
pub const Logger = struct {
    file: std.fs.File,

    const Self = @This();
    pub fn init(file_name: []const u8) !Self {
        return Self{
            .file = try std.fs.cwd().createFile(file_name, .{}),
        };
    }

    var instance: ?Self = null;
    pub fn getInstance() !*Self {
        if (Logger.instance) |*logger| {
            return logger;
        }

        Logger.instance = try Logger.init("log");
        return &Logger.instance.?;
    }

    pub fn deinit() void {
        if (instance) |*logger| {
            logger.file.close();
        }
    }

    pub fn log(comptime fmt: []const u8, args: anytype) !void {
        if (builtin.mode == .Debug) {
            const logger = try Logger.getInstance();
            try logger.file.writer().print(fmt, args);
        }
    }
};
