<h1 align="center">
    zfe
</h1>

<div align="center">Unix terminal file explorer, written in Zig</div>

<br>

**zfe** is a small unix terminal file explorer written in Zig. 

![image](https://github.com/BrookJeynes/zfe/assets/25432120/811956b1-9819-4213-9bd8-67700d901ddd)

## Features
- **Simple to use**: Minimal and customizable keymaps with vim binding support.
- **Image Previews**: Preview images with Kitty terminal.
- **File Previews**: Preview contents of files directly in the terminal.
- **Configurable Options**: Customize settings via an external configuration file.
- **Fuzzy Search**: Fuzzy search within directories.

## Install
To install zfe, check the "Releases" section in Github and download the 
appropriate version or build locally via `zig build -Doptimize=ReleaseSafe`.

## Configuration
Configure `zfe` by editing the external configuration file located at either:
- `$HOME/.zfe/config.json`
- `$XDG_CONFIG_HOME/zfe/config.json`.

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

Styles = struct {
    .selected_list_item: Style,
    .list_item: Style,
    .file_name: Style,
    .file_information: Style
    .error_bar: Style,
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

## Keybinds
```
Normal mode:
j / <Down>         :Go down.
k / <Up>           :Go up.
h / <Left> / -     :Go to the parent directory if exists.
l / <Right>        :Open item or change directory.
gg                 :Go to the top.
G                  :Go to the bottom.
q / <CTRL-c>       :Exit.
/                  :Enter search mode.

Search mode:
<Esc>              :Exit search mode.
<Enter>            :Confirm search.
```

## Roadmap
- Keybindings for Common Actions:
  - Delete files
  - Duplicate files
  - Copy files
  - Adjust settings
- Customizable keybinds
- Syntax highlighting

## Contributing
Contributions, issues, and feature requests are always welcome! This project is
currently using the latest stable release of Zig (0.12.0).
