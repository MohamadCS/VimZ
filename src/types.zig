const vaxis = @import("vaxis");

const Types = @This();

pub const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
    refresh_status_line: void,
};

// Move to dedicated types file
pub const CursorState = struct {
    row: u16 = 0,
    col: u16 = 0,
};

pub const Position = struct {
    row: usize = 0,
    col: usize = 0,
};

// Move to dedicated types file
pub const Mode = enum {
    Normal,
    Insert,
    Pending,
    Visual,
};
