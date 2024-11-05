<h1 align="center">
    zfe
</h1>

**zfe** is a small, customizable file explorer for your terminal. 

![image](https://github.com/BrookJeynes/zfe/assets/25432120/811956b1-9819-4213-9bd8-67700d901ddd)

## Install
To install zfe, check the "Releases" section in Github and download the 
appropriate version.

### Building locally
Ensure you have the following dependencies installed:
- Zig (the targeted version can be found within the ./build.zig.zon
- mupdf
- z

```
git clone https://github.com/brookjeynes/zfe.git
cd zfe
zig build -Doptimize=ReleaseSafe
```

## Keybinds
```
Normal mode:
q / <CTRL-c>       :Exit.

j / <Down>         :Go down.
k / <Up>           :Go up.
h / <Left> / -     :Go to the parent directory if exists.
l / <Right>        :Open item or change directory.
gg                 :Go to the top.
G                  :Go to the bottom.
c                  :Change directory via path. Will enter input mode.

R                  :Rename item. Will enter input mode.
D                  :Delete item.
u                  :Undo delete/rename.

d                  :Create directory. Will enter input mode.
%                  :Create file. Will enter input mode.
/                  :Fuzzy search directory. Will enter input mode.

Input mode:
<Esc>              :Cancel input.
<Enter>            :Confirm input.
```

## Configuration
Configure `zfe` by editing the external configuration file located at either:
- `$HOME/.config/zfe/config.json`
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
    .info_bar: Style,
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

## Optional Dependencies
- Terminal emulator with the Kitty image protocol (e.g. Kitty, WezTerm, Konsole, etc.). 
  This is used to render images and PDF previews if enabled.
- `pdftotext` to view PDF text previews.

## Contributing
Contributions, issues, and feature requests are always welcome! This project is
currently using the latest stable release of Zig (0.13.0).
