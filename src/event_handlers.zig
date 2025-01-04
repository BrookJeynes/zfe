const std = @import("std");
const App = @import("./app.zig");
const environment = @import("./environment.zig");
const zuid = @import("zuid");
const vaxis = @import("vaxis");
const Key = vaxis.Key;
const config = &@import("./config.zig").config;

pub fn inputToSlice(self: *App) []const u8 {
    self.text_input.buf.cursor = self.text_input.buf.realLength();
    return self.text_input.sliceToCursor(&self.text_input_buf);
}

pub fn handleNormalEvent(
    app: *App,
    event: App.Event,
    loop: *vaxis.Loop(App.Event),
) !void {
    switch (event) {
        .key_press => |key| {
            if ((key.codepoint == 'c' and key.mods.ctrl)) {
                app.should_quit = true;
                return;
            }

            switch (key.codepoint) {
                '-', 'h', Key.left => {
                    app.text_input.clearAndFree();

                    if (app.directories.dir.openDir("../", .{ .iterate = true })) |dir| {
                        app.directories.dir = dir;

                        app.directories.clearEntries();
                        const fuzzy = inputToSlice(app);
                        app.directories.populateEntries(fuzzy) catch |err| {
                            switch (err) {
                                error.AccessDenied => try app.notification.writeErr(.PermissionDenied),
                                else => try app.notification.writeErr(.UnknownError),
                            }
                        };

                        if (app.directories.history.pop()) |history| {
                            app.directories.entries.selected = history.selected;
                            app.directories.entries.offset = history.offset;
                        }
                    } else |err| {
                        switch (err) {
                            error.AccessDenied => try app.notification.writeErr(.PermissionDenied),
                            else => try app.notification.writeErr(.UnknownError),
                        }
                    }
                },
                Key.enter, 'l', Key.right => {
                    const entry = lbl: {
                        const entry = app.directories.getSelected() catch return;
                        if (entry) |e| break :lbl e else return;
                    };

                    switch (entry.kind) {
                        .directory => {
                            app.text_input.clearAndFree();

                            if (app.directories.dir.openDir(entry.name, .{ .iterate = true })) |dir| {
                                app.directories.dir = dir;

                                _ = app.directories.history.push(.{
                                    .selected = app.directories.entries.selected,
                                    .offset = app.directories.entries.offset,
                                });

                                app.directories.clearEntries();
                                const fuzzy = inputToSlice(app);
                                app.directories.populateEntries(fuzzy) catch |err| {
                                    switch (err) {
                                        error.AccessDenied => try app.notification.writeErr(.PermissionDenied),
                                        else => try app.notification.writeErr(.UnknownError),
                                    }
                                };
                            } else |err| {
                                switch (err) {
                                    error.AccessDenied => try app.notification.writeErr(.PermissionDenied),
                                    else => try app.notification.writeErr(.UnknownError),
                                }
                            }
                        },
                        .file => {
                            if (environment.getEditor()) |editor| {
                                try app.vx.exitAltScreen(app.tty.anyWriter());
                                try app.vx.resetState(app.tty.anyWriter());
                                loop.stop();

                                environment.openFile(app.alloc, app.directories.dir, entry.name, editor) catch {
                                    try app.notification.writeErr(.UnableToOpenFile);
                                };

                                try loop.start();
                                try app.vx.enterAltScreen(app.tty.anyWriter());
                                try app.vx.enableDetectedFeatures(app.tty.anyWriter());
                                app.vx.queueRefresh();
                            } else {
                                try app.notification.writeErr(.EditorNotSet);
                            }
                        },
                        else => {},
                    }
                },
                'j', Key.down => {
                    app.directories.entries.next(app.last_known_height);
                },
                'k', Key.up => {
                    app.directories.entries.previous(app.last_known_height);
                },
                'G' => {
                    app.directories.entries.selectLast(app.last_known_height);
                },
                'g' => app.directories.entries.selectFirst(),
                'D' => {
                    const entry = lbl: {
                        const entry = app.directories.getSelected() catch {
                            try app.notification.writeErr(.UnableToDelete);
                            return;
                        };
                        if (entry) |e| break :lbl e else return;
                    };

                    var old_path_buf: [std.fs.max_path_bytes]u8 = undefined;
                    const old_path = try app.alloc.dupe(u8, try app.directories.dir.realpath(entry.name, &old_path_buf));
                    var tmp_path_buf: [std.fs.max_path_bytes]u8 = undefined;
                    const tmp_path = try app.alloc.dupe(u8, try std.fmt.bufPrint(&tmp_path_buf, "/tmp/{s}-{s}", .{ entry.name, zuid.new.v4().toString() }));

                    if (app.directories.dir.rename(entry.name, tmp_path)) {
                        if (app.actions.push(.{
                            .delete = .{ .old = old_path, .new = tmp_path },
                        })) |prev_elem| {
                            app.alloc.free(prev_elem.delete.old);
                            app.alloc.free(prev_elem.delete.new);
                        }

                        try app.notification.writeInfo(.Deleted);
                        app.directories.removeSelected();
                    } else |err| {
                        switch (err) {
                            error.RenameAcrossMountPoints => try app.notification.writeErr(.UnableToDeleteAcrossMountPoints),
                            else => try app.notification.writeErr(.UnableToDelete),
                        }
                        app.alloc.free(old_path);
                        app.alloc.free(tmp_path);
                    }
                },
                'd' => {
                    app.text_input.clearAndFree();
                    app.directories.clearEntries();
                    app.directories.populateEntries("") catch |err| {
                        switch (err) {
                            error.AccessDenied => try app.notification.writeErr(.PermissionDenied),
                            else => try app.notification.writeErr(.UnknownError),
                        }
                    };
                    app.state = .new_dir;
                },
                '%' => {
                    app.text_input.clearAndFree();
                    app.directories.clearEntries();
                    app.directories.populateEntries("") catch |err| {
                        switch (err) {
                            error.AccessDenied => try app.notification.writeErr(.PermissionDenied),
                            else => try app.notification.writeErr(.UnknownError),
                        }
                    };
                    app.state = .new_file;
                },
                'u' => {
                    if (app.actions.pop()) |action| {
                        const selected = app.directories.entries.selected;

                        switch (action) {
                            .delete => |a| {
                                // TODO: Will overwrite an item if it has the same name.
                                if (app.directories.dir.rename(a.new, a.old)) {
                                    defer app.alloc.free(a.new);
                                    defer app.alloc.free(a.old);

                                    app.directories.clearEntries();
                                    const fuzzy = inputToSlice(app);
                                    app.directories.populateEntries(fuzzy) catch |err| {
                                        switch (err) {
                                            error.AccessDenied => try app.notification.writeErr(.PermissionDenied),
                                            else => try app.notification.writeErr(.UnknownError),
                                        }
                                    };
                                    try app.notification.writeInfo(.RestoredDelete);
                                } else |_| {
                                    try app.notification.writeErr(.UnableToUndo);
                                }
                            },
                            .rename => |a| {
                                // TODO: Will overwrite an item if it has the same name.
                                if (app.directories.dir.rename(a.new, a.old)) {
                                    defer app.alloc.free(a.new);
                                    defer app.alloc.free(a.old);

                                    app.directories.clearEntries();
                                    const fuzzy = inputToSlice(app);
                                    app.directories.populateEntries(fuzzy) catch |err| {
                                        switch (err) {
                                            error.AccessDenied => try app.notification.writeErr(.PermissionDenied),
                                            else => try app.notification.writeErr(.UnknownError),
                                        }
                                    };
                                    try app.notification.writeInfo(.RestoredRename);
                                } else |_| {
                                    try app.notification.writeErr(.UnableToUndo);
                                }
                            },
                        }

                        app.directories.entries.selected = selected;
                    } else {
                        try app.notification.writeInfo(.EmptyUndo);
                    }
                },
                '/' => {
                    app.text_input.clearAndFree();
                    app.state = .fuzzy;
                },
                'R' => {
                    app.text_input.clearAndFree();
                    app.state = .rename;

                    const entry = lbl: {
                        const entry = app.directories.getSelected() catch {
                            app.state = .normal;
                            try app.notification.writeErr(.UnableToRename);
                            return;
                        };
                        if (entry) |e| break :lbl e else {
                            app.state = .normal;
                            return;
                        }
                    };

                    app.text_input.insertSliceAtCursor(entry.name) catch {
                        app.state = .normal;
                        try app.notification.writeErr(.UnableToRename);
                        return;
                    };
                },
                'c' => {
                    app.text_input.clearAndFree();
                    app.state = .change_dir;
                },
                ':' => {
                    app.text_input.clearAndFree();
                    app.text_input.insertSliceAtCursor(":") catch {};
                    app.state = .command;
                },
                else => {},
            }
        },
        .winsize => |ws| try app.vx.resize(app.alloc, app.tty.anyWriter(), ws),
    }
}

pub fn handleInputEvent(app: *App, event: App.Event) !void {
    switch (event) {
        .key_press => |key| {
            if ((key.codepoint == 'c' and key.mods.ctrl)) {
                app.should_quit = true;
                return;
            }

            switch (key.codepoint) {
                Key.escape => {
                    switch (app.state) {
                        .fuzzy => {
                            app.directories.clearEntries();
                            app.directories.populateEntries("") catch |err| {
                                switch (err) {
                                    error.AccessDenied => try app.notification.writeErr(.PermissionDenied),
                                    else => try app.notification.writeErr(.UnknownError),
                                }
                            };
                        },
                        else => {},
                    }

                    app.text_input.clearAndFree();
                    app.state = .normal;
                },
                Key.enter => {
                    const selected = app.directories.entries.selected;
                    switch (app.state) {
                        .new_dir => {
                            const dir = inputToSlice(app);
                            if (app.directories.dir.makeDir(dir)) {
                                try app.notification.writeInfo(.CreatedFolder);

                                app.directories.clearEntries();
                                app.directories.populateEntries("") catch |err| {
                                    switch (err) {
                                        error.AccessDenied => try app.notification.writeErr(.PermissionDenied),
                                        else => try app.notification.writeErr(.UnknownError),
                                    }
                                };
                            } else |err| {
                                switch (err) {
                                    error.AccessDenied => try app.notification.writeErr(.PermissionDenied),
                                    error.PathAlreadyExists => try app.notification.writeErr(.ItemAlreadyExists),
                                    else => try app.notification.writeErr(.UnknownError),
                                }
                            }
                            app.text_input.clearAndFree();
                        },
                        .new_file => {
                            const file = inputToSlice(app);
                            if (environment.fileExists(app.directories.dir, file)) {
                                try app.notification.writeErr(.ItemAlreadyExists);
                            } else {
                                if (app.directories.dir.createFile(file, .{})) |f| {
                                    f.close();

                                    try app.notification.writeInfo(.CreatedFile);

                                    app.directories.clearEntries();
                                    app.directories.populateEntries("") catch |err| {
                                        switch (err) {
                                            error.AccessDenied => try app.notification.writeErr(.PermissionDenied),
                                            else => try app.notification.writeErr(.UnknownError),
                                        }
                                    };
                                } else |err| {
                                    switch (err) {
                                        error.AccessDenied => try app.notification.writeErr(.PermissionDenied),
                                        else => try app.notification.writeErr(.UnknownError),
                                    }
                                }
                            }
                            app.text_input.clearAndFree();
                        },
                        .rename => {
                            var dir_prefix_buf: [std.fs.max_path_bytes]u8 = undefined;
                            const dir_prefix = try app.directories.dir.realpath(".", &dir_prefix_buf);

                            const old = lbl: {
                                const entry = app.directories.getSelected() catch {
                                    try app.notification.writeErr(.UnableToRename);
                                    return;
                                };
                                if (entry) |e| break :lbl e else return;
                            };
                            const new = inputToSlice(app);

                            if (environment.fileExists(app.directories.dir, new)) {
                                try app.notification.writeErr(.ItemAlreadyExists);
                            } else {
                                app.directories.dir.rename(old.name, new) catch |err| switch (err) {
                                    error.AccessDenied => try app.notification.writeErr(.PermissionDenied),
                                    error.PathAlreadyExists => try app.notification.writeErr(.ItemAlreadyExists),
                                    else => try app.notification.writeErr(.UnknownError),
                                };
                                if (app.actions.push(.{
                                    .rename = .{
                                        .old = try std.fs.path.join(app.alloc, &.{ dir_prefix, old.name }),
                                        .new = try std.fs.path.join(app.alloc, &.{ dir_prefix, new }),
                                    },
                                })) |prev_elem| {
                                    app.alloc.free(prev_elem.rename.old);
                                    app.alloc.free(prev_elem.rename.new);
                                }

                                try app.notification.writeInfo(.Renamed);

                                app.directories.clearEntries();
                                app.directories.populateEntries("") catch |err| {
                                    switch (err) {
                                        error.AccessDenied => try app.notification.writeErr(.PermissionDenied),
                                        else => try app.notification.writeErr(.UnknownError),
                                    }
                                };
                            }
                            app.text_input.clearAndFree();
                        },
                        .change_dir => {
                            const path = inputToSlice(app);
                            if (app.directories.dir.openDir(path, .{ .iterate = true })) |dir| {
                                app.directories.dir = dir;

                                try app.notification.writeInfo(.ChangedDir);

                                app.directories.clearEntries();
                                app.directories.populateEntries("") catch |err| {
                                    switch (err) {
                                        error.AccessDenied => try app.notification.writeErr(.PermissionDenied),
                                        else => try app.notification.writeErr(.UnknownError),
                                    }
                                };
                                app.directories.history.reset();
                            } else |err| {
                                switch (err) {
                                    error.AccessDenied => try app.notification.writeErr(.PermissionDenied),
                                    error.FileNotFound => try app.notification.writeErr(.IncorrectPath),
                                    error.NotDir => try app.notification.writeErr(.IncorrectPath),
                                    else => try app.notification.writeErr(.UnknownError),
                                }
                            }

                            app.text_input.clearAndFree();
                        },
                        .command => {
                            const command = inputToSlice(app);

                            supported: {
                                if (std.mem.eql(u8, command, ":q")) {
                                    app.should_quit = true;
                                    return;
                                }

                                if (std.mem.eql(u8, command, ":config")) {
                                    if (config.config_path) |path| {
                                        if (std.fs.openDirAbsolute(std.mem.trimRight(u8, path, "/config.json"), .{ .iterate = true })) |dir| {
                                            app.directories.clearEntries();
                                            app.directories.dir = dir;
                                            app.directories.populateEntries("") catch |err| {
                                                switch (err) {
                                                    error.AccessDenied => try app.notification.writeErr(.PermissionDenied),
                                                    else => try app.notification.writeErr(.UnknownError),
                                                }
                                            };
                                        } else |_| {
                                            try app.notification.writeErr(.UnableToOpenFile);
                                        }
                                    } else {
                                        try app.text_input.insertSliceAtCursor(":ConfigNotFound");
                                    }
                                    break :supported;
                                }

                                app.text_input.clearAndFree();
                                try app.text_input.insertSliceAtCursor(":UnsupportedCommand");
                            }
                        },
                        else => {},
                    }
                    app.state = .normal;
                    app.directories.entries.selected = selected;
                },
                else => {
                    try app.text_input.update(.{ .key_press = key });

                    switch (app.state) {
                        .fuzzy => {
                            app.directories.clearEntries();
                            const fuzzy = inputToSlice(app);
                            app.directories.populateEntries(fuzzy) catch |err| {
                                switch (err) {
                                    error.AccessDenied => try app.notification.writeErr(.PermissionDenied),
                                    else => try app.notification.writeErr(.UnknownError),
                                }
                            };
                        },
                        .command => {
                            const command = inputToSlice(app);
                            if (!std.mem.startsWith(u8, command, ":")) {
                                app.text_input.clearAndFree();
                                try app.text_input.insertSliceAtCursor(":");
                            }
                        },
                        else => {},
                    }
                },
            }
        },
        .winsize => |ws| try app.vx.resize(app.alloc, app.tty.anyWriter(), ws),
    }
}
