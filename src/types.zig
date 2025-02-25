const vaxis = @import("vaxis");

const Types = @This();

pub const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
    refresh_status_line : u1,

};

// Move to dedicated types file
pub const CursorState = struct {
    row: u16 = 0,
    col: u16 = 0,
    abs_row: usize = 0,
    abs_col: usize = 0,
};

// Move to dedicated types file
pub const Mode = enum {
    Normal,
    Insert,
};
