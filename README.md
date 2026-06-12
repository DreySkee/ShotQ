# ShotQ

Menu bar app that archives every clipboard screenshot you take with the native
macOS shortcuts **⌃⇧⌘4** (selection → clipboard) and **⌃⇧⌘3** (full screen →
clipboard). Normally each new capture overwrites the previous one on the
clipboard; ShotQ saves every capture to disk before that happens.

## Install

Download the latest `ShotQ-x.y.z.dmg` from
[Releases](https://github.com/DreySkee/ShotQ/releases), open it, drag
**ShotQ** to **Applications**, then launch it.

The app is self-signed (not notarized), so Gatekeeper warns on first launch
of a downloaded copy:

1. If "ShotQ can't be opened" appears, go to System Settings → Privacy &
   Security, scroll down, and click **Open Anyway** (on older macOS,
   right-click the app → Open → Open also works).
2. Grant **Accessibility** when prompted (needed for batch paste on
   Ctrl+V/Cmd+V) — System Settings → Privacy & Security → Accessibility →
   enable ShotQ.
3. Allow access to the **Pictures** folder when the first screenshot is saved.

ShotQ registers itself as a login item on first launch, so it survives
reboots until you quit it from the menu.

## How it works

macOS itself takes the screenshot and puts it on the clipboard. ShotQ
polls `NSPasteboard.general.changeCount` (every 0.25 s) and, when new bare image
data appears — image flavors only, no file URL / HTML / text flavors, which is
the signature of a screenshot as opposed to an image copied from an app — it
writes a PNG to the vault:

```
~/Pictures/ShotQ/YYYY/MM/Screenshot 2026-06-12 at 14.03.22.png
```

Consecutive duplicates are skipped via SHA-256. Password-manager clipboard
entries (`org.nspasteboard.ConcealedType`) are always ignored. No Screen
Recording or Accessibility permission is needed — the OS performs the capture.

## Batch paste on Ctrl+V (terminals) and Cmd+V (everywhere else)

Captures accumulate in a "pending batch" (header shows the count). With a
non-empty batch:

- **Ctrl+V in a terminal** (Terminal, iTerm2, Warp, kitty, Alacritty, WezTerm,
  Ghostty, VS Code, Cursor) pastes *every* pending screenshot.
- **Cmd+V in any other app** does the same — but only while the clipboard
  still holds the most recent screenshot. Copy anything else first and Cmd+V
  is a normal paste; the batch stays queued for later.

A CGEventTap swallows the keystroke, then for each capture the app loads it
onto the clipboard and posts a synthetic paste keystroke, with a 400 ms gap so
the receiving app (e.g. Claude Code) reads each image before the clipboard is
swapped.

- Requires the **Accessibility** permission (System Settings → Privacy &
  Security → Accessibility). The menu shows a warning with an Open Settings
  button until granted.
- **Erase screenshots after paste** (default on): pasted captures are moved to
  the Trash and removed from the list once the batch has been delivered.
- With an empty batch, or in any non-terminal app, Ctrl+V is passed through
  untouched.
- Paste pacing is configurable:
  `defaults write dev.andrey.ShotQ pasteDelaySeconds -float 0.6`

## Menu bar UI

- Last 10 captures with thumbnails; pending-batch count in the header
- Per capture: ⧉ copy back to clipboard, 🔍 reveal in Finder, 🗑 move to Trash
- "Delete All" (click twice — second click confirms) moves the whole vault
  folder to the Trash as one recoverable item
- Pause/resume watching
- "Paste all on ⌃V in terminals" toggle (default on)
- "Erase screenshots after paste" toggle (default on)
- "Launch at login" toggle (`SMAppService`); auto-enabled on first launch
- Open Folder, Copy Paths, Quit

## Signing & diagnostics

`build.sh` signs with a self-signed keychain identity when available (falls
back to ad-hoc). The stable identity keeps the app's TCC grants
(Accessibility) valid across rebuilds; ad-hoc signing resets them each build.

Diagnostics append to `~/Library/Logs/ShotQ.log`: every clipboard
change with its pasteboard flavors and verdict, tap install status, every
Ctrl+V decision, saves, erases, deletes.

## Build from source

```sh
./build.sh
ditto build/ShotQ.app ~/Applications/ShotQ.app
open ~/Applications/ShotQ.app
```

Requires macOS 13+ and Xcode command line tools.
`tools/make_dmg.sh` builds the distributable DMG into `dist/`.

## Behavior notes

- First save may prompt for access to the Pictures folder — allow it.
- Survives reboot via login item registration; quitting from the menu keeps it
  quit until next login or manual relaunch.
- Known false positive: images copied from apps that provide *only* raw image
  data (e.g. a selection copied in Preview) are indistinguishable from
  screenshots and will be archived too. Use Pause, or delete strays from the
  vault folder.
