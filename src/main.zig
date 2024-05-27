const std = @import("std");
const builtin = @import("builtin");

const log = &@import("./log.zig").log;
const environment = @import("./environment.zig");
const config = &@import("./config.zig").config;
const List = @import("./list.zig").List;
const View = @import("./view.zig");

const zuid = @import("zuid");

const vaxis = @import("vaxis");
const TextInput = @import("vaxis").widgets.TextInput;
const Cell = vaxis.Cell;
const Key = vaxis.Key;

const State = enum {
    normal,
    fuzzy,
    new_dir,
    new_file,
};

const InfoBar = struct {
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
};

const Action = union(enum) {
    delete: struct {
        /// Allocated.
        old_path: []const u8,
        /// Allocated.
        tmp_path: []const u8,
    },
};

const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
};

var vx: vaxis.Vaxis = undefined;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var view = try View.init(alloc);
    defer view.deinit();

    var file_metadata = try view.dir.metadata();

    log.init();

    config.parse(alloc) catch |err| switch (err) {
        error.ConfigNotFound => {},
        error.MissingConfigHomeEnvironmentVariable => {
            log.err("Could not read config due to $HOME or $XDG_CONFIG_HOME not being set.", .{});
            return;
        },
        error.SyntaxError => {
            log.err("Could not read config due to a syntax error.", .{});
            return;
        },
        else => {
            log.err("Could not read config due to an unknown error.", .{});
            return;
        },
    };

    // TODO: Figure out size.
    var file_buf: [4096]u8 = undefined;

    var current_item_path: []u8 = "";
    var last_item_path: []u8 = "";
    var image: ?vaxis.Image = null;
    var path: [std.fs.max_path_bytes]u8 = undefined;
    var last_path: [std.fs.max_path_bytes]u8 = undefined;

    try view.populate_entries("");

    vx = try vaxis.init(alloc, .{ .kitty_keyboard_flags = .{
        .report_text = false,
        .disambiguate = false,
        .report_events = false,
        .report_alternate_keys = false,
        .report_all_as_ctl_seqs = false,
    } });
    defer vx.deinit(alloc);

    var loop: vaxis.Loop(Event) = .{ .vaxis = &vx };
    try loop.run();
    defer loop.stop();

    try vx.enterAltScreen();
    try vx.queryTerminal();

    var text_input = TextInput.init(alloc, &vx.unicode);
    defer text_input.deinit();

    var info = InfoBar{};
    info.init();

    var actions = std.ArrayList(Action).init(alloc);
    defer actions.deinit();

    var state = State.normal;
    var last_pressed: ?vaxis.Key = null;
    var last_known_height: usize = vx.window().height;
    var input_buf: [std.fs.max_path_bytes]u8 = undefined;
    while (true) {
        info.reset();
        const event = loop.nextEvent();

        switch (event) {
            .winsize => |ws| {
                try vx.resize(alloc, ws);
            },
            else => {},
        }
        const win = vx.window();
        win.clear();

        const top_div = 1;
        const info_div = 1;
        const bottom_div = 1;

        const info_bar = win.child(.{
            .x_off = 0,
            .y_off = top_div,
            .width = .{ .limit = win.width },
            .height = .{ .limit = info_div },
        });

        switch (state) {
            .normal => {
                switch (event) {
                    .key_press => |key| {
                        if ((key.codepoint == 'c' and key.mods.ctrl) or key.codepoint == 'q') {
                            break;
                        }

                        switch (key.codepoint) {
                            '-', 'h', Key.left => {
                                text_input.clearAndFree();

                                if (view.dir.openDir("../", .{ .iterate = true })) |dir| {
                                    view.dir = dir;

                                    view.cleanup();
                                    const fuzzy = text_input.sliceToCursor(&input_buf);
                                    view.populate_entries(fuzzy) catch |err| {
                                        switch (err) {
                                            error.AccessDenied => try info.write_err(.PermissionDenied),
                                            else => try info.write_err(.UnknownError),
                                        }
                                    };
                                } else |err| {
                                    switch (err) {
                                        error.AccessDenied => try info.write_err(.PermissionDenied),
                                        else => try info.write_err(.UnknownError),
                                    }
                                }
                                last_pressed = null;
                            },
                            Key.enter, 'l', Key.right => {
                                const entry = view.entries.get(view.entries.selected) catch continue;

                                switch (entry.kind) {
                                    .directory => {
                                        text_input.clearAndFree();

                                        if (view.dir.openDir(entry.name, .{ .iterate = true })) |dir| {
                                            view.dir = dir;

                                            view.cleanup();
                                            const fuzzy = text_input.sliceToCursor(&input_buf);
                                            view.populate_entries(fuzzy) catch |err| {
                                                switch (err) {
                                                    error.AccessDenied => try info.write_err(.PermissionDenied),
                                                    else => try info.write_err(.UnknownError),
                                                }
                                            };
                                        } else |err| {
                                            switch (err) {
                                                error.AccessDenied => try info.write_err(.PermissionDenied),
                                                else => try info.write_err(.UnknownError),
                                            }
                                        }
                                        last_pressed = null;
                                    },
                                    .file => {
                                        if (environment.get_editor()) |editor| {
                                            try vx.exitAltScreen();
                                            loop.stop();

                                            environment.open_file(alloc, view.dir, entry.name, editor) catch {
                                                try info.write_err(.UnableToOpenFile);
                                            };

                                            try loop.run();
                                            try vx.enterAltScreen();
                                            vx.queueRefresh();
                                        } else {
                                            try info.write_err(.EditorNotSet);
                                        }
                                    },
                                    else => {},
                                }
                            },
                            'j', Key.down => {
                                view.entries.next(last_known_height);
                                last_pressed = null;
                            },
                            'k', Key.up => {
                                view.entries.previous(last_known_height);
                                last_pressed = null;
                            },
                            'G' => {
                                view.entries.select_last(last_known_height);
                                last_pressed = null;
                            },
                            'g' => {
                                if (last_pressed) |k| {
                                    if (k.codepoint == 'g') {
                                        view.entries.select_first();
                                        last_pressed = null;
                                    }
                                    last_pressed = null;
                                } else {
                                    last_pressed = key;
                                }
                            },
                            'D' => {
                                const entry = view.entries.get(view.entries.selected) catch continue;

                                var old_path_buf: [std.fs.max_path_bytes]u8 = undefined;
                                const old_path = try alloc.dupe(u8, try view.dir.realpath(entry.name, &old_path_buf));
                                var tmp_path_buf: [std.fs.max_path_bytes]u8 = undefined;
                                const tmp_path = try alloc.dupe(u8, try std.fmt.bufPrint(&tmp_path_buf, "/tmp/{s}-{s}", .{ entry.name, zuid.new.v4().toString() }));

                                try info.write("Deleting item...", .info);
                                if (view.dir.rename(entry.name, tmp_path)) {
                                    try info.write("Deleted item.", .info);
                                    view.cleanup();
                                    const fuzzy = text_input.sliceToCursor(&input_buf);
                                    view.populate_entries(fuzzy) catch |err| {
                                        switch (err) {
                                            error.AccessDenied => try info.write_err(.PermissionDenied),
                                            else => try info.write_err(.UnknownError),
                                        }
                                    };

                                    try actions.append(.{ .delete = .{ .old_path = old_path, .tmp_path = tmp_path } });
                                } else |_| {
                                    try info.write_err(.UnableToDeleteItem);
                                }

                                last_pressed = null;
                            },
                            'd' => {
                                state = .new_dir;
                                last_pressed = null;
                            },
                            '%' => {
                                state = .new_file;
                                last_pressed = null;
                            },
                            'u' => {
                                if (actions.items.len > 0) {
                                    const action = actions.pop();
                                    switch (action) {
                                        .delete => |a| {
                                            // TODO: Will overwrite an item if it has the same name.
                                            if (view.dir.rename(a.tmp_path, a.old_path)) {
                                                defer alloc.free(a.tmp_path);
                                                defer alloc.free(a.old_path);

                                                view.cleanup();
                                                const fuzzy = text_input.sliceToCursor(&input_buf);
                                                view.populate_entries(fuzzy) catch |err| {
                                                    switch (err) {
                                                        error.AccessDenied => try info.write_err(.PermissionDenied),
                                                        else => try info.write_err(.UnknownError),
                                                    }
                                                };
                                                try info.write("Restored deleted item.", .info);
                                            } else |_| {
                                                try info.write_err(.UnableToUndo);
                                            }
                                        },
                                    }
                                } else {
                                    try info.write("Nothing to undo.", .info);
                                }
                                last_pressed = null;
                            },
                            '/' => {
                                state = State.fuzzy;
                                last_pressed = null;
                            },
                            else => {
                                // log.debug("codepoint: {d}\n", .{key.codepoint});
                            },
                        }
                    },
                    else => {},
                }
            },
            .fuzzy, .new_file, .new_dir => {
                switch (event) {
                    .key_press => |key| {
                        if ((key.codepoint == 'c' and key.mods.ctrl) or key.codepoint == 'q') {
                            break;
                        }

                        switch (key.codepoint) {
                            Key.escape => {
                                text_input.clearAndFree();
                                state = State.normal;

                                switch (state) {
                                    .new_dir => {},
                                    .new_file => {},
                                    .fuzzy => {
                                        view.cleanup();
                                        view.populate_entries("") catch |err| {
                                            switch (err) {
                                                error.AccessDenied => try info.write_err(.PermissionDenied),
                                                else => try info.write_err(.UnknownError),
                                            }
                                        };
                                    },
                                    else => {},
                                }
                            },
                            Key.enter => {
                                switch (state) {
                                    .new_dir => {
                                        const dir = text_input.sliceToCursor(&input_buf);
                                        if (view.dir.makeDir(dir)) {
                                            view.cleanup();
                                            view.populate_entries("") catch |err| {
                                                switch (err) {
                                                    error.AccessDenied => try info.write_err(.PermissionDenied),
                                                    else => try info.write_err(.UnknownError),
                                                }
                                            };
                                        } else |err| {
                                            switch (err) {
                                                error.AccessDenied => try info.write_err(.PermissionDenied),
                                                error.PathAlreadyExists => try info.write_err(.ItemAlreadyExists),
                                                else => try info.write_err(.UnknownError),
                                            }
                                        }
                                        text_input.clearAndFree();
                                    },
                                    .new_file => {
                                        const file = text_input.sliceToCursor(&input_buf);
                                        if (environment.file_exists(view.dir, file)) {
                                            try info.write_err(.ItemAlreadyExists);
                                        } else {
                                            if (view.dir.createFile(file, .{})) |f| {
                                                f.close();
                                                view.cleanup();
                                                view.populate_entries("") catch |err| {
                                                    switch (err) {
                                                        error.AccessDenied => try info.write_err(.PermissionDenied),
                                                        else => try info.write_err(.UnknownError),
                                                    }
                                                };
                                            } else |err| {
                                                switch (err) {
                                                    error.AccessDenied => try info.write_err(.PermissionDenied),
                                                    else => try info.write_err(.UnknownError),
                                                }
                                            }
                                        }
                                        text_input.clearAndFree();
                                    },
                                    .fuzzy => {},
                                    else => {},
                                }
                                state = State.normal;
                            },
                            else => {
                                try text_input.update(.{ .key_press = key });

                                switch (state) {
                                    .new_dir => {},
                                    .new_file => {},
                                    .fuzzy => {
                                        view.cleanup();
                                        const fuzzy = text_input.sliceToCursor(&input_buf);
                                        view.populate_entries(fuzzy) catch |err| {
                                            switch (err) {
                                                error.AccessDenied => try info.write_err(.PermissionDenied),
                                                else => try info.write_err(.UnknownError),
                                            }
                                        };
                                    },
                                    else => {},
                                }
                            },
                        }
                    },
                    else => {},
                }
            },
        }

        // -- Absolute file path bar
        const abs_file_path_bar = win.child(.{
            .x_off = 0,
            .y_off = 0,
            .width = .{ .limit = win.width },
            .height = .{ .limit = top_div },
        });
        _ = try abs_file_path_bar.print(&.{vaxis.Segment{ .text = try view.full_path(".") }}, .{});
        // --

        // -- File information bar
        var file_information_buf: [1024]u8 = undefined;
        const file_information = try std.fmt.bufPrint(&file_information_buf, "{d}/{d} {s} {s}", .{
            view.entries.selected + 1,
            view.entries.items.items.len,
            std.fs.path.extension(if (view.entries.get(view.entries.selected)) |entry| entry.name else |_| ""),
            std.fmt.fmtIntSizeDec(file_metadata.size()),
        });

        const file_information_bar = win.child(.{
            .x_off = 0,
            .y_off = win.height - bottom_div,
            .width = if (config.preview_file) .{ .limit = win.width / 2 } else .{ .limit = win.width },
            .height = .{ .limit = bottom_div },
        });
        file_information_bar.fill(vaxis.Cell{ .style = config.styles.file_information });
        _ = try file_information_bar.print(&.{vaxis.Segment{ .text = file_information, .style = config.styles.file_information }}, .{});
        // --

        // -- Key binding bar
        const keybind_bar = win.child(.{
            .x_off = (win.width / 2) + 5,
            .y_off = win.height - bottom_div,
            .width = .{ .limit = win.width / 2 },
            .height = .{ .limit = bottom_div },
        });
        _ = try keybind_bar.print(&.{vaxis.Segment{
            .text = if (last_pressed) |key| key.text.? else "",
            .style = if (config.preview_file) .{} else config.styles.file_information,
        }}, .{});
        // --

        // -- File preview bar
        if (config.preview_file == true) {
            const file_name_bar = win.child(.{
                .x_off = win.width / 2,
                .y_off = 0,
                .width = .{ .limit = win.width },
                .height = .{ .limit = top_div },
            });
            if (view.entries.get(view.entries.selected)) |entry| {
                var file_name_buf: [std.fs.MAX_NAME_BYTES + 2]u8 = undefined;
                const file_name = try std.fmt.bufPrint(&file_name_buf, "[{s}]", .{entry.name});
                _ = try file_name_bar.print(&.{vaxis.Segment{
                    .text = file_name,
                    .style = config.styles.file_name,
                }}, .{});
            } else |_| {}

            const preview_bar = win.child(.{
                .x_off = win.width / 2,
                .y_off = top_div + 1,
                .width = .{ .limit = win.width / 2 },
                .height = .{ .limit = win.height - (file_name_bar.height + keybind_bar.height + top_div + bottom_div) },
            });

            // Populate preview bar
            if (view.entries.all().len > 0 and config.preview_file == true) {
                const entry = try view.entries.get(view.entries.selected);

                @memcpy(&last_path, &path);
                last_item_path = last_path[0..current_item_path.len];
                current_item_path = try std.fmt.bufPrint(&path, "{s}/{s}", .{ try view.full_path("."), entry.name });

                switch (entry.kind) {
                    .directory => {
                        view.cleanup_sub();
                        if (view.populate_sub_entries(entry.name)) {
                            try view.write_sub_entries(preview_bar, config.styles.list_item);
                        } else |err| {
                            switch (err) {
                                error.AccessDenied => try info.write_err(.PermissionDenied),
                                else => try info.write_err(.UnknownError),
                            }
                        }
                    },
                    .file => file: {
                        var file = view.dir.openFile(entry.name, .{ .mode = .read_only }) catch |err| {
                            switch (err) {
                                error.AccessDenied => try info.write_err(.PermissionDenied),
                                else => try info.write_err(.UnknownError),
                            }

                            _ = try preview_bar.print(&.{
                                .{
                                    .text = "No preview available.",
                                },
                            }, .{});

                            break :file;
                        };
                        defer file.close();
                        const bytes = try file.readAll(&file_buf);

                        // Handle image.
                        if (config.show_images == true) unsupported_terminal: {
                            const supported: [1][]const u8 = .{".png"};

                            for (supported) |ext| {
                                if (std.mem.eql(u8, std.fs.path.extension(entry.name), ext)) {
                                    // Don't re-render preview if we haven't changed selection.
                                    if (std.mem.eql(u8, last_item_path, current_item_path)) break :file;

                                    if (vx.loadImage(alloc, .{ .path = current_item_path })) |img| {
                                        image = img;
                                    } else |_| {
                                        image = null;
                                        break :unsupported_terminal;
                                    }

                                    if (image) |img| {
                                        try img.draw(preview_bar, .{ .scale = .fit });
                                    }

                                    break :file;
                                } else {
                                    // Free any image we might have already.
                                    if (image) |img| {
                                        vx.freeImage(img.id);
                                    }
                                }
                            }
                        }

                        // Handle utf-8.
                        if (std.unicode.utf8ValidateSlice(file_buf[0..bytes])) {
                            _ = try preview_bar.print(&.{
                                .{
                                    .text = file_buf[0..bytes],
                                },
                            }, .{});
                            break :file;
                        }

                        // Fallback to no preview.
                        _ = try preview_bar.print(&.{
                            .{
                                .text = "No preview available.",
                            },
                        }, .{});
                    },
                    else => {
                        _ = try preview_bar.print(&.{vaxis.Segment{ .text = current_item_path }}, .{});
                    },
                }
            }
        }
        // --

        // -- Current directory bar
        const current_dir_bar = win.child(.{
            .x_off = 0,
            .y_off = top_div + 1,
            .width = if (config.preview_file) .{ .limit = win.width / 2 } else .{ .limit = win.width },
            .height = .{ .limit = win.height - (abs_file_path_bar.height + file_information_bar.height + top_div + bottom_div) },
        });
        try view.write_entries(current_dir_bar, config.styles.selected_list_item, config.styles.list_item, null);
        // --

        // -- Info bar
        if (info.len > 0) {
            if (text_input.grapheme_count > 0) {
                text_input.clearAndFree();
            }

            _ = try info_bar.print(&.{
                .{
                    .text = info.slice(),
                    .style = switch (info.style) {
                        .info => config.styles.info_bar,
                        .err => config.styles.error_bar,
                    },
                },
            }, .{});
        }

        // Display search box.
        switch (state) {
            .fuzzy, .new_file, .new_dir => {
                info.reset();
                text_input.draw(info_bar);
            },
            .normal => {
                if (text_input.grapheme_count > 0) {
                    text_input.draw(info_bar);
                }

                win.hideCursor();
            },
        }
        // --

        try vx.render();

        last_known_height = current_dir_bar.height;
    }

    for (actions.items) |action| {
        switch (action) {
            .delete => |a| {
                log.err("{s} - {s}", .{ a.tmp_path, a.old_path });
                alloc.free(a.tmp_path);
                alloc.free(a.old_path);
            },
        }
    }
}

pub fn panic(msg: []const u8, trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    vx.deinit(null);
    std.builtin.default_panic(msg, trace, ret_addr);
}
