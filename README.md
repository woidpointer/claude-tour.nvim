# claude-tour.nvim

Show a guided tour through code as notes above the lines in Neovim. You step through the notes in a fixed
order, and you can show or hide them at any time. The notes never change the files.

An agent such as Claude Code writes the tour. You read it in your editor.

```
┃ [1/14] Start: creates 128 uint32 values and 128 measurements.
┃        Next: measurables.h:107 (constructor)
┃  126   auto vars = measurable::Measurables<std::uint32_t, 128U>::Initialize();
```

## How it works

Each step of a tour points to a file and a line and has one or more lines of text. The plugin puts each
step as an extmark with virtual lines above that line. A sign in the sign column marks the lines that the
step explains, from `line` to `end_line`. By default the note starts in the leftmost screen column, so its
`┃` and the signs below it form one line (option `leftcol`). The current step uses the highlight group `ClaudeTourCurrent`,
all other steps use `ClaudeTourNote`.

When the cursor is in the lines of a step, that step becomes the current step. This also works for jumps
from the quickfix list.

When you edit a file, the notes move with the code. `:ClaudeTourSave` writes the positions they have now.
When Neovim reads a file of the tour again (reload after a change on disk, or open again after `:bdelete`),
the plugin sets the notes of that file again from the lines in the tour. Edits made since the tour was
loaded are lost for these notes.

## Requirements

Neovim 0.10 or later.

## Installation

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "woidpointer/claude-tour.nvim",
  opts = {
    -- tour_dir = vim.fn.expand("~/develop/claude-tours"),
  },
}
```

For a local checkout, use `dir = "/path/to/claude-tour.nvim"` instead of the repository name.

## Commands

| Command | Action |
| --- | --- |
| `:ClaudeTourLoad {name}` | Load a tour from a JSON file. |
| `:ClaudeTourSave {name}` | Save the loaded tour with the current positions of its notes. |
| `:ClaudeTourNext` | Jump to the next step and make it the current step. |
| `:ClaudeTourPrev` | Jump to the previous step. |
| `:ClaudeTourGoto {n}` | Jump to step `n`. |
| `:ClaudeTourToggle` | Show or hide all notes. |
| `:ClaudeTourQf` | Put one entry per step into the quickfix list and open it. |
| `:ClaudeTourClear` | Remove the tour. |

`{name}` without a `/` is a file in `tour_dir`. The plugin adds `.json` unless the name ends in `.json`.
Both commands complete the names of the tours in `tour_dir` and file names.

The plugin defines no key mappings. Example:

```lua
vim.keymap.set("n", "]n", "<cmd>ClaudeTourNext<cr>", { desc = "Next tour step" })
vim.keymap.set("n", "[n", "<cmd>ClaudeTourPrev<cr>", { desc = "Previous tour step" })
vim.keymap.set("n", "<leader>tt", "<cmd>ClaudeTourToggle<cr>", { desc = "Toggle tour notes" })
vim.keymap.set("n", "<leader>tq", "<cmd>ClaudeTourQf<cr>", { desc = "Tour steps in quickfix" })
```

## Tour format

A tour is a JSON file or a Lua table with the same fields:

```json
{
  "title": "simple_app",
  "root": "/abs/path/to/project",
  "steps": [
    {"file": "src/main.cpp", "line": 126, "text": ["Start: ...", "Next: measurables.h:107"]},
    {"file": "include/measurables.h", "line": 101, "end_line": 105, "text": "Fold over all indices: ..."}
  ]
}
```

| Field | Meaning |
| --- | --- |
| `title` | Name of the tour. It is shown in the quickfix title. Default: `claude-tour`. |
| `root` | Directory for relative `file` paths. Default: the current working directory at load time. |
| `steps[].file` | Absolute path, or path relative to `root`. |
| `steps[].line` | Line number, starting at 1. A number past the end of the file goes to the last line. |
| `steps[].end_line` | Optional. Last line that the step explains. Default: `line`. |
| `steps[].text` | A string or a list of strings. The first string is the text in the quickfix list. |

The plugin puts `[i/n]` in front of the first line of each note. Do not number the steps in `text`.

## Load a tour from outside Neovim

Start Neovim with a server socket, for example `nvim --listen /tmp/nvim.sock`. Another program can then
load a tour file:

```bash
nvim --server /tmp/nvim.sock --remote-expr \
  "luaeval('require(\"claude_tour\").load_file(_A)', '/abs/path/tour.json')"
```

or a Lua file that returns the tour table:

```bash
nvim --server /tmp/nvim.sock --remote-expr \
  "luaeval('require(\"claude_tour\").load(dofile(_A))', '/abs/path/tour.lua')"
```

## Configuration

| Option | Default | Meaning |
| --- | --- | --- |
| `tour_dir` | `~/develop/claude-tours` | Directory for tour names without a path. |
| `prefix` | `"┃ "` | Text in front of each note line. |
| `leftcol` | `true` | `true`: a note starts in the leftmost screen column, above the sign column. `false`: a note starts in the text column. |
| `sign` | `"┃"` | Sign for the lines of a step. `false` shows no signs. |
| `sign_priority` | `5` | Priority of the sign. |

With `signcolumn=yes`, Neovim shows one sign per line: the sign with the highest priority. gitsigns uses
priority 6 and hides the tour sign on changed lines. Set `vim.o.signcolumn = "yes:2"` to see both.

## Help

`:help claude-tour` has the full reference: commands, tour format, options, highlight groups and the Lua API.

## License

MIT, see [LICENSE](LICENSE).
