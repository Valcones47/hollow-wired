<div align="center">

# hollow-wired

**A responsive, hardware-accelerated Hyprland desktop environment powered by Quickshell, dynamic Material You theming, and hybrid GPU orchestration.**

[![Platform](https://img.shields.io/badge/Platform-Arch%20%7C%20CachyOS-1793D1?style=for-the-badge&logo=arch-linux&logoColor=white)](https://archlinux.org)
[![Compositor](https://img.shields.io/badge/Compositor-Hyprland%20(Lua)-00A3E0?style=for-the-badge&logo=hyprland&logoColor=white)](https://hyprland.org)
[![Shell](https://img.shields.io/badge/Shell-Quickshell%20(QML)-41CD52?style=for-the-badge&logo=qt&logoColor=white)](https://quickshell.outfoxxed.me)
[![Theming](https://img.shields.io/badge/Theme-Wallust%20Dynamic-FF69B4?style=for-the-badge)](https://github.com/InitCool/wallust)
[![License](https://img.shields.io/badge/License-GPL--3.0-blue?style=for-the-badge)](LICENSE)

<br />

<img src="quickshell-progress/etapa-28-appearance-tab.png" alt="Desktop Overview & Appearance Hub" width="880" />

</div>

---

## Overview

**hollow-wired** is a modern Linux desktop environment built from the ground up for speed, visual coherence, and ergonomics. It combines the performance of **Hyprland** (configured exclusively with modern Lua) with the power of **Quickshell** for all desktop layer-shell interfaces.

Legacy tools like Waybar, Rofi, SwayOSD, and Wofi are completely omitted. Every shell element—top bar, docks, dynamic island OSD, app launcher, live task switcher, and interactive desktop widgets—is written as native QML components running directly on Wayland layer-shell protocols.

---

## Core Features

<div align="center">
<table>
<tr>
<td width="50%">
<img src="quickshell-progress/etapa-15-launcher.png" alt="App Launcher" />
<p align="center"><b>App Launcher & Fuzzy Search</b></p>
</td>
<td width="50%">
<img src="quickshell-progress/etapa-14-dock-jogos.png" alt="Dock and Game Drawer" />
<p align="center"><b>Smart Autohide Dock & Game Shelf</b></p>
</td>
</tr>
<tr>
<td width="50%">
<img src="quickshell-progress/etapa-12-pop-audio.png" alt="Quick Settings & Audio Flyout" />
<p align="center"><b>TopBar Flyout & Quick Controls</b></p>
</td>
<td width="50%">
<img src="quickshell-progress/etapa-9-sidebar-tray.png" alt="Energy Sidebar & System Trays" />
<p align="center"><b>Slide-out Sidebar & System Trays</b></p>
</td>
</tr>
</table>
</div>

### Desktop Shell (Quickshell)
- **TopBar (`TopBar.qml`)**: 34px top bar with animated pill workspace indicators, active window titles, center clock with Hub trigger, and flyout menus with rounded inverted corners for Audio, Wi-Fi, Bluetooth, and Battery management.
- **Desktop Widgets (`DesktopWidgets.qml`)**: Layer-shell desktop widgets with 20px magnetic snap-to-grid positioning, visual inspector (glass, solid, glow, borderless styles; scalable 80% to 120%), and 13 native widgets:
  - Real RAM usage (excluding buffers/cache), CPU telemetry, GPU monitor (NVIDIA RTX / AMD / Intel), real-time Network speed monitor, Analog & Digital clocks, MPRIS music player with spinning vinyl animation, Monthly Calendar grid, Battery health, Storage usage, Pomodoro timer, persistent Notepad, Weather, and Daily quote.
  - Toggle edit mode at any time with `Super + W` or right-clicking empty desktop space.
- **Application Launcher (`Launcher.qml`)**: Keyboard-first fuzzy search opened via `Super` or `Super + R`. Features keyboard navigation, right-click contextual actions (pin to dock, add to gaming drawer), and instant query matching.
- **Autohiding Dock (`Dock.qml`)**: Edge-triggered bottom dock with active workspace indicators (`1·3` or `✦`), drag-and-drop reordering, expandable gaming shelf, and **dedicated Launcher button** with custom icon and animated GIF support (`rice-set-dock-icon`).
- **Shell Customization (`ShellCustomization.qml`)**: Unified visual styling engine for Hub, Sidebar, and Dock. Supports Glass, Solid, Glow (Neon), and Borderless styles, custom scales (80%, 100%, 120%), background opacities, and 6 accent colors with live reactive synchronization.
- **Dynamic Island OSD (`OSD.qml`)**: Non-intrusive floating capsule below the top bar providing visual feedback for volume levels, microphone mute, and screen brightness.
- **Energy Sidebar (`EnergySidebar.qml`)**: Slide-out right panel providing system tray icons, update count badges (Repo + AUR + Dotfiles), night light toggle, blur toggle, and two-step power options.
- **Alt+Tab Task Switcher (`AltTab.qml`)**: Live window thumbnails rendered via Wayland screencopy buffers, sorted by MRU (most recently used) focus history. Quick close windows on the fly with `Q`.
- **Native Clipboard (`Clipboard.qml`)**: Built-in clipboard manager invoked with `Super + V`, supporting quick search, image preview, and instant history clearing.
- **Internationalization (i18n)**: Seamless bilingual localization (English & Brazilian Portuguese) across all shell components and settings via reactive JSON dictionaries and `Theme.t(...)`.
- **Central Hub & Control Center (`VisualConfigPanel.qml` / `Super + I`)**: **20 comprehensive configuration tabs** covering display refresh rates (144Hz/60Hz), FreeSync/VRR, Kitty terminal parameters, Fastfetch animated GIFs, Mako notifications, system repair actions, Discord shortcut binds, shell customization, app store, and theme presets.

### Theming & Dynamic Colors
- **Wallust Palette Engine**: Dynamic color palette extracted directly from the active wallpaper. Automatically updates Hyprland window borders, Quickshell UI surfaces, and Kitty terminal colors without requiring session restarts.
- **Waywallen Integration**: Animated Wallpaper Engine scenes via Flatpak and a native layer-shell bridge. Wallpapers automatically pause when any application is in fullscreen to guarantee zero resource waste during games or video playback.
- **Wallpaper Switcher (`Super + S`)**: Interactive carousel selector to browse and apply installed wallpapers instantly.

### Architecture & GPU Orchestration
- **Mesa iGPU Compositor**: Hyprland and Quickshell run on the integrated Intel GPU to eliminate inter-GPU copy overhead and maintain rock-solid frametimes at 144Hz.
- **On-Demand NVIDIA dGPU (`prime-run`)**: Heavy 3D applications and games invoke the dedicated NVIDIA RTX GPU on demand.
- **Hardware Screen Recording (`Recording.qml`)**: Integrated recording studio leveraging NVENC hardware acceleration (`h264_nvenc`) with independent system audio and microphone capture via PipeWire.
- **Safe Coexistence**: Completely isolated configuration paths. Runs cleanly alongside KDE Plasma or GNOME without conflicting with existing desktop environments.

---

## Keybindings

| Shortcut | Description |
|---|---|
| `Super` or `Super + R` | Toggle Application Launcher |
| `Super + Q` | Open Kitty Terminal |
| `Super + E` | Open Dolphin File Manager |
| `Super + I` | Open Control Center / Settings Hub (20 Categories) |
| `Super + F1` | Keybindings Cheatsheet |
| `Super + V` | Native Clipboard History |
| `Super + W` | Toggle Desktop Widgets Edit Mode |
| `Super + S` | Open Wallpaper Switcher |
| `Super + B` | Toggle Compositor Blur |
| `Super + Shift + B` | Toggle Ultra-Performance Mode (Blur & Animations OFF) |
| `Super + '` | Toggle Dropdown Terminal (*Dropterm*) |
| `Super + L` | Lock Screen (`hyprlock`) |
| `Super + M` | Exit Hyprland Session |
| `Alt + Tab` | Live Window Switcher |
| `Print` or `Super + Shift + S` | Region Screenshot (Saves to pictures, copies to clipboard & notifies) |
| `Super + Alt + S` | Interactive Screenshot with Annotation (Swappy) |
| `Super + Shift + R` | Record Selected Screen Region |
| `Super + Ctrl + Shift + R` | Record Entire Display |
| `Super + Shift + C` | Color Picker (`hyprpicker`) |
| `Super + Shift + X` | Force Kill Unresponsive Window (`hyprctl kill`) |
| `Super + Ctrl + R` | Emergency Reload Quickshell Shell |
| `Ctrl + Shift + M` | Toggle Discord / Vesktop Mute in background |
| `Num_Lock` or `Ctrl + Shift + D` | Toggle Discord / Vesktop Deafen in background |
| `Media Keys` | Volume, Brightness, Microphone Mute, Play/Pause |

---

## Installation

### Requirements
- **OS:** Arch Linux or CachyOS
- **GPU:** Intel / AMD / NVIDIA (Hybrid GPU fully supported)
- **Display Server:** Wayland

### Quick Setup
Clone the repository and run the automated cyberpunk installer:

```bash
git clone https://github.com/Valcones47/hollow-wired.git
cd hollow-wired
chmod +x install.sh
./install.sh
```

The installer features an interactive **cyberpunk terminal UI** with animated **Serial Experiments Lain** ASCII transitions via `chafa`. It installs only the necessary ricing components (Hyprland, Quickshell, Wallust, audio, portals, and helpers), completely delegating GPU drivers and gaming packages to CachyOS/Arch Linux for maximum stability.

> **Note for KDE Plasma / GNOME Users:**  
> Testing `hollow-wired` will **not** modify or break your existing desktop configuration. When prompted to configure SDDM/Limine during installation, simply select **N** (default). Afterward, log out of your current session and choose **Hyprland** from your display manager's session menu.

---

## Dotfiles Updater

`hollow-wired` includes a built-in, non-destructive update system:

```bash
rice-update
```

- **Update Detection**: Background checks quietly query the upstream repository for new commits.
- **UI Notifications**: When updates are available, the update badge in the **Energy Sidebar** and **Control Center** highlights the new commit count.
- **Automated Backup**: Applying updates creates an automatic timestamped backup in `~/.config/rice-backup-<timestamp>`, pulls changes, syncs configurations, and hot-reloads Quickshell in place without interrupting open windows.

---

## Repository Structure

```
hollow-wired/
├── dots/
│   ├── hypr/                 # Hyprland configuration (hyprland.lua, hyprlock, hypridle)
│   ├── quickshell/           # Native desktop shell (TopBar, Launcher, Dock, Hub, Widgets)
│   ├── kitty/                # Kitty terminal configuration
│   ├── wallust/              # Dynamic palette templates and color schemes
│   ├── xdg-desktop-portal/   # Wayland portal rules (KDE Breeze Dark file picker)
│   ├── fastfetch/            # System fetch configuration and custom ASCII/GIFs
│   ├── applications/         # Desktop shortcut definitions (.desktop)
│   └── bin/                  # Helper CLI utilities (rice-update, rice-record, etc.)
├── packaging/                # Turnkey PKGBUILD & AUR installation recipes
├── quickshell-progress/      # Interface captures and preview media
├── install.sh                # Interactive automated installer
└── README.md                 # Project documentation
```

---

## License

Distributed under the [GPL-3.0 License](LICENSE).
