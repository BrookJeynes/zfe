const std = @import("std");
const builtin = @import("builtin");
const environment = @import("./environment.zig");
const Notification = @import("./notification.zig");
const config = &@import("./config.zig").config;
const List = @import("./list.zig").List;
const Directories = @import("./directories.zig");
const CircStack = @import("./circ_stack.zig").CircularStack;
const zuid = @import("zuid");
const vaxis = @import("vaxis");
const Key = vaxis.Key;

pub const State = enum {
    normal,
    fuzzy,
    new_dir,
    new_file,
    change_dir,
    rename,
};

const ActionPaths = struct {
    /// Allocated.
    old: []const u8,
    /// Allocated.
    new: []const u8,
};

pub const Action = union(enum) {
    delete: ActionPaths,
    rename: ActionPaths,
};

const Event = union(enum) {
    key_press: Key,
    winsize: vaxis.Winsize,
};

const top_div: u16 = 1;
const info_div: u16 = 1;
const bottom_div: u16 = 1;
const actions_len = 100;

const App = @This();

alloc: std.mem.Allocator,
should_quit: bool,
vx: vaxis.Vaxis = undefined,
tty: vaxis.Tty = undefined,
state: State = .normal,
actions: CircStack(Action, actions_len),

// Used to detect whether to re-render an image.
current_item_path_buf: [std.fs.max_path_bytes]u8 = undefined,
current_item_path: []u8 = "",
last_item_path_buf: [std.fs.max_path_bytes]u8 = undefined,
last_item_path: []u8 = "",
file_info_buf: [std.fs.max_path_bytes]u8 = undefined,
file_name_buf: [std.fs.max_path_bytes + 2]u8 = undefined, // +2 to accomodate for [<file_name>]

directories: Directories,
notification: Notification,

text_input: vaxis.widgets.TextInput,
text_input_buf: [std.fs.max_path_bytes]u8 = undefined,

image: ?vaxis.Image = null,
last_known_height: usize,

pub fn init(alloc: std.mem.Allocator) !App {
    var vx = try vaxis.init(alloc, .{
        .kitty_keyboard_flags = .{
            .report_text = false,
            .disambiguate = false,
            .report_events = false,
            .report_alternate_keys = false,
            .report_all_as_ctl_seqs = false,
        },
    });

    return App{
        .alloc = alloc,
        .should_quit = false,
        .vx = vx,
        .tty = try vaxis.Tty.init(),
        .directories = try Directories.init(alloc),
        .text_input = vaxis.widgets.TextInput.init(alloc, &vx.unicode),
        .notification = Notification{},
        .actions = CircStack(Action, actions_len).init(),
        .last_known_height = vx.window().height,
    };
}

pub fn deinit(self: *App) void {
    for (self.actions.buf[0..self.actions.count]) |action| {
        switch (action) {
            .delete, .rename => |a| {
                self.alloc.free(a.new);
                self.alloc.free(a.old);
            },
        }
    }

    self.directories.deinit();
    self.text_input.deinit();
    self.vx.deinit(self.alloc, self.tty.anyWriter());
    self.tty.deinit();
}

pub fn run(self: *App) !void {
    self.notification.init();

    try self.directories.populateEntries("");

    var loop: vaxis.Loop(Event) = .{
        .vaxis = &self.vx,
        .tty = &self.tty,
    };
    try loop.start();
    defer loop.stop();

    try self.vx.enterAltScreen(self.tty.anyWriter());
    try self.vx.queryTerminal(self.tty.anyWriter(), 1 * std.time.ns_per_s);

    while (!self.should_quit) {
        loop.pollEvent();
        while (loop.tryEvent()) |event| {
            switch (self.state) {
                .normal => {
                    try self.handleNormalEvent(event, &loop);
                },
                .fuzzy, .new_file, .new_dir, .rename, .change_dir => {
                    try self.handleInputEvent(event);
                },
            }
        }

        try self.draw();

        var buffered = self.tty.bufferedWriter();
        try self.vx.render(buffered.writer().any());
        try buffered.flush();
    }
}

pub fn inputToSlice(self: *App) []const u8 {
    self.text_input.buf.cursor = self.text_input.buf.realLength();
    return self.text_input.sliceToCursor(&self.text_input_buf);
}

pub fn handleNormalEvent(self: *App, event: Event, loop: *vaxis.Loop(Event)) !void {
    switch (event) {
        .key_press => |key| {
            if ((key.codepoint == 'c' and key.mods.ctrl) or key.codepoint == 'q') {
                self.should_quit = true;
            }

            switch (key.codepoint) {
                '-', 'h', Key.left => {
                    self.text_input.clearAndFree();

                    if (self.directories.dir.openDir("../", .{ .iterate = true })) |dir| {
                        self.directories.dir = dir;

                        self.directories.clearEntries();
                        const fuzzy = self.inputToSlice();
                        self.directories.populateEntries(fuzzy) catch |err| {
                            switch (err) {
                                error.AccessDenied => try self.notification.writeErr(.PermissionDenied),
                                else => try self.notification.writeErr(.UnknownError),
                            }
                        };

                        if (self.directories.history.pop()) |history| {
                            self.directories.entries.selected = history.selected;
                            self.directories.entries.offset = history.offset;
                        }
                    } else |err| {
                        switch (err) {
                            error.AccessDenied => try self.notification.writeErr(.PermissionDenied),
                            else => try self.notification.writeErr(.UnknownError),
                        }
                    }
                },
                Key.enter, 'l', Key.right => {
                    const entry = self.directories.getSelected() catch return;

                    switch (entry.kind) {
                        .directory => {
                            self.text_input.clearAndFree();

                            if (self.directories.dir.openDir(entry.name, .{ .iterate = true })) |dir| {
                                self.directories.dir = dir;

                                _ = self.directories.history.push(.{
                                    .selected = self.directories.entries.selected,
                                    .offset = self.directories.entries.offset,
                                });

                                self.directories.clearEntries();
                                const fuzzy = self.inputToSlice();
                                self.directories.populateEntries(fuzzy) catch |err| {
                                    switch (err) {
                                        error.AccessDenied => try self.notification.writeErr(.PermissionDenied),
                                        else => try self.notification.writeErr(.UnknownError),
                                    }
                                };
                            } else |err| {
                                switch (err) {
                                    error.AccessDenied => try self.notification.writeErr(.PermissionDenied),
                                    else => try self.notification.writeErr(.UnknownError),
                                }
                            }
                        },
                        .file => {
                            if (environment.getEditor()) |editor| {
                                try self.vx.exitAltScreen(self.tty.anyWriter());
                                try self.vx.resetState(self.tty.anyWriter());
                                loop.stop();

                                environment.openFile(self.alloc, self.directories.dir, entry.name, editor) catch {
                                    try self.notification.writeErr(.UnableToOpenFile);
                                };

                                try loop.start();
                                try self.vx.enterAltScreen(self.tty.anyWriter());
                                try self.vx.enableDetectedFeatures(self.tty.anyWriter());
                                self.vx.queueRefresh();
                            } else {
                                try self.notification.writeErr(.EditorNotSet);
                            }
                        },
                        else => {},
                    }
                },
                'j', Key.down => {
                    self.directories.entries.next(self.last_known_height);
                },
                'k', Key.up => {
                    self.directories.entries.previous(self.last_known_height);
                },
                'G' => {
                    self.directories.entries.selectLast(self.last_known_height);
                },
                'g' => self.directories.entries.selectFirst(),
                'D' => {
                    const entry = self.directories.getSelected() catch {
                        try self.notification.writeErr(.UnableToDelete);
                        return;
                    };

                    var old_path_buf: [std.fs.max_path_bytes]u8 = undefined;
                    const old_path = try self.alloc.dupe(u8, try self.directories.dir.realpath(entry.name, &old_path_buf));
                    var tmp_path_buf: [std.fs.max_path_bytes]u8 = undefined;
                    const tmp_path = try self.alloc.dupe(u8, try std.fmt.bufPrint(&tmp_path_buf, "/tmp/{s}-{s}", .{ entry.name, zuid.new.v4().toString() }));

                    if (self.directories.dir.rename(entry.name, tmp_path)) {
                        if (self.actions.push(.{
                            .delete = .{ .old = old_path, .new = tmp_path },
                        })) |prev_elem| {
                            self.alloc.free(prev_elem.delete.old);
                            self.alloc.free(prev_elem.delete.new);
                        }

                        try self.notification.writeInfo(.Deleted);
                        self.directories.removeSelected();
                    } else |err| {
                        switch (err) {
                            error.RenameAcrossMountPoints => try self.notification.writeErr(.UnableToDeleteAcrossMountPoints),
                            else => try self.notification.writeErr(.UnableToDelete),
                        }
                        self.alloc.free(old_path);
                        self.alloc.free(tmp_path);
                    }
                },
                'd' => {
                    self.text_input.clearAndFree();
                    self.directories.clearEntries();
                    self.directories.populateEntries("") catch |err| {
                        switch (err) {
                            error.AccessDenied => try self.notification.writeErr(.PermissionDenied),
                            else => try self.notification.writeErr(.UnknownError),
                        }
                    };
                    self.state = .new_dir;
                },
                '%' => {
                    self.text_input.clearAndFree();
                    self.directories.clearEntries();
                    self.directories.populateEntries("") catch |err| {
                        switch (err) {
                            error.AccessDenied => try self.notification.writeErr(.PermissionDenied),
                            else => try self.notification.writeErr(.UnknownError),
                        }
                    };
                    self.state = .new_file;
                },
                'u' => {
                    if (self.actions.pop()) |action| {
                        const selected = self.directories.entries.selected;

                        switch (action) {
                            .delete => |a| {
                                // TODO: Will overwrite an item if it has the same name.
                                if (self.directories.dir.rename(a.new, a.old)) {
                                    defer self.alloc.free(a.new);
                                    defer self.alloc.free(a.old);

                                    self.directories.clearEntries();
                                    const fuzzy = self.inputToSlice();
                                    self.directories.populateEntries(fuzzy) catch |err| {
                                        switch (err) {
                                            error.AccessDenied => try self.notification.writeErr(.PermissionDenied),
                                            else => try self.notification.writeErr(.UnknownError),
                                        }
                                    };
                                    try self.notification.writeInfo(.RestoredDelete);
                                } else |_| {
                                    try self.notification.writeErr(.UnableToUndo);
                                }
                            },
                            .rename => |a| {
                                // TODO: Will overwrite an item if it has the same name.
                                if (self.directories.dir.rename(a.new, a.old)) {
                                    defer self.alloc.free(a.new);
                                    defer self.alloc.free(a.old);

                                    self.directories.clearEntries();
                                    const fuzzy = self.inputToSlice();
                                    self.directories.populateEntries(fuzzy) catch |err| {
                                        switch (err) {
                                            error.AccessDenied => try self.notification.writeErr(.PermissionDenied),
                                            else => try self.notification.writeErr(.UnknownError),
                                        }
                                    };
                                    try self.notification.writeInfo(.RestoredRename);
                                } else |_| {
                                    try self.notification.writeErr(.UnableToUndo);
                                }
                            },
                        }

                        self.directories.entries.selected = selected;
                    } else {
                        try self.notification.writeInfo(.EmptyUndo);
                    }
                },
                '/' => self.state = .fuzzy,
                'R' => {
                    self.state = .rename;

                    const entry = self.directories.getSelected() catch {
                        self.state = .normal;
                        try self.notification.writeErr(.UnableToRename);
                        return;
                    };

                    self.text_input.insertSliceAtCursor(entry.name) catch {
                        self.state = .normal;
                        try self.notification.writeErr(.UnableToRename);
                        return;
                    };
                },
                'c' => self.state = .change_dir,
                else => {},
            }
        },
        .winsize => |ws| try self.vx.resize(self.alloc, self.tty.anyWriter(), ws),
    }
}

pub fn handleInputEvent(self: *App, event: Event) !void {
    switch (event) {
        .key_press => |key| {
            if ((key.codepoint == 'c' and key.mods.ctrl)) {
                self.should_quit = true;
                return;
            }

            switch (key.codepoint) {
                Key.escape => {
                    switch (self.state) {
                        .fuzzy => {
                            self.directories.clearEntries();
                            self.directories.populateEntries("") catch |err| {
                                switch (err) {
                                    error.AccessDenied => try self.notification.writeErr(.PermissionDenied),
                                    else => try self.notification.writeErr(.UnknownError),
                                }
                            };
                        },
                        else => {},
                    }

                    self.text_input.clearAndFree();
                    self.state = .normal;
                },
                Key.enter => {
                    const selected = self.directories.entries.selected;
                    switch (self.state) {
                        .new_dir => {
                            const dir = self.inputToSlice();
                            if (self.directories.dir.makeDir(dir)) {
                                try self.notification.writeInfo(.CreatedFolder);

                                self.directories.clearEntries();
                                self.directories.populateEntries("") catch |err| {
                                    switch (err) {
                                        error.AccessDenied => try self.notification.writeErr(.PermissionDenied),
                                        else => try self.notification.writeErr(.UnknownError),
                                    }
                                };
                            } else |err| {
                                switch (err) {
                                    error.AccessDenied => try self.notification.writeErr(.PermissionDenied),
                                    error.PathAlreadyExists => try self.notification.writeErr(.ItemAlreadyExists),
                                    else => try self.notification.writeErr(.UnknownError),
                                }
                            }
                            self.text_input.clearAndFree();
                        },
                        .new_file => {
                            const file = self.inputToSlice();
                            if (environment.fileExists(self.directories.dir, file)) {
                                try self.notification.writeErr(.ItemAlreadyExists);
                            } else {
                                if (self.directories.dir.createFile(file, .{})) |f| {
                                    f.close();

                                    try self.notification.writeInfo(.CreatedFile);

                                    self.directories.clearEntries();
                                    self.directories.populateEntries("") catch |err| {
                                        switch (err) {
                                            error.AccessDenied => try self.notification.writeErr(.PermissionDenied),
                                            else => try self.notification.writeErr(.UnknownError),
                                        }
                                    };
                                } else |err| {
                                    switch (err) {
                                        error.AccessDenied => try self.notification.writeErr(.PermissionDenied),
                                        else => try self.notification.writeErr(.UnknownError),
                                    }
                                }
                            }
                            self.text_input.clearAndFree();
                        },
                        .rename => {
                            var dir_prefix_buf: [std.fs.max_path_bytes]u8 = undefined;
                            const dir_prefix = try self.directories.dir.realpath(".", &dir_prefix_buf);

                            const old = try self.directories.getSelected();
                            const new = self.inputToSlice();

                            if (environment.fileExists(self.directories.dir, new)) {
                                try self.notification.writeErr(.ItemAlreadyExists);
                            } else {
                                self.directories.dir.rename(old.name, new) catch |err| switch (err) {
                                    error.AccessDenied => try self.notification.writeErr(.PermissionDenied),
                                    error.PathAlreadyExists => try self.notification.writeErr(.ItemAlreadyExists),
                                    else => try self.notification.writeErr(.UnknownError),
                                };
                                if (self.actions.push(.{
                                    .rename = .{
                                        .old = try std.fs.path.join(self.alloc, &.{ dir_prefix, old.name }),
                                        .new = try std.fs.path.join(self.alloc, &.{ dir_prefix, new }),
                                    },
                                })) |prev_elem| {
                                    self.alloc.free(prev_elem.rename.old);
                                    self.alloc.free(prev_elem.rename.new);
                                }

                                try self.notification.writeInfo(.Renamed);

                                self.directories.clearEntries();
                                self.directories.populateEntries("") catch |err| {
                                    switch (err) {
                                        error.AccessDenied => try self.notification.writeErr(.PermissionDenied),
                                        else => try self.notification.writeErr(.UnknownError),
                                    }
                                };
                            }
                            self.text_input.clearAndFree();
                        },
                        .change_dir => {
                            const path = self.inputToSlice();
                            if (self.directories.dir.openDir(path, .{ .iterate = true })) |dir| {
                                self.directories.dir = dir;

                                try self.notification.writeInfo(.ChangedDir);

                                self.directories.clearEntries();
                                self.directories.populateEntries("") catch |err| {
                                    switch (err) {
                                        error.AccessDenied => try self.notification.writeErr(.PermissionDenied),
                                        else => try self.notification.writeErr(.UnknownError),
                                    }
                                };
                                self.directories.history.reset();
                            } else |err| {
                                switch (err) {
                                    error.AccessDenied => try self.notification.writeErr(.PermissionDenied),
                                    error.FileNotFound => try self.notification.writeErr(.IncorrectPath),
                                    error.NotDir => try self.notification.writeErr(.IncorrectPath),
                                    else => try self.notification.writeErr(.UnknownError),
                                }
                            }

                            self.text_input.clearAndFree();
                        },
                        else => {},
                    }
                    self.state = .normal;
                    self.directories.entries.selected = selected;
                },
                else => {
                    try self.text_input.update(.{ .key_press = key });

                    switch (self.state) {
                        .fuzzy => {
                            self.directories.clearEntries();
                            const fuzzy = self.inputToSlice();
                            self.directories.populateEntries(fuzzy) catch |err| {
                                switch (err) {
                                    error.AccessDenied => try self.notification.writeErr(.PermissionDenied),
                                    else => try self.notification.writeErr(.UnknownError),
                                }
                            };
                        },
                        else => {},
                    }
                },
            }
        },
        .winsize => |ws| try self.vx.resize(self.alloc, self.tty.anyWriter(), ws),
    }
}

pub fn draw(self: *App) !void {
    const win = self.vx.window();
    win.clear();

    const abs_file_path_bar = try self.drawAbsFilePath(win);
    const file_info_bar = try self.drawFileInfo(win);
    try self.drawDirList(win, abs_file_path_bar, file_info_bar);

    if (config.preview_file == true) {
        const file_name_bar = try self.drawFileName(win);
        try self.drawFilePreview(win, file_name_bar);
    }

    try self.drawUserInput(win);
    try self.drawNotification(win);
}

fn drawFileName(self: *App, win: vaxis.Window) !vaxis.Window {
    const file_name_bar = win.child(.{
        .x_off = win.width / 2,
        .y_off = 0,
        .width = win.width,
        .height = top_div,
    });

    if (self.directories.getSelected()) |entry| {
        const file_name = try std.fmt.bufPrint(&self.file_name_buf, "[{s}]", .{entry.name});
        _ = file_name_bar.print(&.{vaxis.Segment{
            .text = file_name,
            .style = config.styles.file_name,
        }}, .{});
    } else |_| {}

    return file_name_bar;
}

fn drawFilePreview(self: *App, win: vaxis.Window, file_name_win: vaxis.Window) !void {
    const preview_win = win.child(.{
        .x_off = win.width / 2,
        .y_off = top_div + 1,
        .width = win.width / 2,
        .height = win.height - (file_name_win.height + top_div + bottom_div),
    });

    // Populate preview bar
    if (self.directories.entries.len() > 0 and config.preview_file == true) {
        const entry = try self.directories.getSelected();

        @memcpy(&self.last_item_path_buf, &self.current_item_path_buf);
        self.last_item_path = self.last_item_path_buf[0..self.current_item_path.len];
        self.current_item_path = try std.fmt.bufPrint(&self.current_item_path_buf, "{s}/{s}", .{ try self.directories.fullPath("."), entry.name });

        switch (entry.kind) {
            .directory => {
                self.directories.clearChildEntries();
                if (self.directories.populateChildEntries(entry.name)) {
                    try self.directories.writeChildEntries(preview_win, config.styles.list_item);
                } else |err| {
                    switch (err) {
                        error.AccessDenied => try self.notification.writeErr(.PermissionDenied),
                        else => try self.notification.writeErr(.UnknownError),
                    }
                }
            },
            .file => file: {
                var file = self.directories.dir.openFile(entry.name, .{ .mode = .read_only }) catch |err| {
                    switch (err) {
                        error.AccessDenied => try self.notification.writeErr(.PermissionDenied),
                        else => try self.notification.writeErr(.UnknownError),
                    }

                    _ = preview_win.print(&.{.{ .text = "No preview available." }}, .{});

                    break :file;
                };
                defer file.close();
                const bytes = try file.readAll(&self.directories.file_contents);

                // Handle image.
                if (config.show_images == true) unsupported: {
                    var match = false;
                    inline for (@typeInfo(vaxis.zigimg.Image.Format).Enum.fields) |field| {
                        const entry_ext = std.mem.trimLeft(u8, std.fs.path.extension(entry.name), ".");
                        if (std.mem.eql(u8, entry_ext, field.name)) {
                            match = true;
                        }
                    }
                    if (!match) break :unsupported;

                    if (std.mem.eql(u8, self.last_item_path, self.current_item_path)) break :unsupported;

                    var image = vaxis.zigimg.Image.fromFilePath(self.alloc, self.current_item_path) catch {
                        break :unsupported;
                    };
                    defer image.deinit();
                    if (self.vx.transmitImage(self.alloc, self.tty.anyWriter(), &image, .rgba)) |img| {
                        self.image = img;
                    } else |_| {
                        if (self.image) |img| {
                            self.vx.freeImage(self.tty.anyWriter(), img.id);
                        }
                        self.image = null;
                        break :unsupported;
                    }

                    if (self.image) |img| {
                        try img.draw(preview_win, .{ .scale = .contain });
                    }

                    break :file;
                }

                // Handle pdf.
                if (std.mem.eql(u8, std.fs.path.extension(entry.name), ".pdf")) {
                    const output = std.process.Child.run(.{
                        .allocator = self.alloc,
                        .argv = &[_][]const u8{ "pdftotext", "-f", "0", "-l", "5", self.current_item_path, "-" },
                        .cwd_dir = self.directories.dir,
                    }) catch {
                        _ = preview_win.print(&.{.{
                            .text = "No preview available. Install pdftotext to get PDF previews.",
                        }}, .{});
                        break :file;
                    };
                    defer self.alloc.free(output.stderr);
                    defer self.alloc.free(output.stdout);

                    if (output.term.Exited != 0) {
                        _ = preview_win.print(&.{.{
                            .text = "No preview available. Install pdftotext to get PDF previews.",
                        }}, .{});
                        break :file;
                    }

                    if (self.directories.pdf_contents) |contents| self.alloc.free(contents);
                    self.directories.pdf_contents = try self.alloc.dupe(u8, output.stdout);

                    _ = preview_win.print(&.{.{ .text = self.directories.pdf_contents.? }}, .{});
                    break :file;
                }

                // Handle utf-8.
                if (std.unicode.utf8ValidateSlice(self.directories.file_contents[0..bytes])) {
                    _ = preview_win.print(&.{.{ .text = self.directories.file_contents[0..bytes] }}, .{});
                    break :file;
                }

                // Fallback to no preview.
                _ = preview_win.print(&.{.{ .text = "No preview available." }}, .{});
            },
            else => {
                _ = preview_win.print(&.{vaxis.Segment{ .text = self.current_item_path }}, .{});
            },
        }
    }
}

fn drawFileInfo(self: *App, win: vaxis.Window) !vaxis.Window {
    const file_info = try std.fmt.bufPrint(&self.file_info_buf, "{d}/{d} {s} {s}", .{
        self.directories.entries.selected + 1,
        self.directories.entries.len(),
        std.fs.path.extension(if (self.directories.getSelected()) |entry| entry.name else |_| ""),
        // TODO: This should be the file size, not dir.
        std.fmt.fmtIntSizeDec((try self.directories.dir.metadata()).size()),
    });

    const file_info_win = win.child(.{
        .x_off = 0,
        .y_off = win.height - bottom_div,
        .width = if (config.preview_file) win.width / 2 else win.width,
        .height = bottom_div,
    });
    file_info_win.fill(vaxis.Cell{ .style = config.styles.file_information });
    _ = file_info_win.print(&.{vaxis.Segment{ .text = file_info, .style = config.styles.file_information }}, .{});

    return file_info_win;
}

fn drawDirList(self: *App, win: vaxis.Window, abs_file_path: vaxis.Window, file_information: vaxis.Window) !void {
    const current_dir_list_win = win.child(.{
        .x_off = 0,
        .y_off = top_div + 1,
        .width = if (config.preview_file) win.width / 2 else win.width,
        .height = win.height - (abs_file_path.height + file_information.height + top_div + bottom_div),
    });
    try self.directories.writeEntries(current_dir_list_win, config.styles.selected_list_item, config.styles.list_item);

    self.last_known_height = current_dir_list_win.height;
}

fn drawAbsFilePath(self: *App, win: vaxis.Window) !vaxis.Window {
    const abs_file_path_bar = win.child(.{
        .x_off = 0,
        .y_off = 0,
        .width = win.width,
        .height = top_div,
    });
    _ = abs_file_path_bar.print(&.{vaxis.Segment{ .text = try self.directories.fullPath(".") }}, .{});

    return abs_file_path_bar;
}

fn drawUserInput(self: *App, win: vaxis.Window) !void {
    const user_input_win = win.child(.{
        .x_off = 0,
        .y_off = top_div,
        .width = win.width,
        .height = info_div,
    });

    switch (self.state) {
        .fuzzy, .new_file, .new_dir, .rename, .change_dir => {
            self.text_input.draw(user_input_win);
        },
        .normal => {
            if (self.text_input.buf.realLength() > 0) {
                self.text_input.draw(user_input_win);
            }

            win.hideCursor();
        },
    }
}

fn drawNotification(self: *App, win: vaxis.Window) !void {
    if (self.notification.len > 0) {
        if (std.time.timestamp() - self.notification.timer > Notification.notification_timeout) {
            self.notification.reset();
            return;
        }

        const notification_width_padding = 4;
        const notification_height_padding = 3;
        const notification_screen_pos_padding = 10;

        const max_notification_width = win.width / 4;
        const notification_width = self.notification.len + notification_width_padding;
        const abs_notification_width = if (notification_width > max_notification_width) max_notification_width else notification_width;
        const notification_height = try std.math.divCeil(usize, self.notification.len, abs_notification_width) + notification_height_padding;

        const notification_win = win.child(.{
            .x_off = @intCast(win.width - (abs_notification_width + notification_screen_pos_padding)),
            .y_off = top_div,
            .width = @intCast(abs_notification_width),
            .height = @intCast(notification_height),
            .border = .{ .where = .all },
        });

        notification_win.fill(.{ .style = config.styles.notification_box });
        _ = notification_win.printSegment(.{
            .text = self.notification.slice(),
            .style = switch (self.notification.style) {
                .info => config.styles.info_bar,
                .err => config.styles.error_bar,
            },
        }, .{ .wrap = .word });
    }
}
