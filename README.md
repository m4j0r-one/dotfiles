## Screenshot

![My CachyOS and Niri desktop](screenshots/desktop.png)

# m4j0r.one Dotfiles

My personal CachyOS and Niri desktop configuration.

This repository contains the configuration behind my current desktop setup,
including Niri, Noctalia, Ghostty, Walker, Fastfetch, Quickshell, CAVA and a
modular Conky dashboard.

The setup is built around a two-monitor Niri workflow and includes custom
desktop styling, window rules, utility scripts, audio visualization and
Noctalia extensions.

> This is a snapshot of my personal setup, not a universal one-command
> installer. Some paths, displays and system-specific modules need to be
> adjusted before use.

## Included components

- Niri configuration split into modular KDL files
- Custom Niri window rules for applications, launchers and games
- Noctalia configuration
- Custom `m4j0r-One` Noctalia color scheme
- Custom local `m4j0r-shortcuts` Noctalia plugin
- Ghostty configuration and custom cursor shader
- Walker configuration and custom theme
- Fastfetch configurations and artwork
- Quickshell/CAVA audio visualizer
- Modular Conky dashboard
- Spotify and Tauon artwork helpers
- Multi-monitor wallpaper helper
- Custom utility and startup scripts

## Repository structure

```text
.
├── config/
│   ├── cava/
│   ├── fastfetch/
│   ├── ghostty/
│   ├── niri/
│   ├── noctalia/
│   │   ├── colorschemes/
│   │   │   └── m4j0r-One/
│   │   └── plugins/
│   │       └── m4j0r-shortcuts/
│   ├── quickshell/
│   ├── systemd/
│   │   └── user/
│   ├── walker/
│   └── zsh/
│       └── python-shell/
├── home/
│   ├── .p10k.zsh
│   └── .zshrc
├── local/
│   ├── bin/
│   └── share/
├── screenshots/
└── scripts/
    ├── conky/
    ├── python-projects-backup.sh
    └── weekly-backup-runner.sh
```

## Installation paths

| Repository path                     | Target location                       |
| ----------------------------------- | ------------------------------------- |
| `config/niri`                       | `~/.config/niri`                      |
| `config/ghostty`                    | `~/.config/ghostty`                   |
| `config/noctalia`                   | `~/.config/noctalia`                  |
| `config/walker`                     | `~/.config/walker`                    |
| `config/fastfetch`                  | `~/.config/fastfetch`                 |
| `config/quickshell`                 | `~/.config/quickshell`                |
| `config/cava`                       | `~/.config/cava`                      |
| `config/zsh`                        | `~/.config/zsh`                       |
| `config/systemd/user`               | `~/.config/systemd/user`              |
| `home/.zshrc`                       | `~/.zshrc`                            |
| `home/.p10k.zsh`                    | `~/.p10k.zsh`                         |
| `local/bin`                         | `~/.local/bin`                        |
| `local/share`                       | `~/.local/share`                      |
| `scripts/conky`                     | `~/scripts/Conky`                     |
| `scripts/python-projects-backup.sh` | `~/scripts/python-projects-backup.sh` |
| `scripts/weekly-backup-runner.sh`   | `~/scripts/weekly-backup-runner.sh`   |

Back up your existing configuration before copying anything.

## Backup automation

The setup includes a weekly backup runner:

```text
~/scripts/weekly-backup-runner.sh
```

It coordinates six separate backup modules:

1. Conky configuration and helper scripts
2. General scripts
3. Program configuration
4. Niri configuration
5. Python projects
6. Encrypted private data

The Python project backup stores:

```text
~/Projekte/Python
```

and deliberately excludes project-local `.venv` directories. Virtual environments are recreated after restoration from the project's `pyproject.toml`.

The backup runner is started through the user-level systemd units:

```text
~/.config/systemd/user/m4j0r-weekly-backup.service
~/.config/systemd/user/m4j0r-weekly-backup.timer
```

Additional user timers update the DNS and Unraid cache data used by the Conky dashboard.

After restoring the systemd user units, reload systemd and enable the required timers before relying on the automation.

## Required customization

Search the repository for these placeholders:

```
YOUR_USERNAME
YOUR_SERVER_IP
```

You should also review:

- `config/niri/cfg/display.kdl` for monitor names and resolutions
- `config/niri/cfg/autostart.kdl` for personal startup applications
- `config/niri/cfg/keybinds.kdl` for application paths and shortcuts
- `config/niri/cfg/rules.kdl` for application and game-specific window rules
- `config/noctalia/settings.json` for wallpaper, avatar, weather and display settings
- `config/quickshell/m4j0r-visualizer/` for the CAVA visualizer configuration
- the Conky storage, backup and home-server cards
- font names used by Ghostty, Walker, Fastfetch and Conky

The supplied Niri configuration is designed around two displays named
`DP-1` and `DP-2`.

Monitor names and assignments should always be adjusted to match your own
system.

## Niri notes

The Niri configuration is separated into multiple files under:

```
config/niri/cfg/
```

This keeps display settings, keybindings, startup commands, window rules and
visual settings easier to maintain.

The current setup also contains application-specific rules for software such
as Battle.net and Gamescope-based games.

These rules depend on application IDs, window titles and monitor names from
my system and may need to be adapted before use.

Validate changes with:

```
niri validate
```

## Noctalia notes

The repository includes my custom Noctalia color scheme:

```
config/noctalia/colorschemes/m4j0r-One/
```

It also includes my local shortcuts plugin:

```
config/noctalia/plugins/m4j0r-shortcuts/
```

Additional plugins such as the Noctalia calculator and polkit agent are
referenced through `plugins.json` and come from the upstream Noctalia plugin
repository. Their source files are not duplicated here.

Wallpaper and avatar paths inside `settings.json` use placeholders and must be
adjusted for your own system.

## Quickshell / CAVA visualizer

The desktop includes a custom Quickshell audio visualizer driven by CAVA.

Relevant files are stored under:

```
config/quickshell/m4j0r-visualizer/
config/cava/
```

The visualizer expects its CAVA configuration in the user's home directory,
so the username placeholder must be adjusted after installation.

## Conky notes

The dashboard contains several machine-specific modules.

Cards related to storage, backups, DNS and home-server monitoring require
local customization before they will work on another system.

The custom Conky binary used on my system is not included. The startup script
first checks:

```
~/.local/opt/conky-niri/bin/conky
```

If that executable is unavailable, it falls back to the regular `conky`
command from the system.

## Status

This repository is an actively maintained snapshot of my current CachyOS +
Niri desktop.

I update it as the setup evolves, so individual configurations may change as
I test new tools, workflows and desktop ideas.

It is primarily meant as a reference and source of ideas rather than a fully
automated distribution-independent setup.

## m4j0r.one Community

A German-speaking, beginner-friendly community around Python, Linux,
automation, homelabs and open source.

**Gemeinsam lernen. Gemeinsam bauen. Menschlich bleiben.**

- Website: https://m4j0r.one
- Instagram: https://www.instagram.com/m4j0r_0ne
- Discord: https://discord.gg/m65trXh65e

## License

Configuration files, scripts and source code are available under the
[MIT License](LICENSE).

Logos, branding and artwork are excluded from the MIT License. See
[ASSETS.md](ASSETS.md) for details.
