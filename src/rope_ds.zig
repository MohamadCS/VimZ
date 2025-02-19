const std = @import("std");
const Allocator = std.mem.Allocator;

const Error = error{
    OutOfBounds,
    Unexpected,
    EmptyLeafNode,
};

fn BasicRope(comptime T: type) type {
    return struct {
        root: ?*Node,

        const Node = struct {
            allocator: Allocator,
            left: ?*Node = null,
            right: ?*Node = null,
            length: usize,
            data: ?[]T = null,
        };

        const Self = @This();

        pub fn init(allocator: Allocator) Self {
            return Self{ .root = null, .allocator = allocator };
        }

        fn destroyTree(self: *Self, root: *Node) void {
            if (root.left == null and root.right == null) {
                self.allocator.destroy(root);
                return;
            }

            if (root.left) |value| {
                self.destroyTree(value);
            }

            if (root.right) |value| {
                self.destroyTree(value);
            }
        }

        pub fn deinit(self: *Self) void {
            if (self.root) |value| {
                self.destroyTree(value);
            }

            self.root = null;
        }

        fn isLeaf(node: *Node) bool {
            return node.left == null and node.right == null;
        }

        fn findAux(root: *Node, i: usize) !void {
            if (isLeaf(root)) {
                if (root.data.?) |value| {
                    if(value.len >= i){
                        return Error.Unexpected;
                    } else {
                        return value[i];
                    }
                } else {
                    return Error.EmptyLeafNode;
                }
            }

            if (root.length > i) {
                if (root.left) |value| {
                    return findAux(value, i);
                } else {
                    return Error.Unexpected;
                }
            }

            if (root.length <= i) {
                if (root.left) |value| {
                    return findAux(value, root.length - i);
                } else {
                    return Error.Unexpected;
                }
            }
        }

        pub fn find(self: *Self, i: usize) !void {
            if(self.root) |value| {
                return try findAux(value,i);
            } else {
                return Error.OutOfBounds;
            }
        }

    };
}
