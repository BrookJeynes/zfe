const std = @import("std");

const Self = @This();

// Seconds.
pub const notification_timeout = 3;

const Style = enum {
    err,
    info,
};

/// Simplified construct
const Error = enum {
    PermissionDenied,
    UnknownError,
    UnableToUndo,
    UnableToOpenFile,
    UnableToDelete,
    UnableToDeleteAcrossMountPoints,
    UnsupportedImageFormat,
    EditorNotSet,
    ItemAlreadyExists,
    UnableToRename,
    IncorrectPath,
};

const Info = enum {
    CreatedFile,
    CreatedFolder,
    Deleted,
    Renamed,
    RestoredDelete,
    RestoredRename,
    EmptyUndo,
    ChangedDir,
};

len: usize = 0,
buf: [1024]u8 = undefined,
style: Style = Style.info,
fbs: std.io.FixedBufferStream([]u8) = undefined,
timer: i64 = 0,

pub fn init(self: *Self) void {
    self.fbs = std.io.fixedBufferStream(&self.buf);
}

pub fn write(self: *Self, text: []const u8, style: Style) !void {
    self.fbs.reset();
    self.len = try self.fbs.write(text);
    self.timer = std.time.timestamp();

    self.style = style;
}

pub fn writeErr(self: *Self, err: Error) !void {
    try switch (err) {
        .PermissionDenied => self.write("Permission denied.", .err),
        .UnknownError => self.write("An unknown error occurred.", .err),
        .UnableToOpenFile => self.write("Unable to open file.", .err),
        .UnableToDelete => self.write("Unable to delete item.", .err),
        .UnableToDeleteAcrossMountPoints => self.write("Unable to move item to /tmp. Failed to delete.", .err),
        .UnableToUndo => self.write("Unable to undo previous action.", .err),
        .ItemAlreadyExists => self.write("Item already exists.", .err),
        .UnableToRename => self.write("Unable to rename item.", .err),
        .IncorrectPath => self.write("Unable to find path.", .err),
        .EditorNotSet => self.write("$EDITOR is not set.", .err),
        .UnsupportedImageFormat => self.write("Unsupported image format.", .err),
    };
}

pub fn writeInfo(self: *Self, info: Info) !void {
    try switch (info) {
        .CreatedFile => self.write("Successfully created file.", .info),
        .CreatedFolder => self.write("Successfully created folder.", .info),
        .Deleted => self.write("Successfully deleted item.", .info),
        .Renamed => self.write("Successfully renamed item.", .info),
        .RestoredDelete => self.write("Successfully restored deleted item.", .info),
        .RestoredRename => self.write("Successfully restored renamed item.", .info),
        .EmptyUndo => self.write("Nothing to undo.", .info),
        .ChangedDir => self.write("Successfully changed directory.", .info),
    };
}

pub fn reset(self: *Self) void {
    self.fbs.reset();
    self.len = 0;
    self.style = Style.info;
}

pub fn slice(self: *Self) []const u8 {
    return self.buf[0..self.len];
}
