-- Input prompts: single-line via vim.ui.input and a multi-line float editor.
local M = {}

local MAX_EDIT_HEIGHT = 12

---Exact text of a scratch buffer; nil only when the buffer is unreadable.
---@param buf integer
---@return string|nil text
local function buffer_text(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return nil
  end
  local ok, lines = pcall(vim.api.nvim_buf_get_lines, buf, 0, -1, false)
  if not ok then
    return nil
  end
  return table.concat(lines, "\n")
end

---Delete a float buffer and its window without raising on the second close.
---@param win integer|nil
---@param buf integer|nil
local function destroy(win, buf)
  if win and vim.api.nvim_win_is_valid(win) then
    pcall(vim.api.nvim_win_close, win, true)
  end
  if buf and vim.api.nvim_buf_is_valid(buf) then
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end
end

---@param lines string[]
---@return integer width, integer height
local function editor_size(lines)
  local text_width = 20
  for _, line in ipairs(lines) do
    text_width = math.max(text_width, vim.fn.strdisplaywidth(line))
  end
  local max_width = math.max(vim.o.columns - 6, 20)
  local width = math.max(math.min(text_width + 4, max_width), 20)
  local max_height = math.max(math.min(MAX_EDIT_HEIGHT, vim.o.lines - 6), 1)
  local height = math.max(math.min(math.max(#lines, 1), max_height), 1)
  return width, height
end

---@param initial string
---@param cb fun(text: string|nil)
---@param created { win: integer|nil, buf: integer|nil }
local function open_editor(initial, cb, created)
  local lines = vim.split(initial, "\n", { plain = true })
  if #lines == 0 then
    lines = { "" }
  end

  local buf = vim.api.nvim_create_buf(false, true)
  created.buf = buf
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "markdown"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  local width, height = editor_size(lines)
  local config = {
    relative = "editor",
    width = width,
    height = height,
    row = math.max(math.floor((vim.o.lines - height) / 2) - 1, 0),
    col = math.max(math.floor((vim.o.columns - width) / 2), 0),
    style = "minimal",
    border = "rounded",
    title = " Comment ",
    title_pos = "center",
    footer = " <C-s> save  <Esc> cancel ",
    footer_pos = "center",
  }

  local win = vim.api.nvim_open_win(buf, true, config)
  created.win = win
  vim.wo[win].wrap = true
  vim.wo[win].cursorline = true
  vim.api.nvim_win_set_cursor(win, { #lines, #lines[#lines] })

  local state = { closed = false, au = nil }

  ---@param save boolean
  local function finish(save)
    if state.closed then
      return
    end
    state.closed = true
    local text = save and buffer_text(buf) or nil
    local au = state.au
    state.au = nil
    if au then
      pcall(vim.api.nvim_del_autocmd, au)
    end
    destroy(win, buf)
    vim.schedule(function()
      cb(text)
    end)
  end

  state.au = vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(win),
    once = true,
    callback = function()
      finish(false)
    end,
  })

  local function map(mode, lhs, fn, desc)
    vim.keymap.set(mode, lhs, fn, { buffer = buf, nowait = true, silent = true, desc = desc })
  end
  map({ "n", "i" }, "<C-s>", function()
    finish(true)
  end, "clipreview: save comment")
  map("n", "<Esc>", function()
    finish(false)
  end, "clipreview: cancel comment")
  map("n", "q", function()
    finish(false)
  end, "clipreview: cancel comment")
end

---Single-line comment prompt (honours dressing.nvim / other vim.ui.input overrides).
---@param cb fun(text: string|nil)
function M.input(cb)
  vim.ui.input({ prompt = "Comment: " }, function(text)
    if text == nil or vim.trim(text) == "" then
      cb(nil)
      return
    end
    cb(text)
  end)
end

---Multi-line comment editor in a centered float scratch buffer.
---`<C-s>` saves and calls `cb(text)`, `<q>`/`<Esc>` cancel and call `cb(nil)`.
---@param initial string
---@param cb fun(text: string|nil)
function M.edit_multiline(initial, cb)
  local settled = false

  ---Callback exactly once, whichever path closes the editor.
  ---@param text string|nil
  local function settle(text)
    if settled then
      return
    end
    settled = true
    cb(text)
  end

  local created = { win = nil, buf = nil }
  local ok, err = pcall(open_editor, initial or "", settle, created)
  if ok then
    return
  end
  destroy(created.win, created.buf)
  vim.notify("clipreview: cannot open the comment editor: " .. tostring(err), vim.log.levels.ERROR)
  settle(nil)
end

---Comment list float; implemented in `clipreview.float`.
---@param items { label: string, id: integer, file: string, line: integer }[]
---@param handlers { hover: fun(id: integer)|nil, jump: fun(id: integer)|nil, edit: fun(id: integer)|nil,
---                  delete: fun(id: integer)|nil, items: (fun(): table[])|nil }
function M.list_float(items, handlers)
  return require("clipreview.float").open(items, handlers)
end

return M
