-- clipreview.nvim — annotate buffers, export an agent-ready payload to the clipboard.
local M = {}

local config = require("clipreview.config")

M.config = config.config

local INFO = vim.log.levels.INFO
local WARN = vim.log.levels.WARN
local ERROR = vim.log.levels.ERROR

local function cfg()
  return config.config
end

local function comments()
  return require("clipreview.comments")
end

local function scope()
  return require("clipreview.scope")
end

---@param msg string
---@param level integer|nil
local function notify(msg, level)
  vim.notify("clipreview: " .. msg, level or INFO)
end

---@param opts table|nil
---@return table config
function M.setup(opts)
  config.setup(opts)
  M.config = config.config
  require("clipreview.commands").install()
  local session = require("clipreview.session")
  if cfg().persist then
    session.install_hooks()
    session.restore()
  else
    session.clear_hooks()
  end
  return M.config
end

---@param opts { bufnr: integer|nil, start_line: integer|nil, end_line: integer|nil,
---              cols: integer[]|nil, text: string|nil }|nil
---@return integer|nil id
function M.comment(opts)
  opts = opts or {}
  local bufnr = opts.bufnr or 0
  if bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  local file = scope().file(bufnr)
  if not file or not vim.api.nvim_buf_is_loaded(bufnr) then
    notify("buffer has no file to cite", INFO)
    return nil
  end

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local start_line = opts.start_line or vim.api.nvim_win_get_cursor(0)[1]
  local end_line = opts.end_line or start_line
  if start_line > end_line then
    start_line, end_line = end_line, start_line
  end
  start_line = math.max(1, math.min(start_line, line_count))
  end_line = math.max(start_line, math.min(end_line, line_count))

  local root, is_git = scope().root(bufnr)
  local cols = opts.cols

  local function commit(text)
    if type(text) ~= "string" then
      return nil
    end
    local trimmed = text:gsub("^%s*\n", ""):gsub("%s+$", "")
    if trimmed == "" then
      return nil
    end
    local id = comments().add({
      bufnr = bufnr,
      start_line = start_line,
      end_line = end_line,
      cols = cols,
      text = trimmed,
      root = root,
      is_git = is_git,
      file = file,
    })
    if id then
      require("clipreview.session").save(require("clipreview.payload").views("all"))
    end
    return id
  end

  if opts.text ~= nil then
    return commit(opts.text)
  end
  local created
  require("clipreview.ui").input(function(text)
    created = commit(text)
  end)
  -- nil when the input implementation is asynchronous (dressing.nvim, noice, …).
  return created
end

---@return integer|nil id
function M.comment_selection()
  local bufnr = vim.api.nvim_get_current_buf()
  local span = require("clipreview.selection").span(bufnr)
  if not span then
    return M.comment({ bufnr = bufnr })
  end
  return M.comment({
    bufnr = bufnr,
    start_line = span.start_line,
    end_line = span.end_line,
    cols = span.cols,
  })
end

--- Paste-ready fenced block for the current line or `span`.
---@param span { start_line: integer, end_line: integer|nil, cols: integer[]|nil }|nil
---@return string|nil text, string|nil location
function M.build_selection(span)
  local bufnr = vim.api.nvim_get_current_buf()
  local file = scope().file(bufnr)
  if not file then
    notify("buffer has no file to cite", INFO)
    return nil
  end

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local start_line = (span and span.start_line) or vim.api.nvim_win_get_cursor(0)[1]
  local end_line = (span and span.end_line) or start_line
  if start_line > end_line then
    start_line, end_line = end_line, start_line
  end
  start_line = math.max(1, math.min(start_line, line_count))
  end_line = math.max(start_line, math.min(end_line, line_count))

  local cols = span and span.cols
  local lines = require("clipreview.snippet").read_buffer({
    bufnr = bufnr,
    start_line = start_line,
    end_line = end_line,
    has_cols = cols ~= nil,
    cols = cols,
  })
  if not lines then
    notify("could not read the buffer", WARN)
    return nil
  end

  local item = {
    path = scope().shorten(scope().root(bufnr), file),
    start_line = start_line,
    end_line = end_line,
    cols = cols,
    lines = lines,
    lang = vim.bo[bufnr].filetype or "",
  }
  local prompt = require("clipreview.prompt")
  return prompt.format_selection(item), prompt.location(item)
end

--- Copy the current line or `span` as a paste-ready fenced block.
---@param span { start_line: integer, end_line: integer|nil, cols: integer[]|nil }|nil
---@return boolean ok, string|nil err "no-file"|"no-provider"|"write-failed"
function M.copy_selection(span)
  local text, location = M.build_selection(span)
  if not text then
    return false, "no-file"
  end
  local ok, err = require("clipreview.clipboard").write(text, cfg().register)
  if not ok then
    local why = err == "no-provider" and "no clipboard provider" or ("copy failed: " .. tostring(err))
    notify(string.format("%s — selection is:\n%s", why, text), WARN)
    return false, err
  end
  notify("copied " .. location)
  return true, nil
end

---@param scope_name string|nil
---@return table[] { id, file, abs_path, start_line, end_line, cols, text }
function M.list(scope_name)
  local out = {}
  for _, view in ipairs(require("clipreview.payload").views(scope_name)) do
    out[#out + 1] = {
      id = view.id,
      file = scope().shorten(view.root, view.file),
      abs_path = view.file,
      start_line = view.start_line,
      end_line = view.end_line,
      cols = view.cols,
      text = view.text,
    }
  end
  return out
end

---@param scope_name string|nil
---@return string payload, integer n
function M.build(scope_name)
  return require("clipreview.payload").build(scope_name)
end

---@param opts { register: string|nil }|nil
---@return boolean ok, string|nil err "empty"|"no-provider"|"write-failed"
function M.copy(opts)
  local text, n = M.build(cfg().scope)
  if n == 0 then
    notify("no comments to copy", INFO)
    return false, "empty"
  end
  local clipboard = require("clipreview.clipboard")
  local reg = (opts and opts.register) or cfg().register
  local wrote, write_err = clipboard.write(text, reg)
  if not wrote then
    M.preview()
    if write_err == "no-provider" then
      notify("no clipboard provider — payload opened, copy manually (`:checkhealth clipboard`)", WARN)
      return false, "no-provider"
    elseif write_err == "verify-failed" then
      notify("clipboard write could not be verified (write-only provider?) — payload opened", ERROR)
    else
      notify("clipboard write failed — payload opened", ERROR)
    end
    return false, "write-failed"
  end
  if cfg().clear_after_copy then
    M.clear(cfg().scope)
  end
  if #text > 65536 then
    notify(string.format("payload is %d bytes; some terminals truncate clipboard writes", #text), WARN)
  end
  notify(string.format("copied %d comment(s) to %s", n, reg))
  return true
end

---@param opts { scope: string|nil }|nil
---@return integer bufnr
function M.preview(opts)
  local scope_name = (opts and opts.scope) or cfg().scope
  return require("clipreview.clipboard").preview(M.build(scope_name))
end

---@param span { path: string|nil, file: string|nil, abs_path: string|nil, root: string|nil,
---              start_line: integer|nil, end_line: integer|nil, cols: integer[]|nil }|nil
---@return string
function M.ref(span)
  local bufnr = vim.api.nvim_get_current_buf()
  local current_file = scope().file(bufnr)
  local path, start_line, end_line

  if span then
    start_line = span.start_line
    end_line = span.end_line or start_line
    path = span.path
    if not path then
      local file = span.abs_path or span.file or current_file
      if not file then
        notify("buffer has no file to cite", INFO)
        return ""
      end
      path = scope().shorten(span.root or scope().root(bufnr), file)
    end
  else
    if not current_file then
      notify("buffer has no file to cite", INFO)
      return ""
    end
    local selected = require("clipreview.selection").span(bufnr)
    start_line = selected and selected.start_line or vim.api.nvim_win_get_cursor(0)[1]
    end_line = selected and selected.end_line or start_line
    path = scope().shorten(scope().root(bufnr), current_file)
  end

  if not start_line then
    return ""
  end
  return require("clipreview.prompt").format_ref({
    path = path,
    start_line = start_line,
    end_line = end_line or start_line,
  })
end

---@param id integer
---@param text string
---@return boolean
function M.edit(id, text)
  local trimmed = (text or ""):gsub("^%s*\n", ""):gsub("%s+$", "")
  if trimmed == "" or not comments().update(id, trimmed) then
    return false
  end
  require("clipreview.session").save(require("clipreview.payload").views("all"))
  return true
end

---@param id integer
---@return boolean
function M.delete(id)
  if not comments().delete(id) then
    return false
  end
  require("clipreview.session").save(require("clipreview.payload").views("all"))
  return true
end

---@param scope_name string|nil
---@return integer n
function M.clear(scope_name)
  local n = 0
  for _, view in ipairs(require("clipreview.payload").views(scope_name)) do
    if comments().delete(view.id) then
      n = n + 1
    end
  end
  if n > 0 then
    require("clipreview.session").save(require("clipreview.payload").views("all"))
  end
  return n
end

---@param path string|nil
---@return boolean ok, string|nil err
function M.export(path)
  local text, n = M.build(cfg().scope)
  if n == 0 then
    return false, "empty"
  end
  if not path or path == "" then
    path = "clipreview-export.md"
  end
  path = vim.fn.fnamemodify(vim.fn.expand(path), ":p")
  local ok = pcall(vim.fn.writefile, vim.split(text, "\n", { plain = true }), path)
  if not ok then
    return false, "write-failed"
  end
  return true, path
end

function M.list_ui()
  require("clipreview.list").open()
end

---@return string
function M.statusline()
  local n = #require("clipreview.payload").views(cfg().scope)
  if n == 0 then
    return ""
  end
  return "● " .. n
end

return M
