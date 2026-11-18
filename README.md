# ShellSwitcher

Switch between [Quickshell](https://quickshell.org) shells on Hyprland without a flash: every rice theme that runs
a Quickshell shell is a card (its name, the shell, its last look), and picking one swaps to it under a cover of
the desktop as it was, which fades away once the new shell is up.

It's the switcher for the `rice` theme switcher in my [dotfiles](https://github.com/BugzySleeps/bugzysdotfiles),
whose Quickshell rices are [liquid](https://github.com/BugzySleeps/liquid) and
[PureShell](https://github.com/BugzySleeps/PureShell). It runs on its own, apart from either shell, so it's still
there while one goes and the next comes.

## How it switches

1. Before it shows, a screenshot of the desktop as it is: the cover for the swap, and the current theme's card
   (kept in `~/.cache/rice/previews/`, so every card shows that shell as you last left it).
2. Pick a card: the cover comes up, so the screen looks unchanged, and `rice <theme>` swaps the theme and the
   shell underneath it.
3. Once the new shell answers (`qs -c <its config> ipc show`), the cover fades away and the switcher quits.

## Use it

```sh
qs -c switcher        # open it (the dotfiles bind it to SUPER + ALT + S); a second one does nothing
```

← → or Tab to choose (or the mouse), Enter or a click to switch, Esc or a click outside to close.

## Needs

- Quickshell (Qt 6.9+), Hyprland
- `rice` from the dotfiles (`rice list --json` for the themes, `rice <theme>` to switch)
- `grim` for the screenshots
- Google Sans Flex (in the dotfiles' `fonts/`)

## Licence

See [LICENSE](LICENSE): free to run and to change for yourself, not to copy into other projects or republish.
