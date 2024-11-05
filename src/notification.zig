const std = @import("std");

const Self = @This();

const Style = enum {
    err,
    info,
};

const Error = enum {
    PermissionDenied,
    UnknownError,
    UnableToUndo,
    UnableToOpenFile,
    UnableToDeleteItem,
    UnableToDeleteAcrossMountPoints,
    UnsupportedImageFormat,
    EditorNotSet,
    ItemAlreadyExists,
    UnableToRename,
    IncorrectPath,
    UnableToOpenPdf,
    UnableToRenderPdf,
    UnableToRenderTextPdf,
};

len: usize = 0,
buf: [1024]u8 = undefined,
style: Style = Style.info,
fbs: std.io.FixedBufferStream([]u8) = undefined,

pub fn init(self: *Self) void {
    self.fbs = std.io.fixedBufferStream(&self.buf);
}

pub fn write(self: *Self, text: []const u8, style: Style) !void {
    self.fbs.reset();
    self.len = try self.fbs.write(text);

    self.style = style;
}

pub fn write_err(self: *Self, err: Error) !void {
    try switch (err) {
        .PermissionDenied => self.write("Permission denied.", .err),
        .UnknownError => self.write("An unknown error occurred.", .err),
        .UnableToOpenFile => self.write("Unable to open file.", .err),
        .UnableToDeleteItem => self.write("Unable to delete item.", .err),
        .UnableToDeleteAcrossMountPoints => self.write("Unable to move item to /tmp. Failed to delete.", .err),
        .UnableToUndo => self.write("Unable to undo previous action.", .err),
        .ItemAlreadyExists => self.write("Item already exists.", .err),
        .UnableToRename => self.write("Unable to rename item.", .err),
        .IncorrectPath => self.write("Unable to find path.", .err),
        .EditorNotSet => self.write("$EDITOR is not set.", .err),
        .UnsupportedImageFormat => self.write("Unsupported image format.", .err),
        .UnableToOpenPdf => self.write("Unable to open PDF. Attempting to render text version.", .err),
        .UnableToRenderPdf => self.write("Unable to render PDF. Attempting to render text version.", .err),
        .UnableToRenderTextPdf => self.write("Unable to render text PDF. Install pdftotext for text rendering.", .err),
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
