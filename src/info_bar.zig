const std = @import("std");

const InfoBar = @This();

const InfoStyle = enum {
    err,
    info,
};

const Error = enum {
    PermissionDenied,
    UnknownError,
    UnableToUndo,
    UnableToOpenFile,
    UnableToDeleteItem,
    EditorNotSet,
    ItemAlreadyExists,
    UnableToRename,
};

len: usize = 0,
buf: [1024]u8 = undefined,
style: InfoStyle = InfoStyle.info,
fbs: std.io.FixedBufferStream([]u8) = undefined,

pub fn init(self: *InfoBar) void {
    self.fbs = std.io.fixedBufferStream(&self.buf);
}

pub fn write(self: *InfoBar, text: []const u8, style: InfoStyle) !void {
    self.fbs.reset();
    self.len = try self.fbs.write(text);

    self.style = style;
}

pub fn write_err(self: *InfoBar, err: Error) !void {
    try switch (err) {
        .PermissionDenied => self.write("Permission denied.", .err),
        .UnknownError => self.write("An unknown error occurred.", .err),
        .UnableToOpenFile => self.write("Unable to open file.", .err),
        .UnableToDeleteItem => self.write("Unable to delete item.", .err),
        .UnableToUndo => self.write("Unable to undo previous action.", .err),
        .ItemAlreadyExists => self.write("Item already exists.", .err),
        .UnableToRename => self.write("Unable to rename item.", .err),
        .EditorNotSet => self.write("$EDITOR is not set.", .err),
    };
}

pub fn reset(self: *InfoBar) void {
    self.fbs.reset();
    self.len = 0;
    self.style = InfoStyle.info;
}

pub fn slice(self: *InfoBar) []const u8 {
    return self.buf[0..self.len];
}
