# Getting started

## After installing

1. Log out and pick **Hyprland** in your login screen.
2. The welcome guide opens on the first login. It walks through the layout,
   the window style and the lock screen. Reopen it any time with `Super + F1`.
3. Open the **settings panel** with `Super + I`. Everything the rice offers is
   there, grouped by topic; the search box at the top finds an option by name.

## The pieces on screen

| Piece | What it does | How to open |
|---|---|---|
| **Bar** | Workspaces, clock, media, network, sound/brightness/battery | Always on (can auto-hide) |
| **Hub** | Dashboard, media, performance, workspaces, notifications, recording, agenda | Click the clock |
| **Control center** | Wi-Fi, VPN, Bluetooth, do-not-disturb, blur, night light, volume per app, battery | Click the sound/battery block on the bar |
| **Dock** | Pinned and open apps | Bottom edge of the screen |
| **Launcher** | Apps, open windows, settings and files | `Super` (tap) or `Super + R` |
| **Sidebar** | Tray icons, updates, recording, power | Right edge, or `Ctrl + Alt + Del` if set to "sidebar" |

## Arranging the interface

Right-click an empty part of the bar (or right-click the desktop → **Edit
mode**). Right-click the bar again to leave. In edit mode you can:

- drag the bar to another edge, and drag items to reorder them;
- add or remove bar items (weather, color picker, screenshot, clipboard…);
- move desktop widgets and dock icons;
- pick a ready-made layout (for example **Windows style**: dock with a tray on
  the right, no sidebar).

## The launcher

Type to search apps. The same box does more:

| Start with | Does |
|---|---|
| (nothing) | Apps, then open windows, settings pages and files matching the text |
| `=` | Calculator (`= 25 * 4`); Enter copies the result |
| `:` | Emoji by name (`:fire`, `:fogo`); Enter pastes it |
| `>` | Runs a command in a terminal (`> btop`); Shift + Enter runs it in the background |
| `/` or `~` | Browses folders; Tab goes into a folder |

## Colors and theme

The colors come from the wallpaper (`Super + S` to change it). In
**Settings → Colors & Wallpaper** you can lock the palette, change single
colors, and switch between **dark, light or automatic** (light during the day,
dark at night).

## Your data

Everything you choose lives in `~/.config` (mostly `~/.config/hollow-wired`,
`~/.config/quickshell` and `~/.config/hypr`). Updates never overwrite those
files, and going back to an older version keeps them too.
