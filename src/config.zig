const std = @import("std");
const builtin = @import("builtin");
const environment = @import("./environment.zig");
const vaxis = @import("vaxis");
const Notification = @import("./notification.zig");

const Config = struct {
    show_hidden: bool = true,
    sort_dirs: bool = true,
    show_images: bool = true,
    preview_file: bool = true,
    styles: Styles,

    pub fn parse(self: *Config, alloc: std.mem.Allocator, notification: *Notification) !void {
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
                    try notification.writeWarn(.DeprecatedConfigPath);
                    break :lbl .{
                        .home_dir = home_dir,
                        .path = deprecated_path,
                    };
                }

                var dir = home_dir;
                dir.close();
            }

            return;
        };
        defer config_location.home_dir.close();

        const config_file = try config_location.home_dir.openFile(config_location.path, .{});
        defer config_file.close();

        const config_str = try config_file.readToEndAlloc(alloc, 1024 * 1024 * 1024);
        defer alloc.free(config_str);

        const parsed_config = try std.json.parseFromSlice(Config, alloc, config_str, .{});
        defer parsed_config.deinit();

        self.* = parsed_config.value;
    }
};

const Styles = struct {
    selected_list_item: vaxis.Style = vaxis.Style{
        .bg = .{ .rgb = .{ 45, 45, 45 } },
        .bold = true,
    },
    notification_box: vaxis.Style = vaxis.Style{
        .bg = .{ .rgb = .{ 45, 45, 45 } },
    },
    list_item: vaxis.Style = vaxis.Style{},
    file_name: vaxis.Style = vaxis.Style{},
    file_information: vaxis.Style = vaxis.Style{
        .fg = .{ .rgb = .{ 0, 0, 0 } },
        .bg = .{ .rgb = .{ 255, 255, 255 } },
    },
    error_bar: vaxis.Style = vaxis.Style{
        .fg = .{ .rgb = .{ 216, 74, 74 } },
        .bg = .{ .rgb = .{ 45, 45, 45 } },
    },
    warning_bar: vaxis.Style = vaxis.Style{
        .fg = .{ .rgb = .{ 216, 129, 74 } },
        .bg = .{ .rgb = .{ 45, 45, 45 } },
    },
    info_bar: vaxis.Style = vaxis.Style{
        .fg = .{ .rgb = .{ 0, 140, 200 } },
        .bg = .{ .rgb = .{ 45, 45, 45 } },
    },
};

pub var config: Config = Config{ .styles = Styles{} };
