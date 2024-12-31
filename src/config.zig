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
        return .{ .deprecated = deprecated };
    }
};

const Styles = struct {
    selected_list_item: vaxis.Style = vaxis.Style{
        .bg = .{ .rgb = .{ 39, 39, 39 } },
        .bold = true,
    },
    notification_box: vaxis.Style = vaxis.Style{
        .bg = .{ .rgb = .{ 39, 39, 39 } },
    },
    list_item: vaxis.Style = vaxis.Style{},
    file_name: vaxis.Style = vaxis.Style{},
    file_information: vaxis.Style = vaxis.Style{
        .fg = .{ .rgb = .{ 0, 0, 0 } },
        .bg = .{ .rgb = .{ 254, 252, 253 } },
    },
    error_bar: vaxis.Style = vaxis.Style{
        .fg = .{ .rgb = .{ 227, 23, 10 } },
        .bg = .{ .rgb = .{ 39, 39, 39 } },
    },
    warning_bar: vaxis.Style = vaxis.Style{
        .fg = .{ .rgb = .{ 251, 139, 36 } },
        .bg = .{ .rgb = .{ 39, 39, 39 } },
    },
    info_bar: vaxis.Style = vaxis.Style{
        .fg = .{ .rgb = .{ 82, 209, 220 } },
        .bg = .{ .rgb = .{ 39, 39, 39 } },
    },
    git_branch: vaxis.Style = vaxis.Style{
        .fg = .{ .rgb = .{ 82, 209, 220 } },
    },
};

pub var config: Config = Config{ .styles = Styles{} };
