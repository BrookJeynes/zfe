const std = @import("std");
const builtin = @import("builtin");

const Logger = @import("./log.zig").Logger;
const environment = @import("./environment.zig");
const Notification = @import("./notification.zig");
const config = &@import("./config.zig").config;
const List = @import("./list.zig").List;
const Directories = @import("./directories.zig");
const CircStack = @import("./circ_stack.zig").CircularStack;

const zuid = @import("zuid");

const vaxis = @import("vaxis");
const TextInput = @import("vaxis").widgets.TextInput;
const Cell = vaxis.Cell;
const Key = vaxis.Key;

pub const State = enum {
    normal,
    fuzzy,
    new_dir,
    new_file,
    change_dir,
    rename,
};

const InputReturnStatus = enum {
    exit,
    default,
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
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
};

const top_div = 1;
const info_div = 1;
const bottom_div = 1;
const actions_len = 100;

const App = @This();

alloc: std.mem.Allocator,
vx: vaxis.Vaxis = undefined,
tty: vaxis.Tty = undefined,
logger: Logger,
state: State = .normal,
actions: CircStack(Action, actions_len),

// Used to detect whether to re-render an image.
current_item_path_buf: [std.fs.max_path_bytes]u8 = undefined,
current_item_path: []u8 = "",
last_item_path_buf: [std.fs.max_path_bytes]u8 = undefined,
last_item_path: []u8 = "",

directories: Directories,
notification: Notification,

text_input: TextInput,
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
        .vx = vx,
        .tty = try vaxis.Tty.init(),
        .directories = try Directories.init(alloc),
        .logger = Logger{},
        .text_input = TextInput.init(alloc, &vx.unicode),
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
    self.logger.init();
    self.notification.init();

    try self.directories.populate_entries("");

    var loop: vaxis.Loop(Event) = .{ .vaxis = &self.vx, .tty = &self.tty };
    try loop.start();
    defer loop.stop();

    try self.vx.enterAltScreen(self.tty.anyWriter());
    try self.vx.queryTerminal(self.tty.anyWriter(), 1 * std.time.ns_per_s);
    self.vx.queueRefresh();

    while (true) {
        self.notification.reset();
        const event = loop.nextEvent();

        switch (self.state) {
            .normal => {
                switch (try self.handle_normal_event(event, &loop)) {
                    .exit => return,
                    .default => {},
                }
            },
            .fuzzy, .new_file, .new_dir, .rename, .change_dir => {
                switch (try self.handle_input_event(event)) {
                    .exit => return,
                    .default => {},
                }
            },
        }

        try self.draw();
    }
}

pub fn inputToSlice(self: *App) []const u8 {
    self.text_input.buf.cursor = self.text_input.buf.realLength();
    return self.text_input.sliceToCursor(&self.text_input_buf);
}

pub fn handle_normal_event(self: *App, event: Event, loop: *vaxis.Loop(Event)) !InputReturnStatus {
    switch (event) {
        .key_press => |key| {
            if ((key.codepoint == 'c' and key.mods.ctrl) or key.codepoint == 'q') {
                return .exit;
            }

            switch (key.codepoint) {
                '-', 'h', Key.left => {
                    self.text_input.clearAndFree();

                    if (self.directories.dir.openDir("../", .{ .iterate = true })) |dir| {
                        self.directories.dir = dir;

                        self.directories.cleanup();
                        const fuzzy = self.inputToSlice();
                        self.directories.populate_entries(fuzzy) catch |err| {
                            switch (err) {
                                error.AccessDenied => try self.notification.write_err(.PermissionDenied),
                                else => try self.notification.write_err(.UnknownError),
                            }
                        };

                        if (self.directories.history.pop()) |history| {
                            self.directories.entries.selected = history.selected;
                            self.directories.entries.offset = history.offset;
                        }
                    } else |err| {
                        switch (err) {
                            error.AccessDenied => try self.notification.write_err(.PermissionDenied),
                            else => try self.notification.write_err(.UnknownError),
                        }
                    }
                },
                Key.enter, 'l', Key.right => {
                    const entry = try self.directories.get_selected();

                    switch (entry.kind) {
                        .directory => {
                            self.text_input.clearAndFree();

                            if (self.directories.dir.openDir(entry.name, .{ .iterate = true })) |dir| {
                                self.directories.dir = dir;

                                _ = self.directories.history.push(.{
                                    .selected = self.directories.entries.selected,
                                    .offset = self.directories.entries.offset,
                                });

                                self.directories.cleanup();
                                const fuzzy = self.inputToSlice();
                                self.directories.populate_entries(fuzzy) catch |err| {
                                    switch (err) {
                                        error.AccessDenied => try self.notification.write_err(.PermissionDenied),
                                        else => try self.notification.write_err(.UnknownError),
                                    }
                                };
                            } else |err| {
                                switch (err) {
                                    error.AccessDenied => try self.notification.write_err(.PermissionDenied),
                                    else => try self.notification.write_err(.UnknownError),
                                }
                            }
                        },
                        .file => {
                            if (environment.get_editor()) |editor| {
                                try self.vx.exitAltScreen(self.tty.anyWriter());
                                try self.vx.resetState(self.tty.anyWriter());
                                loop.stop();

                                environment.open_file(self.alloc, self.directories.dir, entry.name, editor) catch {
                                    try self.notification.write_err(.UnableToOpenFile);
                                };

                                try loop.start();
                                try self.vx.enterAltScreen(self.tty.anyWriter());
                                try self.vx.enableDetectedFeatures(self.tty.anyWriter());
                                self.vx.queueRefresh();
                            } else {
                                try self.notification.write_err(.EditorNotSet);
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
                    self.directories.entries.select_last(self.last_known_height);
                },
                'g' => {
                    self.directories.entries.select_first();
                },
                'D' => {
                    const entry = self.directories.get_selected() catch {
                        try self.notification.write_err(.UnableToDeleteItem);
                        return .default;
                    };

                    var old_path_buf: [std.fs.max_path_bytes]u8 = undefined;
                    const old_path = try self.alloc.dupe(u8, try self.directories.dir.realpath(entry.name, &old_path_buf));
                    var tmp_path_buf: [std.fs.max_path_bytes]u8 = undefined;
                    const tmp_path = try self.alloc.dupe(u8, try std.fmt.bufPrint(&tmp_path_buf, "/tmp/{s}-{s}", .{ entry.name, zuid.new.v4().toString() }));

                    try self.notification.write("Deleting item...", .info);
                    if (self.directories.dir.rename(entry.name, tmp_path)) {
                        if (self.actions.push(.{
                            .delete = .{ .old = old_path, .new = tmp_path },
                        })) |prev_elem| {
                            self.alloc.free(prev_elem.delete.old);
                            self.alloc.free(prev_elem.delete.new);
                        }
                        try self.notification.write("Deleted item.", .info);

                        self.directories.remove_selected();
                    } else |err| {
                        switch (err) {
                            error.RenameAcrossMountPoints => try self.notification.write_err(.UnableToDeleteAcrossMountPoints),
                            else => try self.notification.write_err(.UnableToDeleteItem),
                        }
                        self.alloc.free(old_path);
                        self.alloc.free(tmp_path);
                    }
                },
                'd' => {
                    self.text_input.clearAndFree();
                    self.directories.cleanup();
                    self.directories.populate_entries("") catch |err| {
                        switch (err) {
                            error.AccessDenied => try self.notification.write_err(.PermissionDenied),
                            else => try self.notification.write_err(.UnknownError),
                        }
                    };
                    self.state = .new_dir;
                },
                '%' => {
                    self.text_input.clearAndFree();
                    self.directories.cleanup();
                    self.directories.populate_entries("") catch |err| {
                        switch (err) {
                            error.AccessDenied => try self.notification.write_err(.PermissionDenied),
                            else => try self.notification.write_err(.UnknownError),
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

                                    self.directories.cleanup();
                                    const fuzzy = self.inputToSlice();
                                    self.directories.populate_entries(fuzzy) catch |err| {
                                        switch (err) {
                                            error.AccessDenied => try self.notification.write_err(.PermissionDenied),
                                            else => try self.notification.write_err(.UnknownError),
                                        }
                                    };
                                    try self.notification.write("Restored deleted item.", .info);
                                } else |_| {
                                    try self.notification.write_err(.UnableToUndo);
                                }
                            },
                            .rename => |a| {
                                // TODO: Will overwrite an item if it has the same name.
                                if (self.directories.dir.rename(a.new, a.old)) {
                                    defer self.alloc.free(a.new);
                                    defer self.alloc.free(a.old);

                                    self.directories.cleanup();
                                    const fuzzy = self.inputToSlice();
                                    self.directories.populate_entries(fuzzy) catch |err| {
                                        switch (err) {
                                            error.AccessDenied => try self.notification.write_err(.PermissionDenied),
                                            else => try self.notification.write_err(.UnknownError),
                                        }
                                    };
                                    try self.notification.write("Restored previous item name.", .info);
                                } else |_| {
                                    try self.notification.write_err(.UnableToUndo);
                                }
                            },
                        }

                        self.directories.entries.selected = selected;
                    } else {
                        try self.notification.write("Nothing to undo.", .info);
                    }
                },
                '/' => {
                    self.state = .fuzzy;
                },
                'R' => {
                    self.state = .rename;

                    const entry = try self.directories.get_selected();
                    self.text_input.insertSliceAtCursor(entry.name) catch {
                        self.state = .normal;
                        try self.notification.write_err(.UnableToRename);
                    };
                },
                'c' => {
                    self.state = .change_dir;
                },
                else => {
                    // log.debug("codepoint: {d}\n", .{key.codepoint});
                },
            }
        },
        .winsize => |ws| {
            try self.vx.resize(self.alloc, self.tty.anyWriter(), ws);
        },
    }

    return .default;
}

pub fn handle_input_event(self: *App, event: Event) !InputReturnStatus {
    switch (event) {
        .key_press => |key| {
            if ((key.codepoint == 'c' and key.mods.ctrl)) {
                return .exit;
            }

            switch (key.codepoint) {
                Key.escape => {
                    switch (self.state) {
                        .fuzzy => {
                            self.directories.cleanup();
                            self.directories.populate_entries("") catch |err| {
                                switch (err) {
                                    error.AccessDenied => try self.notification.write_err(.PermissionDenied),
                                    else => try self.notification.write_err(.UnknownError),
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
                                self.directories.cleanup();
                                self.directories.populate_entries("") catch |err| {
                                    switch (err) {
                                        error.AccessDenied => try self.notification.write_err(.PermissionDenied),
                                        else => try self.notification.write_err(.UnknownError),
                                    }
                                };
                            } else |err| {
                                switch (err) {
                                    error.AccessDenied => try self.notification.write_err(.PermissionDenied),
                                    error.PathAlreadyExists => try self.notification.write_err(.ItemAlreadyExists),
                                    else => try self.notification.write_err(.UnknownError),
                                }
                            }
                            self.text_input.clearAndFree();
                        },
                        .new_file => {
                            const file = self.inputToSlice();
                            if (environment.file_exists(self.directories.dir, file)) {
                                try self.notification.write_err(.ItemAlreadyExists);
                            } else {
                                if (self.directories.dir.createFile(file, .{})) |f| {
                                    f.close();
                                    self.directories.cleanup();
                                    self.directories.populate_entries("") catch |err| {
                                        switch (err) {
                                            error.AccessDenied => try self.notification.write_err(.PermissionDenied),
                                            else => try self.notification.write_err(.UnknownError),
                                        }
                                    };
                                } else |err| {
                                    switch (err) {
                                        error.AccessDenied => try self.notification.write_err(.PermissionDenied),
                                        else => try self.notification.write_err(.UnknownError),
                                    }
                                }
                            }
                            self.text_input.clearAndFree();
                        },
                        .rename => {
                            var dir_prefix_buf: [std.fs.max_path_bytes]u8 = undefined;
                            const dir_prefix = try self.directories.dir.realpath(".", &dir_prefix_buf);

                            const old = try self.directories.get_selected();
                            const new = self.inputToSlice();

                            if (environment.file_exists(self.directories.dir, new)) {
                                try self.notification.write_err(.ItemAlreadyExists);
                            } else {
                                self.directories.dir.rename(old.name, new) catch |err| switch (err) {
                                    error.AccessDenied => try self.notification.write_err(.PermissionDenied),
                                    error.PathAlreadyExists => try self.notification.write_err(.ItemAlreadyExists),
                                    else => try self.notification.write_err(.UnknownError),
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

                                self.directories.cleanup();
                                self.directories.populate_entries("") catch |err| {
                                    switch (err) {
                                        error.AccessDenied => try self.notification.write_err(.PermissionDenied),
                                        else => try self.notification.write_err(.UnknownError),
                                    }
                                };
                            }
                            self.text_input.clearAndFree();
                        },
                        .change_dir => {
                            const path = self.inputToSlice();
                            if (self.directories.dir.openDir(path, .{ .iterate = true })) |dir| {
                                self.directories.dir = dir;

                                self.directories.cleanup();
                                self.directories.populate_entries("") catch |err| {
                                    switch (err) {
                                        error.AccessDenied => try self.notification.write_err(.PermissionDenied),
                                        else => try self.notification.write_err(.UnknownError),
                                    }
                                };
                                self.directories.history.reset();
                            } else |err| {
                                switch (err) {
                                    error.AccessDenied => try self.notification.write_err(.PermissionDenied),
                                    error.FileNotFound => try self.notification.write_err(.IncorrectPath),
                                    error.NotDir => try self.notification.write_err(.IncorrectPath),
                                    else => try self.notification.write_err(.UnknownError),
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
                            self.directories.cleanup();
                            const fuzzy = self.inputToSlice();
                            self.directories.populate_entries(fuzzy) catch |err| {
                                switch (err) {
                                    error.AccessDenied => try self.notification.write_err(.PermissionDenied),
                                    else => try self.notification.write_err(.UnknownError),
                                }
                            };
                        },
                        else => {},
                    }
                },
            }
        },
        .winsize => |ws| {
            try self.vx.resize(self.alloc, self.tty.anyWriter(), ws);
        },
    }

    return .default;
}

pub fn draw(self: *App) !void {
    const win = self.vx.window();
    win.clear();

    const abs_file_path_bar = try self.draw_abs_file_path(win);
    var file_info_buf: [1024]u8 = undefined;
    const file_info_bar = try self.draw_file_info(win, &file_info_buf);
    try self.draw_current_dir_list(win, abs_file_path_bar, file_info_bar);

    if (config.preview_file == true) {
        var file_name_buf: [std.fs.MAX_NAME_BYTES + 2]u8 = undefined;
        const file_name_bar = try self.draw_file_name(win, &file_name_buf);
        try self.draw_preview(win, file_name_bar);
    }

    try self.draw_info(win);

    try self.vx.render(self.tty.anyWriter());
}

fn draw_file_name(self: *App, win: vaxis.Window, buf: []u8) !vaxis.Window {
    const file_name_bar = win.child(.{
        .x_off = win.width / 2,
        .y_off = 0,
        .width = .{ .limit = win.width },
        .height = .{ .limit = top_div },
    });

    if (self.directories.get_selected()) |entry| {
        const file_name = try std.fmt.bufPrint(buf, "[{s}]", .{entry.name});
        _ = try file_name_bar.print(&.{vaxis.Segment{
            .text = file_name,
            .style = config.styles.file_name,
        }}, .{});
    } else |_| {}

    return file_name_bar;
}

fn draw_preview(self: *App, win: vaxis.Window, file_name_win: vaxis.Window) !void {
    const preview_win = win.child(.{
        .x_off = win.width / 2,
        .y_off = top_div + 1,
        .width = .{ .limit = win.width / 2 },
        .height = .{ .limit = win.height - (file_name_win.height + top_div + bottom_div) },
    });

    // Populate preview bar
    if (self.directories.entries.len() > 0 and config.preview_file == true) {
        const entry = try self.directories.get_selected();

        @memcpy(&self.last_item_path_buf, &self.current_item_path_buf);
        self.last_item_path = self.last_item_path_buf[0..self.current_item_path.len];
        self.current_item_path = try std.fmt.bufPrint(&self.current_item_path_buf, "{s}/{s}", .{ try self.directories.full_path("."), entry.name });

        switch (entry.kind) {
            .directory => {
                self.directories.cleanup_sub();
                if (self.directories.populate_sub_entries(entry.name)) {
                    try self.directories.write_sub_entries(preview_win, config.styles.list_item);
                } else |err| {
                    switch (err) {
                        error.AccessDenied => try self.notification.write_err(.PermissionDenied),
                        else => try self.notification.write_err(.UnknownError),
                    }
                }
            },
            .file => file: {
                var file = self.directories.dir.openFile(entry.name, .{ .mode = .read_only }) catch |err| {
                    switch (err) {
                        error.AccessDenied => try self.notification.write_err(.PermissionDenied),
                        else => try self.notification.write_err(.UnknownError),
                    }

                    _ = try preview_win.print(&.{
                        .{
                            .text = "No preview available.",
                        },
                    }, .{});

                    break :file;
                };
                defer file.close();
                const bytes = try file.readAll(&self.directories.file_contents);

                // Handle image.
                if (config.show_images == true) unsupported_terminal: {
                    if (!std.mem.eql(u8, self.last_item_path, self.current_item_path)) {
                        var image = vaxis.zigimg.Image.fromFilePath(self.alloc, self.current_item_path) catch {
                            break :unsupported_terminal;
                        };
                        defer image.deinit();
                        if (self.vx.transmitImage(self.alloc, self.tty.anyWriter(), &image, .rgba)) |img| {
                            self.image = img;
                        } else |_| {
                            if (self.image) |img| {
                                self.vx.freeImage(self.tty.anyWriter(), img.id);
                            }
                            self.image = null;
                            break :unsupported_terminal;
                        }

                        if (self.image) |img| {
                            try img.draw(preview_win, .{ .scale = .contain });
                        }
                    }

                    break :file;
                }

                // Handle pdf.
                if (std.mem.eql(u8, std.fs.path.extension(entry.name), ".pdf")) {
                    var child = std.process.Child.init(&.{ "pdftotext", self.current_item_path, "-" }, self.alloc);
                    child.stdout_behavior = .Pipe;
                    child.stderr_behavior = .Close;
                    child.stdin_behavior = .Close;
                    try child.spawn();

                    const pdf_bytes = if (child.stdout) |stdout|
                        try stdout.reader().read(&self.directories.pdf_contents)
                    else
                        0;

                    const term = try child.wait();
                    if (term.Exited != 0) {
                        _ = try preview_win.print(&.{
                            .{
                                .text = "No preview available. Install pdftotext to get PDF previews.",
                            },
                        }, .{});
                        break :file;
                    }

                    _ = try preview_win.print(&.{
                        .{
                            .text = self.directories.pdf_contents[0..pdf_bytes],
                        },
                    }, .{});
                    break :file;
                }

                // Handle utf-8.
                if (std.unicode.utf8ValidateSlice(self.directories.file_contents[0..bytes])) {
                    _ = try preview_win.print(&.{
                        .{
                            .text = self.directories.file_contents[0..bytes],
                        },
                    }, .{});
                    break :file;
                }

                // Fallback to no preview.
                _ = try preview_win.print(&.{
                    .{
                        .text = "No preview available.",
                    },
                }, .{});
            },
            else => {
                _ = try preview_win.print(&.{vaxis.Segment{ .text = self.current_item_path }}, .{});
            },
        }
    }
}

fn draw_file_info(self: *App, win: vaxis.Window, file_info_buf: []u8) !vaxis.Window {
    const file_info = try std.fmt.bufPrint(file_info_buf, "{d}/{d} {s} {s}", .{
        self.directories.entries.selected + 1,
        self.directories.entries.len(),
        std.fs.path.extension(if (self.directories.get_selected()) |entry| entry.name else |_| ""),
        std.fmt.fmtIntSizeDec((try self.directories.dir.metadata()).size()),
    });

    const file_info_win = win.child(.{
        .x_off = 0,
        .y_off = win.height - bottom_div,
        .width = if (config.preview_file) .{ .limit = win.width / 2 } else .{ .limit = win.width },
        .height = .{ .limit = bottom_div },
    });
    file_info_win.fill(vaxis.Cell{ .style = config.styles.file_information });
    _ = try file_info_win.print(&.{vaxis.Segment{ .text = file_info, .style = config.styles.file_information }}, .{});

    return file_info_win;
}

fn draw_current_dir_list(self: *App, win: vaxis.Window, abs_file_path: vaxis.Window, file_information: vaxis.Window) !void {
    const current_dir_list_win = win.child(.{
        .x_off = 0,
        .y_off = top_div + 1,
        .width = if (config.preview_file) .{ .limit = win.width / 2 } else .{ .limit = win.width },
        .height = .{ .limit = win.height - (abs_file_path.height + file_information.height + top_div + bottom_div) },
    });
    try self.directories.write_entries(current_dir_list_win, config.styles.selected_list_item, config.styles.list_item);

    self.last_known_height = current_dir_list_win.height;
}

fn draw_abs_file_path(self: *App, win: vaxis.Window) !vaxis.Window {
    const abs_file_path_bar = win.child(.{
        .x_off = 0,
        .y_off = 0,
        .width = .{ .limit = win.width },
        .height = .{ .limit = top_div },
    });
    _ = try abs_file_path_bar.print(&.{vaxis.Segment{ .text = try self.directories.full_path(".") }}, .{});

    return abs_file_path_bar;
}

fn draw_info(self: *App, win: vaxis.Window) !void {
    const info_win = win.child(.{
        .x_off = 0,
        .y_off = top_div,
        .width = .{ .limit = win.width },
        .height = .{ .limit = info_div },
    });

    // Display info box.
    if (self.notification.len > 0) {
        if (self.text_input.buf.realLength() > 0) {
            self.text_input.clearAndFree();
        }

        _ = try info_win.print(&.{
            .{
                .text = self.notification.slice(),
                .style = switch (self.notification.style) {
                    .info => config.styles.info_bar,
                    .err => config.styles.error_bar,
                },
            },
        }, .{});
    }

    // Display user input box.
    switch (self.state) {
        .fuzzy, .new_file, .new_dir, .rename, .change_dir => {
            self.notification.reset();
            self.text_input.draw(info_win);
        },
        .normal => {
            if (self.text_input.buf.realLength() > 0) {
                self.text_input.draw(info_win);
            }

            win.hideCursor();
        },
    }
}
