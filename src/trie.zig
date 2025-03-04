const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

/// Modified Trie data structure to support state change
/// Matches the shortest prefix.
pub const Trie = struct {
    allocator: Allocator = undefined,

    init_state_id: usize = undefined,

    curr_state_id: usize = undefined,

    id_ctr: usize = 0,

    /// ID -> State
    states: std.AutoHashMap(u64, State) = undefined,

    /// Current Word
    curr_seq: std.ArrayList(u8) = undefined, // TODO: Consider changing that to std.BoundedArray

    pub const Result = enum {
        Reject,
        Accept,
        Deciding,
    };

    const State = struct {
        /// Char -> State ID
        next_state_tbl: std.AutoHashMap(u8, u64) = undefined,
        accepting: bool = false,
        id: usize = undefined,

        pub fn init(allocator: Allocator, id: usize) State {
            return State{
                .next_state_tbl = std.AutoHashMap(u8, u64).init(allocator),
                .accepting = false,
                .id = id,
            };
        }

        pub fn deinit(self: *State) void {
            self.next_state_tbl.deinit();
        }
    };

    const Self = @This();

    pub fn init(self: *Self, allocator: Allocator, words: []const []const u8) !void {
        self.states = std.AutoHashMap(u64, State).init(allocator);
        self.curr_seq = std.ArrayList(u8).init(allocator);
        self.allocator = allocator;

        self.init_state_id = 0;
        self.curr_state_id = self.init_state_id;

        try self.states.put(self.init_state_id, State.init(allocator, self.init_state_id));

        for (words) |word| {
            try self.append(word);
        }
    }

    /// Creates a new state in states, and returns its id.
    fn create_state(self: *Self) !usize {
        self.id_ctr += 1;
        const new_id = self.id_ctr;

        try self.states.put(new_id, State.init(self.allocator, new_id));
        return new_id; // Should not fail
    }

    pub fn append(self: *Self, seq: []const u8) !void {
        var curr_state_id = self.init_state_id;

        for (seq) |ch| {
            const current_state = self.states.get(curr_state_id).?;

            // if the transition is already there step.
            if (current_state.next_state_tbl.get(ch)) |next_state_id| {
                curr_state_id = next_state_id;
            } else {
                // Else add the transition
                const id = try self.create_state();
                const currentStatePtr = self.states.getPtr(curr_state_id).?;
                try currentStatePtr.next_state_tbl.put(ch, id);
                curr_state_id = id;
            }
        }

        if (self.states.getPtr(curr_state_id)) |state| {
            state.accepting = true;
        }
    }

    pub fn getCurrentWord(self : Self) []const u8 {
        return self.curr_seq.items;
    }

    pub fn reset(self: *Self) void {
        self.curr_seq.shrinkAndFree(0);
        self.curr_state_id = self.init_state_id;
    }

    pub fn step(self: *Self, ch: u8) !Result {
        const current_state = self.states.getPtr(self.curr_state_id).?;

        // If an edge with ch value exists then try step to it.
        if (current_state.next_state_tbl.get(ch)) |next_state_id| {
            self.curr_state_id = next_state_id;
            const next_state = self.states.getPtr(next_state_id).?;

            try self.curr_seq.append(ch);

            if (next_state.accepting) {
                return Result.Accept;
            }

            // the next state is not an accepting one, we can continue
            return Result.Deciding;
        } else {
            return Result.Reject;
        }
    }

    pub fn deinit(self: *Self) void {
        var val_it = self.states.valueIterator();

        while (val_it.next()) |it| {
            it.deinit();
        }

        self.states.deinit();
        self.curr_seq.deinit();
    }
};

test "Basic matching test" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        _ = gpa.deinit();
    }

    const alloc = gpa.allocator();

    var dfa = Trie{};
    const words: []const []const u8 = &[_][]const u8{ "hello", "hellr" };
    try dfa.init(alloc, words);
    defer dfa.deinit();

    try testing.expectEqual(try dfa.step('h'), Trie.Result.Deciding);
    try testing.expectEqual(try dfa.step('e'), Trie.Result.Deciding);
    try testing.expectEqual(try dfa.step('l'), Trie.Result.Deciding);
    try testing.expectEqual(try dfa.step('l'), Trie.Result.Deciding);
    try testing.expectEqual(try dfa.step('o'), Trie.Result.Accept);
    try testing.expectEqualStrings(dfa.curr_seq.items, "hello");

    dfa.reset();

    try testing.expectEqual(try dfa.step('h'), Trie.Result.Deciding);
    try testing.expectEqual(try dfa.step('e'), Trie.Result.Deciding);
    try testing.expectEqual(try dfa.step('l'), Trie.Result.Deciding);
    try testing.expectEqual(try dfa.step('l'), Trie.Result.Deciding);
    try testing.expectEqual(try dfa.step('r'), Trie.Result.Accept);
    try testing.expectEqualStrings(dfa.curr_seq.items, "hellr");
}

test "Reject test" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        _ = gpa.deinit();
    }

    const alloc = gpa.allocator();

    var dfa = Trie{};

    const words: []const []const u8 = &[_][]const u8{ "hello", "again", "world" };
    try dfa.init(alloc, words);
    defer dfa.deinit();

    try testing.expectEqual(try dfa.step('h'), Trie.Result.Deciding);
    try testing.expectEqual(try dfa.step('e'), Trie.Result.Deciding);
    try testing.expectEqual(try dfa.step('l'), Trie.Result.Deciding);
    try testing.expectEqual(try dfa.step('l'), Trie.Result.Deciding);
    try testing.expectEqual(try dfa.step('r'), Trie.Result.Reject);
}

test "smallest prefix match" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        _ = gpa.deinit();
    }

    const alloc = gpa.allocator();

    var dfa = Trie{};
    const words: []const []const u8 = &[_][]const u8{ "hello", "he" };

    try dfa.init(alloc, words);
    defer dfa.deinit();

    try testing.expectEqual(try dfa.step('h'), Trie.Result.Deciding);
    try testing.expectEqual(try dfa.step('e'), Trie.Result.Accept);
    try testing.expectEqual(try dfa.step('l'), Trie.Result.Deciding);
    try testing.expectEqual(try dfa.step('l'), Trie.Result.Deciding);
    try testing.expectEqual(try dfa.step('o'), Trie.Result.Accept);
}
