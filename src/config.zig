const std = @import("std");
const vaxis = @import("vaxis");

const Config = struct {
    show_hidden: bool = true,
    sort_dirs: bool = false,
    show_images: bool = false,
    preview_file: bool = true,
    styles: Styles,

    pub fn parse(self: *Config, alloc: std.mem.Allocator, path: []const u8) !void {
        const config_file = try std.fs.cwd().openFile(path, .{});
        defer config_file.close();

        const config_str = try config_file.readToEndAlloc(alloc, 1024 * 1024 * 1024);
        defer alloc.free(config_str);

        const c = try std.json.parseFromSlice(Config, alloc, config_str, .{});
        defer c.deinit();

        self.show_hidden = c.value.show_hidden;
        self.sort_dirs = c.value.sort_dirs;
        self.show_images = c.value.show_images;
        self.preview_file = c.value.preview_file;
        self.styles = c.value.styles;
    }
};

const Styles = struct {
    selected_list_item: vaxis.Style = vaxis.Style{},
    list_item: vaxis.Style = vaxis.Style{},
    file_name: vaxis.Style = vaxis.Style{},
    file_information: vaxis.Style = vaxis.Style{},
};

pub var config: Config = Config{ .styles = Styles{} };
