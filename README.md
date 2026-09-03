# Clipboard Plus

> **Fork note.** This fork adds a **text transform chooser** — see
> [Text transforms](#text-transforms). Everything else is upstream
> [idr4n/omarchy-clipboard-plus](https://github.com/idr4n/omarchy-clipboard-plus).

A keyboard-first overlay for Omarchy Quattro's clipboard history, with type
filters, large text and image previews, color swatches, and inline text
editing.

![Clipboard Plus overlay](preview.png)

Clipboard Plus is a UI companion to Omarchy's built-in `omarchy.clipboard`
plugin. It reads the same resident history and uses Omarchy's clipboard
helpers, so it does not start another `wl-paste` watcher or Quickshell process.

## Features

- Search clipboard history by typing
- Navigate with the arrow keys or `Ctrl+J` / `Ctrl+K`
- Filter all entries, text, images, or six-digit hexadecimal colors
- Preview long text, images, and detected colors without leaving the overlay
- Edit text before copying or pasting it
- Transform an entry's case from a chooser: Title, Sentence, UPPER, lower, slug
- Paste, copy, open, remove, or clear history entries from the keyboard
- Follow the active Omarchy theme through the shell's shared UI components

## Requirements

- Omarchy Quattro
- The built-in `omarchy.clipboard` plugin enabled, which is the Omarchy default
- Omarchy's standard clipboard history and helper commands

No additional packages, services, or background processes are required.

## Install

```sh
omarchy plugin add https://github.com/idr4n/omarchy-clipboard-plus.git --enable
```

Clipboard Plus is an overlay and does not install a keybinding. To place it on
`SUPER+CTRL+V` while retaining the stock clipboard on
`SUPER+CTRL+SHIFT+V`, add this to `~/.config/hypr/bindings.lua`:

```lua
hl.unbind("SUPER + CTRL + V")
o.bind(
  "SUPER + CTRL + V",
  "Clipboard Plus",
  "omarchy-shell shell toggle io.github.idr4n.clipboard-plus"
)
o.bind(
  "SUPER + CTRL + SHIFT + V",
  "Clipboard",
  "omarchy-shell shell toggle omarchy.clipboard"
)
```

Apply and validate the binding:

```sh
hyprctl reload
hyprctl configerrors
```

The overlay intentionally uses Omarchy's `omarchy-clipboard` layer-shell
namespace so the stock no-animation rule also applies to Clipboard Plus. The
plugin IDs remain separate; this only shares the compositor rule.

## Keyboard controls

| Key | Action |
| --- | --- |
| Type | Filter entries |
| `Up` / `Down`, `Ctrl+K` / `Ctrl+J` | Move selection |
| `Page Up` / `Page Down`, `Home` / `End` | Move through history |
| `Enter` | Paste the selected entry |
| `Shift+Enter` | Copy without pasting |
| `Alt+Enter` | Open with Omarchy's clipboard opener |
| `Ctrl+Space` | Open or close the expanded preview |
| `Ctrl+E` | Edit the selected text entry |
| `Ctrl+1` / `2` / `3` / `4` | Show all / text / images / colors |
| `Ctrl+T` / `Ctrl+Shift+T` | Cycle filters forward / backward |
| `Alt+T` | Open the transform chooser for the selected text entry |
| `Alt+U` / `Alt+L` / `Alt+K` | Apply UPPERCASE / lowercase / slug-case directly |
| `Ctrl+R` | Reload history from disk |
| `Delete` | Remove the selected history entry |
| `Shift+Delete` | Confirm clearing all history |
| `Escape` | Clear the search, close a detail view, or close the overlay |

In the text editor:

- `Ctrl+Enter` pastes the edited text.
- `Ctrl+Shift+Enter` or `Ctrl+S` copies the edited text.
- `Escape` cancels editing.

## Text transforms

`Alt+T` on a selected text entry opens a chooser that rewrites the text and
pastes it, without opening the editor:

| Key | Transform |
| --- | --- |
| `T` | Title Case |
| `S` | Sentence case |
| `U` | UPPERCASE |
| `L` | lowercase |
| `K` | slug-case |

Given this on the clipboard:

```
draft the release notes

and a migration guide

a final pass before shipping
```

Title Case gives:

```
Draft the Release Notes

And a Migration Guide

A Final Pass Before Shipping
```

Watch `a`: lowercase inside the second line, capitalised at the start of the
third. The first/last-word rule applies per line rather than across the whole
text, and blank lines and line breaks are preserved. slug-case flattens the
same input to `draft-the-release-notes-and-a-migration-guide-a-final-pass-before-shipping`.

Each row previews the result against the entry you actually have selected, so
the choice is visible rather than remembered. Navigate with the arrow keys or
`Ctrl+J` / `Ctrl+K` and press `Enter`, or press a letter to pick outright.
`Escape` cancels. `Alt+U`, `Alt+L` and `Alt+K` skip the chooser.

The same transforms are available inside the editor (`Ctrl+E`) as `Ctrl+T`,
`Ctrl+Shift+T`, `Ctrl+U`, `Ctrl+L` and `Ctrl+K`. There they apply to the
selection when there is one, so a single word or line can be recased without
touching the rest; otherwise they rewrite the whole buffer. The cursor and
selection are preserved, so the keys can be pressed repeatedly.

### Title case rules

Title case follows AP style rather than naively capitalising every word:

- Minor words (`a`, `of`, `the`, `from`, …) stay lowercase unless they land
  first or last: `A Tale of Two Cities`.
- ALL-CAPS words are treated as acronyms and survive: `Using the NASA API for a
  SQL Query`. Input that is entirely uppercase is treated as shouting and
  normalised instead, so `MEETING NOTES` becomes `Meeting Notes`.
- Compounds keep the minor-word rule after the first part:
  `state-of-the-art` becomes `State-of-the-Art`, not `State-Of-The-Art`.

Slug-case folds accented Latin to ASCII (`Café Münster` becomes
`cafe-munster`) using an explicit map rather than `String.normalize`, which is
not guaranteed across the QML JavaScript engines this may run on.

Transforms live in `TextTransforms.js`, a `.pragma library` with no Qt types
and no shell calls, so it can be exercised outside the shell with any
JavaScript runtime.

## Privacy and permissions

Clipboard Plus runs unsandboxed inside the existing Omarchy shell, as all
Omarchy shell plugins do. It can therefore read clipboard contents, which may
contain sensitive information.

The plugin:

- reads and updates `~/.local/state/omarchy/clipboard-history.json`;
- refuses raw history files over 4 MiB before JSON parsing and retains the
  first 300 disk positions;
- represents individual text entries over 1,048,576 code units as
  metadata-only rows that preserve their disk indices for paste, copy, and
  open while keeping their contents out of search, preview, and editing;
- keeps plugin writes disabled while any oversized placeholder would remain;
  the last one can be deleted directly, while multiple require clearing
  history or removing them with the stock clipboard manager;
- caps aggregate retained text at 4,194,304 code units and rejects
  modifications that would exceed the cap instead of silently dropping entries;
- validates persisted image-entry paths and MIME types before loading previews;
- invokes Omarchy's packaged `omarchy-clipboard-paste-text`,
  `omarchy-clipboard-paste-file`, and `omarchy-clipboard-open` helpers;
- stores edited text as a new stock-format history entry and invokes it by
  history index, so edited clipboard contents are not exposed through process
  arguments;
- makes no network requests;
- requests no elevated privileges; and
- starts no persistent watcher, service, installer, or second Quickshell
  instance.

Removing or clearing entries modifies the history shared with the stock
clipboard manager.

## Remove

First remove the Clipboard Plus binding block from
`~/.config/hypr/bindings.lua` and reload Hyprland. Omarchy's stock
`SUPER+CTRL+V` binding will then be restored from its default configuration.

Remove the plugin:

```sh
omarchy plugin remove io.github.idr4n.clipboard-plus
```

## Development

Run the manifest validator, QML linter, and model tests from the repository
root:

```sh
omarchy plugin validate .
qmllint -I "$OMARCHY_PATH/shell" Clipboard.qml
node tests/clipboard-history.js
```

Before releasing, also exercise open, close, paste, copy, edit, disable,
re-enable, shell restart, and removal against a current Omarchy Quattro
installation.

## Acknowledgements

Clipboard Plus is derived from Omarchy's stock clipboard history model and
overlay, then extended with filtering, expanded previews, and text editing.
The stock Omarchy clipboard
[implementation](https://github.com/basecamp/omarchy/tree/quattro/shell/plugins/clipboard)
is MIT-licensed; `LICENSE` retains its upstream copyright notice.

## License

[MIT](LICENSE)
