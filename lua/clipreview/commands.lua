-- :ClipReview <subcommand>, completion and the configured keymaps.
local M = {}

local SUBCOMMANDS = { "comment", "list", "copy", "preview", "ref", "selection", "clear", "export", "help" }

local HELP_LINES = {
  "clipreview: annotate code and copy a review payload",
  "",
  "  :ClipReview comment        comment the current line, range or visual selection",
  "  :ClipReview list           open the comment list",
  "  :ClipReview copy           copy the markdown payload to the clipboard register",
  "  :ClipReview preview        open the payload in a scratch buffer",
  "  :ClipReview ref            copy the path:line reference for the current line or selection",
  "  :ClipReview selection      copy the path and code block of the current line or selection",
  "  :ClipReview clear          delete every comment in the current scope",
  "  :ClipReview export <path>  write the payload to <path>",
  "  :ClipReview help           show this message",
}

---Maps installed by the last `install()`: deleted before re-installing.
---@type { mode: string, lhs: string }[]
local installed = {}

---@param cmd table
local function run_comment(cmd)
  local cr = require("clipreview")
  if cmd.range == 2 and vim.fn.line("'<") == cmd.line1 and vim.fn.line("'>") == cmd.line2 then
    cr.comment_selection()
    return
  end
  cr.comment({ start_line = cmd.line1, end_line = cmd.line2 })
end

---Copy the `path:line ` reference for the cursor line or visual selection.
local function copy_ref()
  local cr = require("clipreview")
  local text = cr.ref()
  if text == "" then
    return
  end
  local config = require("clipreview.config").config
  local clipboard = require("clipreview.clipboard")
  local ok, err = clipboard.write(text, config.register)
  if not ok then
    local why = err == "no-provider" and "no clipboard provider" or ("copy failed: " .. tostring(err))
    vim.notify(("clipreview: %s — ref is: %s"):format(why, text), vim.log.levels.WARN)
    return
  end
  vim.notify("clipreview: copied ref " .. text)
end

---Copy the current line or selection as a paste-ready code block.
---@param cmd table
local function run_selection(cmd)
  local cr = require("clipreview")
  local bufnr = vim.api.nvim_get_current_buf()
  local span
  if cmd.range == 2 then
    if vim.fn.line("'<") == cmd.line1 and vim.fn.line("'>") == cmd.line2 then
      span = require("clipreview.selection").span(bufnr)
    end
    span = span or { start_line = cmd.line1, end_line = cmd.line2 }
  end
  cr.copy_selection(span)
end

---@param cmd table
local function run_export(cmd)
  local path = cmd.fargs[2]
  if path == nil or path == "" then
    vim.notify("clipreview: export needs a path", vim.log.levels.ERROR)
    return
  end
  local ok, err = require("clipreview").export(path)
  if not ok then
    vim.notify("clipreview: export failed: " .. tostring(err), vim.log.levels.ERROR)
    return
  end
  vim.notify("clipreview: wrote " .. vim.fn.fnamemodify(path, ":p"))
end

---@param level integer
---@param prefix string|nil
local function show_help(level, prefix)
  local lines = {}
  if prefix then
    lines[#lines + 1] = prefix
    lines[#lines + 1] = ""
  end
  for _, line in ipairs(HELP_LINES) do
    lines[#lines + 1] = line
  end
  vim.notify(table.concat(lines, "\n"), level)
end

---@param cmd table
local function dispatch(cmd)
  local sub = cmd.fargs[1] or "help"
  if sub == "comment" then
    run_comment(cmd)
    return
  end
  if sub == "help" then
    show_help(vim.log.levels.INFO)
    return
  end
  if sub == "export" then
    run_export(cmd)
    return
  end
  if sub == "ref" then
    copy_ref()
    return
  end
  if sub == "selection" then
    run_selection(cmd)
    return
  end
  local cr = require("clipreview")
  if sub == "list" then
    cr.list_ui()
  elseif sub == "copy" then
    cr.copy()
  elseif sub == "preview" then
    cr.preview()
  elseif sub == "clear" then
    cr.clear()
  else
    show_help(vim.log.levels.WARN, "clipreview: unknown subcommand '" .. sub .. "'")
  end
end

---Subcommand completion; `export` completes file names.
---@param arg_lead string
---@param cmd_line string
---@param cursor_pos integer|nil
---@return string[]
function M.complete(arg_lead, cmd_line, cursor_pos)
  local line = cmd_line:sub(1, cursor_pos or #cmd_line)
  local args = vim.split(line, "%s+", { trimempty = true })
  local first_arg = #args <= 1 or (#args == 2 and not line:match("%s$"))
  if first_arg then
    local matches = {}
    for _, name in ipairs(SUBCOMMANDS) do
      if name:sub(1, #arg_lead) == arg_lead then
        matches[#matches + 1] = name
      end
    end
    return matches
  end
  if args[2] == "export" then
    return vim.fn.getcompletion(arg_lead, "file")
  end
  return {}
end

---@param mode string
---@param lhs string
---@param rhs function
---@param desc string
local function set_map(mode, lhs, rhs, desc)
  vim.keymap.set(mode, lhs, rhs, { silent = true, desc = "clipreview: " .. desc })
  installed[#installed + 1] = { mode = mode, lhs = lhs }
end

---Register `:ClipReview` and the configured keymaps. Safe to call repeatedly.
function M.install()
  for _, map in ipairs(installed) do
    pcall(vim.keymap.del, map.mode, map.lhs)
  end
  installed = {}

  vim.api.nvim_create_user_command("ClipReview", dispatch, {
    nargs = "*",
    range = true,
    force = true, -- install() is called by plugin startup and again by setup()
    complete = M.complete,
    desc = "clipreview: annotate code and copy review comments",
  })

  local keymaps = require("clipreview.config").config.keymaps or {}

  ---@param mode string
  ---@param name string
  ---@param rhs function
  ---@param desc string
  local function add(mode, name, rhs, desc)
    local lhs = keymaps[name]
    if type(lhs) ~= "string" or lhs == "" then
      return
    end
    set_map(mode, lhs, rhs, desc)
  end

  add("n", "comment", function()
    require("clipreview").comment({})
  end, "comment on current line")
  add("x", "comment", function()
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
    require("clipreview").comment_selection()
  end, "comment on selection")
  add("n", "list", function()
    require("clipreview").list_ui()
  end, "list comments")
  add("n", "copy", function()
    require("clipreview").copy()
  end, "copy payload")
  add("n", "preview", function()
    require("clipreview").preview()
  end, "preview payload")
  add("n", "ref", copy_ref, "copy location reference")
  add("n", "selection", function()
    require("clipreview").copy_selection(nil)
  end, "copy the current line as a code block")
  add("x", "selection", function()
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
    local buf = vim.api.nvim_get_current_buf()
    require("clipreview").copy_selection(require("clipreview.selection").span(buf))
  end, "copy the selection as a code block")
end

return M
