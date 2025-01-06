const App = @import("app.zig");
const environment = @import("environment.zig");
const _config = &@import("./config.zig").config;

///Navigate the user to the config dir.
pub fn config(app: *App) !void {
    const dir = dir: {
        notfound: {
            break :dir (_config.configDir() catch break :notfound) orelse break :notfound;
        }
        try app.notification.writeErr(.ConfigPathNotFound);
        return;
    };
    app.directories.clearEntries();
    app.directories.dir.close();
    app.directories.dir = dir;
    app.directories.populateEntries("") catch |err| {
        switch (err) {
            error.AccessDenied => try app.notification.writeErr(.PermissionDenied),
            else => try app.notification.writeErr(.UnknownError),
        }
    };
}

///Navigate the user to the trash dir.
pub fn trash(app: *App) !void {
    const dir = dir: {
        notfound: {
            break :dir (_config.trashDir() catch break :notfound) orelse break :notfound;
        }
        try app.notification.writeErr(.ConfigPathNotFound);
        return;
    };
    app.directories.clearEntries();
    app.directories.dir.close();
    app.directories.dir = dir;
    app.directories.populateEntries("") catch |err| {
        switch (err) {
            error.AccessDenied => try app.notification.writeErr(.PermissionDenied),
            else => try app.notification.writeErr(.UnknownError),
        }
    };
}

///Empty the trash.
pub fn emptyTrash(app: *App) !void {
    const dir = dir: {
        notfound: {
            break :dir (_config.trashDir() catch break :notfound) orelse break :notfound;
        }
        try app.notification.writeErr(.ConfigPathNotFound);
        return;
    };

    var trash_dir = dir;
    defer trash_dir.close();
    const failed = try environment.deleteContents(trash_dir);
    if (failed > 0) try app.notification.writeErr(.FailedToDeleteSomeItems);

    app.directories.clearEntries();
    app.directories.populateEntries("") catch |err| {
        switch (err) {
            error.AccessDenied => try app.notification.writeErr(.PermissionDenied),
            else => try app.notification.writeErr(.UnknownError),
        }
    };
}
