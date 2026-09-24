# FAQ and troubleshooting

### Something on screen froze or disappeared (bar, dock, panels)
Press `Super + Ctrl + R` to restart the shell. Windows stay open. If the bar is
gone for good, check **Settings → Interface Layout** (it may be
set to auto-hide or turned off).

### The wallpaper does not change / stays black
The wallpaper engine runs as a Flatpak. Open `Super + S` again and pick
another one; if it still fails, run the repair tool (below) — it restarts the
wallpaper service.

### Notifications stopped showing
The shell draws notifications itself; `mako` is the fallback. Check which one
is active:

```bash
rice-notif-daemon status
```

To switch to mako: **Settings → Notifications**, or `rice-notif-daemon set-provider mako`.
Do not disturb (`Super + Shift + N`) also hides them — they still land in the history.

### An update broke something — how do I go back?
**Settings → Programs & Updates → Go back to the previous version**, or:

```bash
rice-update rollback
```

It lists the backups made before each update and restores the one you pick.
Your own settings are kept, and the current state is saved first so the
rollback itself can be undone.

### How do I repair the rice?
**Settings → Programs & Updates → Find and fix problems** runs `rice-doctor`:
audio, GPU, wallpaper, notifications, broken settings files and services.

### I want the light theme
**Settings → Colors & Wallpaper → Theme**: Dark, Light or Automatic.

### My calendar events do not show in the Agenda
Open the Hub (click the clock) → **Agenda** → paste a `.ics` file path or a
calendar link (Google Calendar's "secret address in iCal format" works) and
press Enter. Links are refreshed every 30 minutes.

### Where are my settings stored?
In `~/.config/hollow-wired`, `~/.config/quickshell` and `~/.config/hypr`.
Updates never overwrite them.
