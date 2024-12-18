const std = @import("std");

const Self = @This();

/// Seconds.
pub const notification_timeout = 3;

const Style = enum {
    err,
    info,
    warn,
};

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
    ConfigSyntaxError,
    ConfigUnknownError,
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

const Warn = enum { DeprecatedConfigPath };

buf: [1024]u8 = undefined,
style: Style = Style.info,
fbs: std.io.FixedBufferStream([]u8) = undefined,
/// How long until the notification disappears in seconds.
timer: i64 = 0,

pub fn init(self: *Self) void {
    self.fbs = std.io.fixedBufferStream(&self.buf);
}

pub fn write(self: *Self, text: []const u8, style: Style) !void {
    self.fbs.reset();
    _ = try self.fbs.write(text);
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
        .ConfigSyntaxError => self.write("Could not read config due to a syntax error.", .err),
        .ConfigUnknownError => self.write("Could not read config due to an unknown error.", .err),
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

pub fn writeWarn(self: *Self, warning: Warn) !void {
    try switch (warning) {
        .DeprecatedConfigPath => self.write("You are using a deprecated config path. Please move your config to either `$XDG_CONFIG_HOME/zfe` or `$HOME/.zfe`", .warn),
    };
}

pub fn reset(self: *Self) void {
    self.fbs.reset();
    self.style = Style.info;
}

pub fn slice(self: *Self) []const u8 {
    return self.fbs.getWritten();
}
