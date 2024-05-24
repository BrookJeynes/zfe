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

## Install
To install zfe, check the "Releases" section in Github and download the 
appropriate version or build locally via `zig build run`.

## Configuration
Configure `zfe` by editing the external configuration file located at either:
- `$HOME/.zfe/config.json`
- `$XDG_CONFIG_HOME/zfe/config.json`.

## Keybinds
```
j / <Down>         :Go down.
k / <Up>           :Go up.
h / <Left> / -     :Go to the parent directory if exists.
l / <Right>        :Open item or change directory.
gg                 :Go to the top.
G                  :Go to the bottom.
q / <CTRL-c>       :Exit.
```

## Roadmap
- Keybindings for Common Actions:
  - Delete files
  - Duplicate files
  - Copy files
  - Adjust settings
- Open Files in Editor
- Customizable keybinds
- Fuzzy search files
- Syntax highlighting

## Contributing
Contributions, issues, and feature requests are always welcome! This project is
currently using the latest stable release of Zig (0.12.0).
