const std = @import("std");
const builtin = @import("builtin");
const environment = @import("./environment.zig");
const vaxis = @import("vaxis");
const Notification = @import("./notification.zig");

pub const ParseRes = struct { deprecated: bool };

const Config = struct {
    show_hidden: bool = true,
    sort_dirs: bool = true,
    show_images: bool = true,
    preview_file: bool = true,
    styles: Styles,

    config_path_buf: [std.fs.max_path_bytes]u8 = undefined,
    config_path: ?[]u8 = null,

    pub fn parse(self: *Config, alloc: std.mem.Allocator) !ParseRes {
        var deprecated = false;
        var config_location: struct {
            home_dir: std.fs.Dir,
            path: []const u8,
        } = lbl: {
            if (try environment.getXdgConfigHomeDir()) |home_dir| {
                const path = "zfe" ++ std.fs.path.sep_str ++ "config.json";
                if (environment.fileExists(home_dir, path)) {
                    break :lbl .{
                        .home_dir = home_dir,
                        .path = path,
                    };
                }

                var dir = home_dir;
                dir.close();
            }

            if (try environment.getHomeDir()) |home_dir| {
                const path = ".zfe" ++ std.fs.path.sep_str ++ "config.json";
                if (environment.fileExists(home_dir, path)) {
                    break :lbl .{
                        .home_dir = home_dir,
                        .path = path,
                    };
                }

                const deprecated_path = ".config" ++ std.fs.path.sep_str ++ "zfe" ++ std.fs.path.sep_str ++ "config.json";
                if (environment.fileExists(home_dir, deprecated_path)) {
                    deprecated = true;
                    break :lbl .{
                        .home_dir = home_dir,
                        .path = deprecated_path,
                    };
                }

                var dir = home_dir;
                dir.close();
            }

            return .{ .deprecated = deprecated };
        };
        defer config_location.home_dir.close();

        const config_file = try config_location.home_dir.openFile(config_location.path, .{});
        defer config_file.close();

        const config_str = try config_file.readToEndAlloc(alloc, 1024 * 1024 * 1024);
        defer alloc.free(config_str);

        const parsed_config = try std.json.parseFromSlice(Config, alloc, config_str, .{});
        defer parsed_config.deinit();

        self.* = parsed_config.value;
        self.config_path = config_location.home_dir.realpath(
            config_location.path,
            &self.config_path_buf,
        ) catch null;
        return .{ .deprecated = deprecated };
    }
};

const Colours = struct {
    const RGB = [3]u8;
    const red: RGB = .{ 227, 23, 10 };
    const orange: RGB = .{ 251, 139, 36 };
    const blue: RGB = .{ 82, 209, 220 };
    const grey: RGB = .{ 39, 39, 39 };
    const black: RGB = .{ 0, 0, 0 };
    const snow_white: RGB = .{ 254, 252, 253 };
};

const NotificationStyles = struct {
    box: vaxis.Style = vaxis.Style{
        .bg = .{ .rgb = Colours.grey },
    },
    err: vaxis.Style = vaxis.Style{
        .fg = .{ .rgb = Colours.red },
        .bg = .{ .rgb = Colours.grey },
    },
    warn: vaxis.Style = vaxis.Style{
        .fg = .{ .rgb = Colours.orange },
        .bg = .{ .rgb = Colours.grey },
    },
    info: vaxis.Style = vaxis.Style{
        .fg = .{ .rgb = Colours.blue },
        .bg = .{ .rgb = Colours.grey },
    },
};

const Styles = struct {
    selected_list_item: vaxis.Style = vaxis.Style{
        .bg = .{ .rgb = Colours.grey },
        .bold = true,
    },
    notification: NotificationStyles = NotificationStyles{},
    text_input: vaxis.Style = vaxis.Style{},
    text_input_err: vaxis.Style = vaxis.Style{ .bg = .{ .rgb = Colours.red } },
    list_item: vaxis.Style = vaxis.Style{},
    file_name: vaxis.Style = vaxis.Style{},
    file_information: vaxis.Style = vaxis.Style{
        .fg = .{ .rgb = Colours.black },
        .bg = .{ .rgb = Colours.snow_white },
    },
    git_branch: vaxis.Style = vaxis.Style{
        .fg = .{ .rgb = Colours.blue },
    },
};

pub var config: Config = Config{ .styles = Styles{} };
