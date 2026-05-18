-- obsessions.nvim - Vim command registration
-- This file is pure Lua (not Fennel) because it lives in plugin/ and is
-- sourced directly by Neovim before any require() calls.

local commands_created = false

local function setup_commands()
  if commands_created then
    return
  end

  local ok, obs = pcall(require, "obsessions")
  if not ok then
    vim.schedule(function()
      vim.notify("Obsessions: failed to load module: " .. obs, vim.log.levels.ERROR)
    end)
    return
  end

  vim.api.nvim_create_user_command("ObsessionsSave", function(args)
    local name = args.args ~= "" and args.args or nil
    local ok, err = obs.save(name)
    if not ok and err then
      vim.notify("Obsessions: " .. err, vim.log.levels.ERROR)
    end
  end, {
    nargs = "?",
    desc = "Save the current session (optionally with a name)",
    complete = function()
      local sessions = obs.list()
      local names = {}
      for _, s in ipairs(sessions) do
        table.insert(names, s.name)
      end
      return names
    end,
  })

  vim.api.nvim_create_user_command("ObsessionsLoad", function(args)
    if args.args == "" then
      vim.notify("Obsessions: session name required", vim.log.levels.ERROR)
      return
    end
    local ok, err = obs.load(args.args)
    if not ok and err then
      vim.notify("Obsessions: " .. err, vim.log.levels.ERROR)
    end
  end, {
    nargs = 1,
    desc = "Load a session by name",
    complete = function()
      local sessions = obs.list()
      local names = {}
      for _, s in ipairs(sessions) do
        table.insert(names, s.name)
      end
      return names
    end,
  })

  vim.api.nvim_create_user_command("ObsessionsNew", function(args)
    if args.args == "" then
      vim.notify("Obsessions: session name required", vim.log.levels.ERROR)
      return
    end
    local ok, err = obs.create(args.args)
    if not ok and err then
      vim.notify("Obsessions: " .. err, vim.log.levels.ERROR)
    end
  end, {
    nargs = 1,
    desc = "Create a new session with a terminal buffer",
  })

  vim.api.nvim_create_user_command("ObsessionsDelete", function(args)
    if args.args == "" then
      vim.notify("Obsessions: session name required", vim.log.levels.ERROR)
      return
    end
    obs.delete(args.args)
  end, {
    nargs = 1,
    desc = "Delete a session (with confirmation)",
    complete = function()
      local sessions = obs.list()
      local names = {}
      for _, s in ipairs(sessions) do
        table.insert(names, s.name)
      end
      return names
    end,
  })

  vim.api.nvim_create_user_command("ObsessionsRename", function(args)
    local parts = vim.split(args.args, "%s+", { trimempty = true })
    if #parts == 0 then
      obs.pick("rename")
    elseif #parts == 2 then
      local ok, err = obs.rename(parts[1], parts[2])
      if not ok and err then
        vim.notify("Obsessions: " .. err, vim.log.levels.ERROR)
      end
    else
      vim.notify("Obsessions: usage - :ObsessionsRename <old> <new>", vim.log.levels.ERROR)
    end
  end, {
    nargs = "*",
    desc = "Rename a session (opens picker if no name given)",
    complete = function()
      local sessions = obs.list()
      local names = {}
      for _, s in ipairs(sessions) do
        table.insert(names, s.name)
      end
      return names
    end,
  })

  vim.api.nvim_create_user_command("ObsessionsSwitch", function(args)
    if args.args ~= "" then
      obs.switch(args.args)
    else
      obs.pick("switch")
    end
  end, {
    nargs = "?",
    desc = "Switch to another session (opens picker if no name given)",
    complete = function()
      local sessions = obs.list()
      local names = {}
      for _, s in ipairs(sessions) do
        table.insert(names, s.name)
      end
      return names
    end,
  })

  vim.api.nvim_create_user_command("ObsessionsList", function()
    local sessions = obs.list()
    if #sessions == 0 then
      vim.notify("Obsessions: no saved sessions", vim.log.levels.INFO)
      return
    end
    local current = obs.current()
    local lines = {}
    for _, s in ipairs(sessions) do
      local marker = (current and s.name == current) and " *" or "  "
      local time = os.date("%Y-%m-%d %H:%M", s.mtime)
      table.insert(lines, string.format("%s %s  (%s)", marker, s.name, time))
    end
    vim.notify("Sessions:\n" .. table.concat(lines, "\n"), vim.log.levels.INFO)
  end, {
    desc = "List all saved sessions",
  })

  vim.api.nvim_create_user_command("ObsessionsPick", function(args)
    local action = args.args ~= "" and args.args or "switch"
    obs.pick(action)
  end, {
    nargs = "?",
    desc = "Open session picker (action: switch/load/delete)",
    complete = function()
      return { "switch", "load", "delete", "rename" }
    end,
  })

  commands_created = true
end

-- Defer command setup until after lazy loading completes
vim.api.nvim_create_autocmd("User", {
  pattern = "ObsessionsSetup",
  once = true,
  callback = setup_commands,
})

-- Also set up commands immediately if the plugin is loaded directly
-- (not through lazy.nvim or similar)
if vim.v.vim_did_enter == 1 then
  setup_commands()
else
  vim.api.nvim_create_autocmd("VimEnter", {
    once = true,
    callback = function()
      -- Small delay to ensure setup() has been called
      vim.defer_fn(setup_commands, 1)
    end,
  })
end
