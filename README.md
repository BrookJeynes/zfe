# zfe

![zfe preview](./assets/preview.png)

**zfe** is a small unix tui file explorer designed to be simple and fast.

- [Installation](#installation)
- [Integrations](#integrations)
- [Key manual](#key-manual)
- [Configuration](#configuration)
- [Contributing](#contributing)

## Installation
To install zfe, check the "Releases" section in Github and download the 
appropriate version or build locally via `zig build -Doptimize=ReleaseSafe`.

## Integrations
- `pdftotext` to view PDF text previews.
- A terminal supporting the `kitty image protocol` to view images.

## Key manual
```
Normal mode:
<CTRL-c>           :Exit.
j / <Down>         :Go down.
k / <Up>           :Go up.
h / <Left> / -     :Go to the parent directory.
l / <Right>        :Open item or change directory.
g                  :Go to the top.
G                  :Go to the bottom.
c                  :Change directory via path. Will enter input mode.
R                  :Rename item. Will enter input mode.
D                  :Delete item.
u                  :Undo delete/rename.
d                  :Create directory. Will enter input mode.
%                  :Create file. Will enter input mode.
/                  :Fuzzy search directory. Will enter input mode.
:                  :Allows for zfe commands to be entered. Please refer to the 
                    "Command mode" section for available commands. Will enter 
                    input mode.

Input mode:
<Esc>              :Cancel input.
<CR>               :Confirm input.

Command mode:
:q                 :Exit.
:config            :Navigate to config directory if it exists.
```


## Configuration
Configure `zfe` by editing the external configuration file located at either:
- `$HOME/.zfe/config.json`
- `$XDG_CONFIG_HOME/zfe/config.json`.

zfe will look for these env variables specifically. If they are not set, zfe will
not be able to find the config file.

An example config file can be found [here](https://github.com/BrookJeynes/zfe/blob/main/example-config.json).

Config schema:
```
Config = struct {
    .show_hidden: bool,
    .sort_dirs: bool,
    .show_images: bool,
    .preview_file: bool,
    .styles: Styles,
}

NotificationStyles = struct {
    box: vaxis.Style,
    err: vaxis.Style,
    warn: vaxis.Style,
    info: vaxis.Style,
};

Styles = struct {
    .selected_list_item: Style,
    .list_item: Style,
    .file_name: Style,
    .file_information: Style
    .notification: NotificationStyles,
    .git_branch: Style,
}

Style = struct {
    .fg: Color,
    .bg: Color,
    .ul: Color,
    .ul_style = .{
        off,
        single,
        double,
        curly,
        dotted,
        dashed,
    }
    .bold: bool,
    .dim: bool,
    .italic: bool,
    .blink: bool,
    .reverse: bool,
    .invisible: bool,
    .strikethrough: bool,
}

Color = enum{
    default,
    index: u8,
    rgb: [3]u8,
}
```

## Contributing
Contributions, issues, and feature requests are always welcome! This project is
currently using the latest stable release of Zig (0.13.0).
