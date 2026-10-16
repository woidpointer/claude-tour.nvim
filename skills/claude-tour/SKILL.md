---
name: claude-tour
description: Show explanations of code as a guided tour in the user's running Neovim, with notes above the lines, a sign bar over the explained range and a quickfix overview (claude-tour.nvim). Use when the user asks to show, mark or explain code places "in nvim", "im Editor", "zeig mir das im Code", asks for a tour, a walkthrough or overlays, gives a Neovim server socket such as /tmp/*.sock, or mentions :ClaudeTour or claude-tour. Do NOT use for plain chat explanations when the user has no Neovim open.
license: MIT
metadata:
  author: woidpointer
---

# claude-tour: explain code inside the user's Neovim

You write a tour file. The plugin claude-tour.nvim shows each step as notes above the code, a sign bar over the
lines the step explains, and the step number `[i/n]`. The user steps with their own keys. You never change
source files.

## Rules

- Ask the user for the Neovim server socket path. Do not guess it. You may list candidates with
  `ls /tmp/*.sock` and ask which one to use.
- Before the first load, check that the plugin is loaded (see "Check the plugin"). If it is not, stop and tell
  the user; do not inject the plugin code.
- Verify every line number against the file before you write the tour. Read the lines; do not use numbers from
  memory, from an old diff or from a summary.
- Write the note text in the language of the chat. Keep each line short; the first line of a step is the
  summary that the quickfix list shows.
- Do not number the steps in the text. The plugin adds `[i/n]`.
- Order the steps in reading order, not in file order.
- When the code changed since you wrote a tour, read the places again and write the tour again. Do not patch
  single line numbers.

## Tour file

Write the tour to `~/develop/claude-tours/<name>.json` (the plugin's default `tour_dir`). `<name>` is short
and describes the topic, for example `simple_app` or `pipeline-clang-format`.

```json
{
  "title": "simple_app",
  "root": "/abs/path/to/project",
  "steps": [
    {
      "file": "src/main.cpp",
      "line": 126,
      "text": [
        "Start: creates 128 values and 128 measurements.",
        "Next: measurables.h:107 (constructor)"
      ]
    },
    {
      "file": "include/measurables.h",
      "line": 101,
      "end_line": 105,
      "text": ["Fold over all indices: ..."]
    }
  ]
}
```

| Field      | Rule                                                                                                                              |
| ---------- | --------------------------------------------------------------------------------------------------------------------------------- |
| `root`     | Absolute path. `file` paths are relative to it.                                                                                   |
| `line`     | First line the step is about (integer, starts at 1). The note appears above it.                                                   |
| `end_line` | Last line of the explained range. Set it for every step that explains more than one line, for example a whole function or a loop. |
| `text`     | List of strings. First string = summary.                                                                                          |

Write one step per line in the JSON file, so the user can read and diff it.

## Check the plugin

```bash
nvim --server <socket> --remote-expr 'exists(":ClaudeTourLoad")'
```

`2` means loaded. `0` means not loaded: tell the user to install claude-tour.nvim.

## Load and show the tour

```bash
nvim --server <socket> --remote-expr \
  "luaeval('(function(n) local t = require(\"claude_tour\"); local ok = t.load_file(n); if ok then t.quickfix(); t.next() end; return ok end)(_A)', '<name>')"
```

The result `true` means the tour is loaded, the quickfix list is open and the cursor is on step 1. Then tell the
user in one line which tour is open and how many steps it has. Mention the commands only if the user does not
know them: `:ClaudeTourNext`, `:ClaudeTourPrev`, `:ClaudeTourToggle`, `:ClaudeTourQf`, `:ClaudeTourClear`.

Loading a tour replaces the tour that is loaded. To show another tour again later, load its file again.

## Limits to tell the user when they matter

- When Neovim reads a file of the tour again (`:e!`, `autoread`, open after `:bdelete`), the plugin sets the
  notes of that file again from the lines in the tour. Edits made after loading are lost for these notes.
- A tour that the user opens later, after the code changed, can point to wrong lines. Offer to write it again.
- With `signcolumn=yes`, gitsigns and diagnostics hide the tour sign on their lines. `signcolumn=yes:2` shows
  both.

For all options and commands: `:help claude-tour` in Neovim, or `doc/claude-tour.txt` in the plugin repository.
