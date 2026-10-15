-- claude-tour.nvim: show a guided tour of notes as virtual lines above the code.
--
-- A tour is a list of steps. Each step points to a file and a line and has one or more lines of text.
-- The notes are extmarks, so they move with the code when you edit the file.
local M = {}

local ns = vim.api.nvim_create_namespace("claude_tour")

M.config = {
  -- Directory that :ClaudeTourLoad and :ClaudeTourSave use for a name without a path.
  tour_dir = vim.fn.expand("~/develop/claude-tours"),
  -- Prefix of each note line.
  prefix = "┃ ",
  -- true: a note starts in the leftmost screen column, so the first character of the prefix stands in the same
  -- column as the sign and both form one line. false: a note starts in the text column.
  leftcol = true,
  -- Sign that marks the lines a step explains (line .. end_line). Set to false to show no signs.
  sign = "┃",
  -- Priority of the sign. gitsigns uses 6; with 'signcolumn' "yes:2" both are visible.
  sign_priority = 5,
}

-- state.tour: the loaded tour (title, root, steps)
-- state.marks[i]: { buf = <bufnr>, id = <extmark id of the note>, signs = { <extmark id per line> } } of step i
-- state.current: index of the current step, 0 before the first step
-- state.visible: false hides the notes but keeps their positions
local state = { tour = nil, marks = {}, current = 0, visible = true }

local function set_highlights()
  vim.api.nvim_set_hl(0, "ClaudeTourCurrent", { link = "DiagnosticInfo", default = true })
  vim.api.nvim_set_hl(0, "ClaudeTourNote", { link = "Comment", default = true })
end

local function notify(msg, level)
  vim.notify("claude-tour: " .. msg, level or vim.log.levels.INFO)
end

local function is_absolute(path)
  return path:sub(1, 1) == "/"
end

local function resolve(root, file)
  if is_absolute(file) then
    return file
  end
  return root .. "/" .. file
end

-- The current position of step i as (buf, 0-based row), or nil.
local function position(i)
  local mark = state.marks[i]
  if not mark or not vim.api.nvim_buf_is_valid(mark.buf) then
    return nil
  end
  local pos = vim.api.nvim_buf_get_extmark_by_id(mark.buf, ns, mark.id, {})
  if #pos == 0 then
    return nil
  end
  return mark.buf, pos[1]
end

-- The current 0-based row of the last line that step i explains.
local function end_row(i)
  local mark = state.marks[i]
  local last = mark.signs[#mark.signs]
  local pos = last and vim.api.nvim_buf_get_extmark_by_id(mark.buf, ns, last, {}) or {}
  return pos[1]
end

-- Set (or update) the extmarks of step i at their current positions, with or without note text and signs.
local function render_step(i)
  local step = state.tour.steps[i]
  local buf, row = position(i)
  if not buf then
    return
  end
  local hl = (i == state.current) and "ClaudeTourCurrent" or "ClaudeTourNote"
  for _, sign_id in ipairs(state.marks[i].signs) do
    local pos = vim.api.nvim_buf_get_extmark_by_id(buf, ns, sign_id, {})
    if #pos > 0 then
      local sign_opts = { id = sign_id }
      if state.visible and M.config.sign then
        sign_opts.sign_text = M.config.sign
        sign_opts.sign_hl_group = hl
        sign_opts.priority = M.config.sign_priority
      end
      vim.api.nvim_buf_set_extmark(buf, ns, pos[1], 0, sign_opts)
    end
  end
  local opts = { id = state.marks[i].id }
  if state.visible then
    local lines = {}
    local number = ("[%d/%d] "):format(i, #state.tour.steps)
    for j, text in ipairs(step.text) do
      -- The step number goes in front of the first line, the other lines are indented to match.
      local lead = (j == 1) and number or (" "):rep(#number)
      table.insert(lines, { { M.config.prefix .. lead .. text, hl } })
    end
    opts.virt_lines = lines
    opts.virt_lines_above = true
    opts.virt_lines_leftcol = M.config.leftcol
  end
  vim.api.nvim_buf_set_extmark(buf, ns, row, 0, opts)
end

local function render()
  if not state.tour then
    return
  end
  for i = 1, #state.tour.steps do
    render_step(i)
  end
end

local function require_tour()
  if not state.tour then
    notify("no tour loaded", vim.log.levels.WARN)
    return false
  end
  return true
end

-- Check and normalize a tour table. Returns the tour or nil and an error message.
local function normalize(tour)
  if type(tour) ~= "table" or type(tour.steps) ~= "table" or #tour.steps == 0 then
    return nil, "a tour needs a non-empty 'steps' list"
  end
  local out = { title = tour.title or "claude-tour", root = tour.root or vim.fn.getcwd(), steps = {} }
  for i, step in ipairs(tour.steps) do
    if type(step.file) ~= "string" or type(step.line) ~= "number" then
      return nil, ("step %d needs 'file' (string) and 'line' (number)"):format(i)
    end
    local text = step.text
    if type(text) == "string" then
      text = { text }
    end
    if type(text) ~= "table" or #text == 0 then
      return nil, ("step %d needs 'text' (string or list of strings)"):format(i)
    end
    if step.end_line ~= nil and (type(step.end_line) ~= "number" or step.end_line < step.line) then
      return nil, ("step %d: 'end_line' must be a number >= 'line'"):format(i)
    end
    table.insert(out.steps, { file = step.file, line = step.line, end_line = step.end_line, text = text })
  end
  return out
end

local follow_group = vim.api.nvim_create_augroup("claude_tour_follow", { clear = true })

-- When the cursor is in the lines of a step, that step becomes the current step. This also covers jumps that
-- the plugin does not make itself, e.g. from the quickfix list. If the ranges of several steps overlap, the step
-- whose note is on the cursor line wins, otherwise the first step.
local function follow_cursor()
  if not state.tour or not state.visible then
    return
  end
  local buf = vim.api.nvim_get_current_buf()
  local row = vim.api.nvim_win_get_cursor(0)[1] - 1
  local found
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, { row, 0 }, { row, -1 }, {})) do
    for i, m in ipairs(state.marks) do
      if m.buf == buf then
        if m.id == mark[1] then
          found = i
          break
        elseif not found and vim.tbl_contains(m.signs, mark[1]) then
          found = i
        end
      end
    end
  end
  if found and found ~= state.current then
    state.current = found
    render()
  end
end

-- Remove the notes of the loaded tour.
function M.clear()
  for _, mark in ipairs(state.marks) do
    if vim.api.nvim_buf_is_valid(mark.buf) then
      pcall(vim.api.nvim_buf_del_extmark, mark.buf, ns, mark.id)
      for _, sign_id in ipairs(mark.signs) do
        pcall(vim.api.nvim_buf_del_extmark, mark.buf, ns, sign_id)
      end
    end
  end
  vim.api.nvim_clear_autocmds({ group = follow_group })
  state = { tour = nil, marks = {}, current = 0, visible = true }
end

-- Load a tour from a Lua table: { title = ..., root = ..., steps = { { file, line, text }, ... } }.
-- A relative 'file' is taken relative to 'root' (default: the current working directory).
function M.load(tour)
  local t, err = normalize(tour)
  if not t then
    notify(err, vim.log.levels.ERROR)
    return false
  end
  M.clear()
  state.tour = t
  for i, step in ipairs(t.steps) do
    local path = resolve(t.root, step.file)
    if vim.fn.filereadable(path) == 0 then
      notify(("step %d: cannot read %s"):format(i, path), vim.log.levels.WARN)
    end
    local buf = vim.fn.bufadd(path)
    vim.fn.bufload(buf)
    local count = vim.api.nvim_buf_line_count(buf)
    local row = math.max(0, math.min(step.line, count) - 1)
    local last = math.max(row, math.min(step.end_line or step.line, count) - 1)
    local id = vim.api.nvim_buf_set_extmark(buf, ns, row, 0, {})
    -- One extmark per line, so the sign of each line moves with that line.
    local signs = {}
    for r = row, last do
      table.insert(signs, vim.api.nvim_buf_set_extmark(buf, ns, r, 0, {}))
    end
    state.marks[i] = { buf = buf, id = id, signs = signs }
  end
  vim.api.nvim_create_autocmd({ "CursorMoved", "BufEnter" }, { group = follow_group, callback = follow_cursor })
  render()
  notify(("%s: %d steps loaded"):format(t.title, #t.steps))
  return true
end

-- Path of a tour file: a name without a path is looked up in config.tour_dir, ".json" is added if missing.
local function tour_path(name)
  local path = vim.fn.expand(name)
  if not path:match("%.json$") then
    path = path .. ".json"
  end
  if not is_absolute(path) and not path:find("/") then
    path = M.config.tour_dir .. "/" .. path
  end
  return vim.fn.fnamemodify(path, ":p")
end

function M.load_file(name)
  local path = tour_path(name)
  if vim.fn.filereadable(path) == 0 then
    notify("cannot read " .. path, vim.log.levels.ERROR)
    return false
  end
  local ok, tour = pcall(vim.json.decode, table.concat(vim.fn.readfile(path), "\n"))
  if not ok then
    notify("cannot parse " .. path .. ": " .. tour, vim.log.levels.ERROR)
    return false
  end
  return M.load(tour)
end

-- Save the loaded tour as JSON, with the current positions of the notes.
function M.save_file(name)
  if not require_tour() then
    return false
  end
  local root = state.tour.root
  local steps = {}
  for i, step in ipairs(state.tour.steps) do
    local buf, row = position(i)
    local file = buf and vim.api.nvim_buf_get_name(buf) or resolve(root, step.file)
    if file:sub(1, #root + 1) == root .. "/" then
      file = file:sub(#root + 2)
    end
    local entry = { file = file, line = row and row + 1 or step.line, text = step.text }
    if step.end_line then
      local last = buf and end_row(i)
      entry.end_line = last and last + 1 or step.end_line
    end
    table.insert(steps, entry)
  end
  -- One step per line keeps the file readable and easy to diff.
  local lines = {
    "{",
    '  "title": ' .. vim.json.encode(state.tour.title) .. ",",
    '  "root": ' .. vim.json.encode(root) .. ",",
    '  "steps": [',
  }
  for i, step in ipairs(steps) do
    table.insert(lines, "    " .. vim.json.encode(step) .. (i < #steps and "," or ""))
  end
  table.insert(lines, "  ]")
  table.insert(lines, "}")
  local path = tour_path(name)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  vim.fn.writefile(lines, path)
  notify("saved " .. path)
  return true
end

function M.toggle()
  if not require_tour() then
    return
  end
  state.visible = not state.visible
  render()
end

-- Jump to step i and make it the current step.
function M.goto_step(i)
  if not require_tour() then
    return
  end
  local n = #state.tour.steps
  if i < 1 or i > n then
    notify(("no step %d (1..%d)"):format(i, n), vim.log.levels.WARN)
    return
  end
  local buf, row = position(i)
  if not buf then
    notify(("step %d: its buffer is gone, load the tour again"):format(i), vim.log.levels.WARN)
    return
  end
  state.current = i
  state.visible = true
  render()
  if vim.bo.buftype == "quickfix" then
    vim.cmd("wincmd p")
  end
  vim.cmd("buffer " .. buf)
  vim.api.nvim_win_set_cursor(0, { row + 1, 0 })
  vim.cmd("normal! zz")
  vim.api.nvim_echo({ { ("[%d/%d] %s"):format(i, n, state.tour.steps[i].text[1]) } }, false, {})
end

function M.next()
  if require_tour() then
    if state.current >= #state.tour.steps then
      notify("last step reached")
      return
    end
    M.goto_step(state.current + 1)
  end
end

function M.prev()
  if require_tour() then
    if state.current <= 1 then
      notify("first step reached")
      return
    end
    M.goto_step(state.current - 1)
  end
end

-- Fill the quickfix list with one entry per step (the first line of its text) and open it.
function M.quickfix()
  if not require_tour() then
    return
  end
  local items = {}
  local n = #state.tour.steps
  for i, step in ipairs(state.tour.steps) do
    local buf, row = position(i)
    table.insert(items, {
      bufnr = buf,
      filename = not buf and resolve(state.tour.root, step.file) or nil,
      lnum = row and row + 1 or step.line,
      text = ("[%d/%d] %s"):format(i, n, vim.trim(step.text[1])),
    })
  end
  vim.fn.setqflist({}, " ", { title = "claude-tour: " .. state.tour.title, items = items })
  vim.cmd("copen")
end

-- Completion for :ClaudeTourLoad / :ClaudeTourSave: tour names in tour_dir, then files.
function M.complete(arglead)
  local names = {}
  for _, path in ipairs(vim.fn.globpath(M.config.tour_dir, "*.json", false, true)) do
    local name = vim.fn.fnamemodify(path, ":t:r")
    if name:sub(1, #arglead) == arglead then
      table.insert(names, name)
    end
  end
  vim.list_extend(names, vim.fn.getcompletion(arglead, "file"))
  return names
end

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
end

set_highlights()
vim.api.nvim_create_autocmd("ColorScheme", {
  group = vim.api.nvim_create_augroup("claude_tour_highlights", { clear = true }),
  callback = set_highlights,
})

return M
