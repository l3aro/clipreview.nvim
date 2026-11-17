-- Floating comment list: j/k hover, <CR> edit, d delete; vim.ui.select when floats fail.
local M = {}

local MAX_LIST_HEIGHT = 14

---Window placement shared by the float windows: centered in the editor.
---@param width integer
---@param height integer
---@return table
local function centered(width, height)
  return {
    relative = "editor",
    width = width,
    height = height,
    row = math.max(math.floor((vim.o.lines - height) / 2) - 1, 0),
    col = math.max(math.floor((vim.o.columns - width) / 2), 0),
  }
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

---Fallback when the float window cannot be created (no editor UI).
---`vim.ui.select` blocks on stdin without a UI, so it is only used with one.
---@param list { label: string, id: integer, file: string, line: integer }[]
---@param handlers table
local function fallback_select(list, handlers)
  if #vim.api.nvim_list_uis() == 0 then
    vim.notify("clipreview: comment list needs a UI", vim.log.levels.WARN)
    return
  end
  local ok = pcall(
    vim.ui.select,
    list,
    { prompt = "clipreview comments", format_item = function(item)
      return item.label
    end },
    function(choice)
      if choice and handlers.jump then
        handlers.jump(choice.id)
      end
    end
  )
  if not ok then
    vim.notify("clipreview: cannot show the comment list", vim.log.levels.ERROR)
  end
end

---@param list { label: string, id: integer, file: string, line: integer }[]
---@param handlers table
---@param created { win: integer|nil, buf: integer|nil }
---@param start_index integer
local function open_list(list, handlers, created, start_index)
  local buf = vim.api.nvim_create_buf(false, true)
  created.buf = buf
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "clipreview"

  local state = { closed = false, index = math.max(start_index, 1), au = nil }

  local function list_width()
    local text_width = 20
    for _, item in ipairs(list) do
      text_width = math.max(text_width, vim.fn.strdisplaywidth(item.label))
    end
    local max_width = math.max(vim.o.columns - 6, 20)
    return math.max(math.min(text_width + 4, max_width), 20)
  end

  ---@param height integer
  ---@return table
  local function window_config(height)
    local config = centered(list_width(), height)
    config.style = "minimal"
    config.border = "rounded"
    config.title = " clipreview "
    config.title_pos = "center"
    return config
  end

  local height = math.max(math.min(#list, MAX_LIST_HEIGHT), 1)
  local win = vim.api.nvim_open_win(buf, true, window_config(height))
  created.win = win
  vim.wo[win].wrap = false
  vim.wo[win].cursorline = true

  local function close()
    if state.closed then
      return
    end
    state.closed = true
    local au = state.au
    state.au = nil
    if au then
      pcall(vim.api.nvim_del_autocmd, au)
    end
    destroy(win, buf)
  end

  local function focus()
    if #list == 0 then
      return
    end
    state.index = math.min(math.max(state.index, 1), #list)
    if vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_win_set_cursor, win, { state.index, 0 })
    end
  end

  local function render()
    local labels = {}
    for i, item in ipairs(list) do
      labels[i] = item.label
    end
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, labels)
    vim.bo[buf].modifiable = false
  end

  local function move(delta)
    if #list == 0 then
      return
    end
    state.index = math.min(math.max(state.index + delta, 1), #list)
    focus()
    local item = list[state.index]
    if item and handlers.hover then
      handlers.hover(item.id)
    end
  end

  local function edit_current()
    local item = list[state.index]
    if not item then
      return
    end
    close()
    if handlers.edit then
      handlers.edit(item.id)
    end
  end

  local function delete_current()
    local item = list[state.index]
    if not item then
      return
    end
    local index = state.index
    local id = item.id
    close()
    if handlers.delete and handlers.delete(id) == false then
      M.open(list, handlers, index)
      return
    end
    if handlers.items then
      list = handlers.items() or {}
    else
      table.remove(list, index)
    end
    if #list == 0 then
      return
    end
    M.open(list, handlers, math.min(index, #list))
  end

  render()

  local function map(lhs, fn, desc)
    vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, silent = true, desc = desc })
  end
  map("j", function()
    move(1)
  end, "clipreview: next comment")
  map("k", function()
    move(-1)
  end, "clipreview: previous comment")
  map("<CR>", edit_current, "clipreview: edit comment")
  map("d", delete_current, "clipreview: delete comment")
  map("q", close, "clipreview: close list")
  map("<Esc>", close, "clipreview: close list")

  state.au = vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(win),
    once = true,
    callback = function()
      state.closed = true
    end,
  })

  focus()
end

---Open the comment list float. Never raises: falls back to `vim.ui.select`.
---@param items { label: string, id: integer, file: string, line: integer }[]
---@param handlers { hover: fun(id: integer)|nil, jump: fun(id: integer)|nil, edit: fun(id: integer)|nil,
---                  delete: fun(id: integer)|nil, items: (fun(): table[])|nil }
---@param start_index integer|nil
function M.open(items, handlers, start_index)
  local list = {}
  for i, item in ipairs(items or {}) do
    list[i] = item
  end
  if #list == 0 then
    vim.notify("clipreview: no comments to list", vim.log.levels.INFO)
    return
  end
  handlers = handlers or {}
  local created = { win = nil, buf = nil }
  local ok, err = pcall(open_list, list, handlers, created, start_index or 1)
  if ok then
    return
  end
  destroy(created.win, created.buf)
  vim.notify("clipreview: float list unavailable, falling back: " .. tostring(err), vim.log.levels.DEBUG)
  fallback_select(list, handlers)
end

return M
