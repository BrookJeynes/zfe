const std = @import("std");
const builtin = @import("builtin");
const vaxis = @import("vaxis");
const environment = @import("./environment.zig");

const Config = struct {
    show_hidden: bool = true,
    sort_dirs: bool = false,
    show_images: bool = false,
    preview_file: bool = true,
    styles: Styles,

    pub fn parse(self: *Config, alloc: std.mem.Allocator) !void {
        var config_path: []u8 = undefined;
        defer alloc.free(config_path);

        var config_home: std.fs.Dir = undefined;
        defer config_home.close();
        if (try environment.get_xdg_config_home_dir()) |path| {
            config_home = path;
            config_path = try std.fs.path.join(alloc, &.{ "zfe", "config.json" });
        } else {
            if (try environment.get_home_dir()) |path| {
                config_home = path;
                config_path = try std.fs.path.join(alloc, &.{ ".config", "zfe", "config.json" });
            } else {
                return error.MissingConfigHomeEnvironmentVariable;
            }
        }

        if (!environment.file_exists(config_home, config_path)) {
            return error.ConfigNotFound;
        }

        const config_file = try config_home.openFile(config_path, .{});
        defer config_file.close();

        const config_str = try config_file.readToEndAlloc(alloc, 1024 * 1024 * 1024);
        defer alloc.free(config_str);

        const c = try std.json.parseFromSlice(Config, alloc, config_str, .{});
        defer c.deinit();

        self.* = c.value;
    }
};

const Styles = struct {
    selected_list_item: vaxis.Style = vaxis.Style{
        .bg = .{ .rgb = .{ 45, 45, 45 } },
        .bold = true,
    },
    list_item: vaxis.Style = vaxis.Style{},
    file_name: vaxis.Style = vaxis.Style{},
    file_information: vaxis.Style = vaxis.Style{
        .fg = .{ .rgb = .{ 0, 0, 0 } },
        .bg = .{ .rgb = .{ 255, 255, 255 } },
    },
};

pub var config: Config = Config{ .styles = Styles{} };
