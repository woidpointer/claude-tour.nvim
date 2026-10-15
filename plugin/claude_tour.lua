if vim.g.loaded_claude_tour then
  return
end
vim.g.loaded_claude_tour = true

local function tour()
  return require("claude_tour")
end

local function complete(arglead)
  return tour().complete(arglead)
end

local command = vim.api.nvim_create_user_command

command("ClaudeTourLoad", function(o)
  tour().load_file(o.args)
end, { nargs = 1, complete = complete, desc = "Load a tour from a JSON file" })

command("ClaudeTourSave", function(o)
  tour().save_file(o.args)
end, { nargs = 1, complete = complete, desc = "Save the tour with the current note positions" })

command("ClaudeTourToggle", function()
  tour().toggle()
end, { desc = "Show or hide the tour notes" })

command("ClaudeTourNext", function()
  tour().next()
end, { desc = "Jump to the next tour step" })

command("ClaudeTourPrev", function()
  tour().prev()
end, { desc = "Jump to the previous tour step" })

command("ClaudeTourGoto", function(o)
  tour().goto_step(tonumber(o.args))
end, { nargs = 1, desc = "Jump to tour step N" })

command("ClaudeTourQf", function()
  tour().quickfix()
end, { desc = "List the tour steps in the quickfix list" })

command("ClaudeTourClear", function()
  tour().clear()
end, { desc = "Remove the tour" })
