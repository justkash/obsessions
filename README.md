# obsessions.nvim

Session management for Neovim, written in [Fennel](https://fennel-lang.org/) and built with [Nix Flakes](https://nixos.wiki/wiki/Flakes).

Obsessions lets you create, save, switch between, and restore project sessions — including window layouts, terminal buffers, cursor positions, marks, jump lists, and more.

## Features

- **Full state capture**: cwd, tabs, windows, splits, buffer order, cursor positions, marks (local + global), jump lists, change lists, location lists, and terminal positions
- **Live terminal preservation**: terminal buffers keep running in the background when switching sessions within the same Neovim instance
- **Lazy buffer loading**: large sessions restore instantly by loading only visible buffers upfront; the rest load on first access (with named stubs visible in `:ls`)
- **Atomic saves**: writes go to a temp file first, then atomically rename into place — no half-written session files
- **Concurrent safety**: advisory locking prevents two Neovim instances from writing to the same session; different instances can work on different sessions
- **Autosave**: configurable periodic saves + automatic save on `VimLeavePre`
- **Abstract picker**: works with Telescope, fzf-lua, or plain `vim.ui.select` — bring your own fuzzy finder
- **New sessions start with a terminal**: configurable layout (fullscreen, bottom split, or right split)
- **MessagePack storage**: fast, compact session files using Neovim's built-in `vim.mpack`
- **Built with Fennel**: compiled to Lua at build time via Nix — zero runtime dependency on Fennel

## Requirements

- Neovim ≥ 0.10
- (Optional) [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) or [fzf-lua](https://github.com/ibhagwan/fzf-lua) for fuzzy picking

## Installation

### With Nix Flakes (recommended)

Add the flake to your inputs and include the package in your Neovim plugin list:

```nix
# flake.nix
{
  inputs.obsessions.url = "github:your-user/obsessions.nvim";

  # In your NixOS or home-manager config:
  # Add to neovim extraPlugins:
  # inputs.obsessions.packages.${system}.default
}
```

Then in your Neovim config (Lua):

```lua
require("obsessions").setup({
  -- see Configuration below
})
```

### With NixVim

Import the NixVim module from the flake:

```nix
# flake.nix
{
  inputs.obsessions.url = "github:your-user/obsessions.nvim";
}

# In your NixVim config:
{
  imports = [ inputs.obsessions.nixvimModules.default ];

  programs.obsessions = {
    enable = true;
    restoreLastSession = true;
    autosaveInterval = 300;
    picker = "auto";        # "auto" | "telescope" | "fzf_lua" | "select"
    lazyLoadBuffers = true;
    newSessionLayout = "fullscreen"; # "fullscreen" | "bottom" | "right"
    # storagePath = "/custom/path"; # optional
  };
}
```

### With lazy.nvim (non-Nix)

First, build the Lua files from Fennel. You need the `fennel` CLI installed:

```bash
cd obsessions.nvim
find src -name '*.fnl' -print0 | while IFS= read -r -d '' src; do
  rel="${src#src/}"
  dest="lua/${rel%.fnl}.lua"
  mkdir -p "$(dirname "$dest")"
  fennel --compile "$src" > "$dest"
done
```

Then add to lazy.nvim:

```lua
{
  dir = "/path/to/obsessions.nvim",
  config = function()
    require("obsessions").setup()
  end,
}
```

### Development shell

```bash
nix develop
# Gives you the Fennel compiler in PATH
# Test compilation:
fennel --compile src/obsessions/init.fnl
# Test plugin locally:
nvim --cmd 'set rtp+=.'
```

## Configuration

All options with their defaults:

```lua
require("obsessions").setup({
  ["storage-path"] = vim.fn.stdpath("data") .. "/obsessions",
  ["autosave-interval"] = 300,       -- seconds; 0 to disable
  ["restore-last-session"] = false,  -- restore last session on VimEnter
  ["picker"] = "auto",              -- "auto" | "telescope" | "fzf_lua" | "select"
  ["lazy-load-buffers"] = true,     -- named stubs in :ls, load on access
  ["new-session-layout"] = "fullscreen", -- "fullscreen" | "bottom" | "right"
  ["new-session-terminal-height"] = 15,  -- for "bottom" layout
  ["new-session-terminal-width"] = 80,   -- for "right" layout
  ["lock-timeout"] = 5000,              -- ms to wait for write lock
  ["picker-keymaps"] = {                -- keys handled inside the picker
    delete = "<C-d>",
    rename = "<C-r>",
  },
})
```

## Commands

| Command | Description |
|---|---|
| `:ObsessionsNew <name>` | Create a new session (opens terminal) |
| `:ObsessionsSave [name]` | Save current session (defaults to active session name) |
| `:ObsessionsLoad <name>` | Load a session by name |
| `:ObsessionsSwitch [name]` | Save current + load target (opens picker if no name) |
| `:ObsessionsDelete <name>` | Delete a session (with confirmation) |
| `:ObsessionsRename [<old> <new>]` | Rename a session (opens picker if no args) |
| `:ObsessionsList` | List all saved sessions |
| `:ObsessionsPick [action]` | Open session picker (action: switch/load/delete/rename) |

All commands that accept a session name support tab completion.

## Lua API

```lua
local obs = require("obsessions")

obs.save("my-project")          -- save current state
obs.load("my-project")          -- load a session
obs.create("new-project")       -- create new session with terminal
obs.switch("other-project")     -- save current + switch
obs.delete("old-project")       -- delete with confirmation
obs.rename("old", "new")        -- rename a session
obs.list()                      -- returns { {name, path, mtime}, ... }
obs.current()                   -- returns active session name or nil
obs.pick("switch")              -- open fuzzy picker
```

## Picker integration

Obsessions auto-detects your fuzzy finder. You can also force a specific one:

```lua
require("obsessions").setup({ picker = "telescope" })
```

### Custom picker

You can implement your own picker by creating a module that exports a `pick(opts)` function:

```lua
-- opts.sessions: list of {name, path, mtime}
-- opts.prompt: string
-- opts.action: "switch" | "load" | "delete"
-- opts.on_select: function(name) to call when user picks a session
```

### Picker keymaps

When using the Telescope or fzf-lua picker:

- `<CR>` performs the picker's action (switch / load / delete / rename)
- `<C-d>` deletes the selected session (after confirmation)
- `<C-r>` renames the selected session (prompts for the new name)

The delete and rename keys are configurable via `picker-keymaps`:

```lua
require("obsessions").setup({
  ["picker-keymaps"] = {
    delete = "<C-x>",
    rename = "<C-e>",
  },
})
```

Keys are given in Vim notation (e.g. `<C-x>`); the fzf-lua adapter translates
them to fzf-style keys (`ctrl-x`) automatically. The `vim.ui.select` fallback
does not support extra keymaps — use Telescope or fzf-lua for those.

## Session data

Sessions are stored as MessagePack files in the storage directory (default: `~/.local/share/nvim/obsessions/`). Each session is a single `.msgpack` file.

Captured state includes:
- Working directory (global)
- All tab pages with their ordering
- Window layout tree (splits, sizes, positions) per tab
- Active window and active tab
- Buffer list with ordering
- Per-buffer: file path, filetype, cursor position, local marks (a-z), change list
- Global marks (A-Z)
- Jump list
- Location list per window
- Terminal buffer positions and live terminal identities

When switching sessions inside a running Neovim instance, terminal buffers owned
by background sessions are hidden instead of deleted, so their jobs keep running.
When the Neovim process exits, those jobs exit with Neovim as usual. Loading a
saved session in a fresh Neovim instance still opens fresh terminal buffers in
the saved splits.

## Architecture

```
plugin/
└── obsessions.lua      # Command registration sourced by Neovim
src/
└── obsessions/
    ├── init.fnl        # setup() and public API
    ├── config.fnl      # configuration defaults and merging
    ├── session.fnl     # save/load/create/delete/switch orchestration
    ├── state.fnl       # Neovim state capture and restore
    ├── storage.fnl     # MessagePack I/O with atomic writes
    ├── lock.fnl        # Advisory locking (mkdir-based + PID ownership)
    ├── autosave.fnl    # Periodic timer + VimLeavePre hook
    ├── lazy.fnl        # Lazy buffer loading via BufReadCmd autocmds
    ├── picker.fnl      # Abstract picker with auto-detection
    └── pickers/
        ├── telescope.fnl  # Telescope adapter
        ├── fzf_lua.fnl    # fzf-lua adapter
        └── select.fnl     # vim.ui.select fallback
```

## License

MIT
