-- Comment list UI orchestration (float via ui.lua, select fallback).
local M = {}

---@param source_win integer
---@return integer
local function target_win(source_win)
  if vim.api.nvim_win_is_valid(source_win) then
    return source_win
  end
  return vim.api.nvim_get_current_win()
end

---@param view table
---@param source_win integer
local function reveal(view, source_win)
  local win = target_win(source_win)
  if view.bufnr and view.bufnr > 0 and vim.api.nvim_buf_is_valid(view.bufnr) then
    vim.api.nvim_win_set_buf(win, view.bufnr)
  else
    pcall(vim.api.nvim_win_call, win, function()
      vim.cmd.edit({ args = { view.file } })
    end)
  end
  local count = vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(win))
  pcall(vim.api.nvim_win_set_cursor, win, { math.max(1, math.min(view.start_line, count)), 0 })
end

---@param view table
---@return string
local function label(view)
  local span = view.start_line == view.end_line and tostring(view.start_line)
    or (view.start_line .. "-" .. view.end_line)
  local first = view.text:gsub("\n.*$", "")
  return string.format("%s:%s  %s", view.file, span, first)
end

function M.open()
  local cr = require("clipreview")
  local scope = require("clipreview.scope")
  local config = require("clipreview.config").config
  if #cr.list() == 0 then
    vim.notify("clipreview: no comments", vim.log.levels.INFO)
    return
  end
  local source_win = vim.api.nvim_get_current_win()

  local function items()
    local out = {}
    for _, view in ipairs(cr.list()) do
      out[#out + 1] = { id = view.id, file = view.file, line = view.start_line, label = label(view) }
    end
    return out
  end

  local function view_of(id)
    return require("clipreview.comments").view(id)
  end

  local handlers = {
    hover = function(id)
      local view = view_of(id)
      if view then
        reveal(view, source_win)
      end
    end,
    jump = function(id)
      local view = view_of(id)
      if view then
        reveal(view, source_win)
      end
    end,
    items = items,
    edit = function(id)
      local view = view_of(id)
      if view then
        reveal(view, source_win)
      end
      local win = target_win(source_win)
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_set_current_win(win)
      end
      require("clipreview.ui").edit_multiline(view and view.text or "", function(text)
        if text ~= nil then
          cr.edit(id, text)
        end
      end)
    end,
    delete = function(id)
      cr.delete(id)
    end,
  }

  if config.list_ui == "ui.select" then
    vim.ui.select(items(), {
      prompt = "clipreview comments",
      format_item = function(item)
        return item.label
      end,
    }, function(choice)
      if choice then
        handlers.edit(choice.id)
      end
    end)
    return
  end

  require("clipreview.ui").list_float(items(), handlers)
end

return M
