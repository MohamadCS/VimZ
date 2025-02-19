const std = @import("std");
const vaxis = @import("vaxis");
const Cell = vaxis.Cell;

const Allocator = std.mem.Allocator;


pub const Error = enum {
    OutOfBound,
};

pub const TextData = struct {
    rows: std.DoublyLinkedList(std.DoublyLinkedList(u8)) = .{.{}},
    currentRowNode: ?*std.DoublyLinkedList(std.DoublyLinkedList(u8)).Node = null,
    selectedNode: ?*std.DoublyLinkedList(u8).Node = null,

    rowsNum: u16 = 0,
    colsNum: u16 = 0,
    const Self = @This();

};
