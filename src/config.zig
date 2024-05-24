const std = @import("std");
const vaxis = @import("vaxis");
const environment = @import("./environment.zig");

const Config = struct {
    show_hidden: bool = true,
    sort_dirs: bool = false,
    show_images: bool = false,
    preview_file: bool = true,
    styles: Styles,

    pub fn parse(self: *Config, alloc: std.mem.Allocator) !void {
        var home_dir = try environment.getHomeDir();
        defer home_dir.close();

        const config_path = try std.fs.path.join(alloc, &.{ ".zfe", "config.json" });
        defer alloc.free(config_path);

        if (!environment.fileExists(home_dir, config_path)) {
            return error.ConfigNotFound;
        }

        const config_file = try home_dir.openFile(config_path, .{});
        defer config_file.close();

        const config_str = try config_file.readToEndAlloc(alloc, 1024 * 1024 * 1024);
        defer alloc.free(config_str);

        const c = try std.json.parseFromSlice(Config, alloc, config_str, .{});
        defer c.deinit();

        self.* = c.value;
    }
};

const Styles = struct {
    selected_list_item: vaxis.Style = vaxis.Style{},
    list_item: vaxis.Style = vaxis.Style{},
    file_name: vaxis.Style = vaxis.Style{},
    file_information: vaxis.Style = vaxis.Style{},
};

pub var config: Config = Config{ .styles = Styles{} };
