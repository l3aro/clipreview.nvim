-- Comment store: extmark anchoring, strict resolution, CRUD. Snippet spans live in snippet.lua.
local scope = require("clipreview.scope")
local snippet = require("clipreview.snippet")

local M = {}
local ns = vim.api.nvim_create_namespace("clipreview")

---@class CRComment
---@field id integer
---@field bufnr integer          -- buffer the comment was created in (-1 when detached)
---@field extmark integer|nil
---@field text string
---@field created_at integer
---@field has_cols boolean
---@field file string            -- absolute path at creation
---@field start_line integer     -- fallback, 1-indexed inclusive
---@field end_line integer       -- fallback, 1-indexed inclusive
---@field cols integer[]|nil     -- {start, end}, 0-indexed, end-exclusive
---@field fingerprint string     -- sha256 of the span text at creation
---@field root string            -- scope root captured at creation
---@field is_git boolean

---@type table<integer, CRComment>
local store = {}
local next_id = 0

---@param fn function
---@param bufnr integer|nil
---@return boolean
local function buf_check(fn, bufnr)
  if type(bufnr) ~= "number" or bufnr < 0 then return false end
  local ok, res = pcall(fn, bufnr)
  return ok and res == true
end

---@param bufnr integer|nil
---@return boolean
local function is_loaded(bufnr) return buf_check(vim.api.nvim_buf_is_loaded, bufnr) end

---@param bufnr integer|nil
---@return boolean
local function is_valid(bufnr) return buf_check(vim.api.nvim_buf_is_valid, bufnr) end

--- Sign/highlight options from config.signs.
---@return table
local function sign_opts()
  local signs = require("clipreview.config").config.signs
  if type(signs) ~= "table" then return {} end
  local opts = {}
  if type(signs.text) == "string" and signs.text ~= "" then opts.sign_text = signs.text end
  if type(signs.hl) == "string" and signs.hl ~= "" then opts.sign_hl_group = signs.hl end
  if type(signs.line_hl) == "string" and signs.line_hl ~= "" then opts.line_hl_group = signs.line_hl end
  return opts
end

--- `virt_lines` callout options for `text`; empty table when the preview is off.
local function callout_opts(text)
  local chunks = require("clipreview.decor").callout(text or "", require("clipreview.config").config)
  return chunks and { virt_lines = chunks, virt_lines_above = true } or {}
end

--- Place the anchor extmark (signs + callout); nil on failure. With `id`, that mark is
--- re-decorated in place: set_extmark clears every option it does not receive.
---@param bufnr integer
---@param start_line integer
---@param end_line integer
---@param cols integer[]|nil
---@param text string
---@param id integer|nil
---@return integer|nil
local function place_extmark(bufnr, start_line, end_line, cols, text, id)
  local lc = vim.api.nvim_buf_line_count(bufnr)
  if lc < 1 then return nil end
  local s = math.min(math.max(1, start_line), lc)
  local e = math.min(math.max(s, end_line), lc)
  local opts = vim.tbl_extend("keep", sign_opts(), callout_opts(text))
  local row, col = s - 1, 0
  if cols then
    local first = vim.api.nvim_buf_get_lines(bufnr, s - 1, s, false)[1] or ""
    col = math.min(math.max(0, math.floor(cols[1])), #first)
    opts.end_row, opts.end_col = e - 1, math.min(math.max(0, math.floor(cols[2])), #(vim.api.nvim_buf_get_lines(bufnr, e - 1, e, false)[1] or ""))
    opts.right_gravity, opts.end_right_gravity = true, false
  else
    opts.end_row, opts.end_col = e, 0
    opts.right_gravity, opts.end_right_gravity = false, true
  end
  if id then
    local res = select(2, pcall(vim.api.nvim_buf_get_extmark_by_id, bufnr, ns, id, { details = true }))
    local d = type(res) == "table" and type(res[1]) == "number" and res[3] or nil
    if type(d) ~= "table" or type(d.end_row) ~= "number" or type(d.end_col) ~= "number" then return nil end
    opts.id, row, col = id, res[1], res[2] or 0
    opts.end_row, opts.end_col = d.end_row, d.end_col
    opts.right_gravity, opts.end_right_gravity = d.right_gravity, d.end_right_gravity
  end
  local ok, mark = pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, row, col, opts)
  if not ok or type(mark) ~= "number" then return nil end
  return mark
end

---@param spec { bufnr: integer, start_line: integer, end_line: integer, cols: integer[]|nil,
---              text: string, root: string, is_git: boolean, file: string }
---@return integer|nil id, string|nil err
function M.add(spec)
  if type(spec) ~= "table" then return nil, "invalid spec" end
  local bufnr = (spec.bufnr == nil or spec.bufnr == 0) and vim.api.nvim_get_current_buf() or spec.bufnr
  if not is_valid(bufnr) then return nil, "invalid buffer" end
  if type(spec.text) ~= "string" then return nil, "missing comment text" end
  local file = spec.file
  if type(file) ~= "string" or file == "" then file = scope.file(bufnr) end
  if not file then return nil, "buffer has no file to cite" end
  local root, is_git = spec.root, spec.is_git
  if type(root) ~= "string" or root == "" then root, is_git = scope.root(bufnr) end
  local start_line = math.floor(tonumber(spec.start_line) or 0)
  local end_line = math.floor(tonumber(spec.end_line) or start_line)
  if start_line < 1 or end_line < start_line then return nil, "invalid line range" end
  local loaded, lc = is_loaded(bufnr), vim.api.nvim_buf_line_count(bufnr)
  if loaded and start_line > lc then return nil, "invalid line range" end
  if loaded then end_line = math.min(end_line, lc) end
  local cols
  if type(spec.cols) == "table" then
    local c1, c2 = math.floor(tonumber(spec.cols[1]) or -1), math.floor(tonumber(spec.cols[2]) or -1)
    if loaded then
      c1 = math.min(c1, #(vim.api.nvim_buf_get_lines(bufnr, start_line - 1, start_line, false)[1] or ""))
      c2 = math.min(c2, #(vim.api.nvim_buf_get_lines(bufnr, end_line - 1, end_line, false)[1] or ""))
    end
    if c1 < 0 or c2 < 0 then return nil, "invalid cols" end
    if start_line == end_line and c1 >= c2 then return nil, "invalid cols" end
    cols = { c1, c2 }
  end
  local span_view = { bufnr = bufnr, file = file, start_line = start_line, end_line = end_line, has_cols = cols ~= nil, cols = cols }
  local span = snippet.read_buffer(span_view) or snippet.read_disk(span_view) or {}
  next_id = next_id + 1
  store[next_id] = {
    id = next_id, bufnr = bufnr, extmark = place_extmark(bufnr, start_line, end_line, cols, spec.text),
    text = spec.text, created_at = os.time(), has_cols = cols ~= nil,
    file = vim.fs.normalize(file), start_line = start_line, end_line = end_line, cols = cols,
    fingerprint = snippet.fingerprint(span), root = vim.fs.normalize(root), is_git = is_git and true or false,
  }
  return next_id
end

--- Create a non-live record (no bufnr/extmark) loaded from JSON.
---@param rec { file: string, root: string, is_git: boolean, start_line: integer, end_line: integer,
---             cols: integer[]|nil, text: string, created_at: integer, fingerprint: string }
---@return integer|nil id, string|nil err
function M.restore(rec)
  if type(rec) ~= "table" or type(rec.file) ~= "string" or rec.file == "" then return nil, "invalid record" end
  local start_line = math.floor(tonumber(rec.start_line) or 0)
  local end_line = math.floor(tonumber(rec.end_line) or start_line)
  if start_line < 1 or end_line < start_line then return nil, "invalid record" end
  local cols
  if type(rec.cols) == "table" then
    local c1, c2 = tonumber(rec.cols[1]), tonumber(rec.cols[2])
    if c1 and c2 and c1 >= 0 and c2 >= 0 and (start_line ~= end_line or c2 > c1) then
      cols = { math.floor(c1), math.floor(c2) }
    end
  end
  next_id = next_id + 1
  store[next_id] = {
    id = next_id, bufnr = -1, extmark = nil, text = type(rec.text) == "string" and rec.text or "",
    created_at = math.floor(tonumber(rec.created_at) or os.time()), has_cols = cols ~= nil,
    file = vim.fs.normalize(rec.file), start_line = start_line, end_line = end_line,
    cols = cols, fingerprint = type(rec.fingerprint) == "string" and rec.fingerprint or "",
    root = type(rec.root) == "string" and vim.fs.normalize(rec.root) or vim.fs.normalize(vim.fn.getcwd()),
    is_git = rec.is_git and true or false,
  }
  return next_id
end

--- Live-only strict resolution: nil when the buffer is invalid/unloaded or the extmark is gone.
---@param id integer
---@return { bufnr: integer, start_line: integer, end_line: integer, cols: integer[]|nil,
---          has_cols: boolean }|nil
function M.resolve(id)
  local rec = store[id]
  if not rec then return nil end
  local bufnr, mark = rec.bufnr, rec.extmark
  if type(mark) ~= "number" or not is_loaded(bufnr) then return nil end
  local ok, res = pcall(vim.api.nvim_buf_get_extmark_by_id, bufnr, ns, mark, { details = true })
  if not ok or type(res) ~= "table" or type(res[1]) ~= "number" then return nil end
  local details, row, col = res[3] or {}, res[1], res[2] or 0
  local end_row = type(details.end_row) == "number" and details.end_row or row
  local end_col = type(details.end_col) == "number" and details.end_col or 0
  if rec.has_cols then
    return { bufnr = bufnr, start_line = row + 1, end_line = end_row + 1, cols = { col, end_col }, has_cols = true }
  end
  return { bufnr = bufnr, start_line = row + 1, end_line = math.max(end_row + (end_col > 0 and 1 or 0), row + 1), cols = nil, has_cols = false }
end

--- Unified record used by every consumer. Returns nil only when `id` is unknown.
---@param id integer
---@return (CRComment & { live: boolean, loaded: boolean, shifted: boolean })|nil
function M.view(id)
  local rec = store[id]
  if not rec then return nil end
  local view = {}
  for k, v in pairs(rec) do view[k] = v end
  local live = M.resolve(id)
  view.loaded = is_loaded(rec.bufnr)
  if live then
    view.start_line, view.end_line, view.cols, view.has_cols = live.start_line, live.end_line, live.cols, live.has_cols
    rec.start_line, rec.end_line, rec.cols, rec.has_cols = view.start_line, view.end_line, view.cols, view.has_cols
  end
  view.live, view.shifted = live ~= nil, false
  return view
end

---@return integer[] ids sorted by (display path, start_line)
function M.ids()
  local rows = {}
  for id in pairs(store) do
    local view = M.view(id)
    rows[#rows + 1] = { id = id, path = scope.shorten(view.root, view.file), line = view.start_line }
  end
  table.sort(rows, function(a, b)
    if a.path ~= b.path then return a.path < b.path end
    if a.line ~= b.line then return a.line < b.line end
    return a.id < b.id
  end)
  local ids = {}
  for i, row in ipairs(rows) do ids[i] = row.id end
  return ids
end

--- Raw stored record (never nil for a known id).
---@param id integer
---@return CRComment|nil
function M.get(id)
  return store[id]
end

---@param id integer
---@param text string
---@return boolean
function M.update(id, text)
  local rec = store[id]
  if not rec or type(text) ~= "string" then return false end
  rec.text = text
  if type(rec.extmark) == "number" and is_loaded(rec.bufnr) then
    place_extmark(rec.bufnr, rec.start_line, rec.end_line, rec.cols, text, rec.extmark)
  end
  return true
end

---@param id integer
---@return boolean
function M.delete(id)
  local rec = store[id]
  if not rec then return false end
  if type(rec.extmark) == "number" and is_valid(rec.bufnr) then
    pcall(vim.api.nvim_buf_del_extmark, rec.bufnr, ns, rec.extmark)
  end
  store[id] = nil
  return true
end

---@return integer n
function M.clear()
  local n = 0
  for id in pairs(store) do n = n + (M.delete(id) and 1 or 0) end
  return n
end

---@return integer count
function M.count()
  return vim.tbl_count(store)
end

--- Snippet lines for one view, honouring config.snippet.max_lines.
---@param view CRComment
---@return { lines: string[], more: integer, shifted: boolean }
function M.snippet(view)
  return snippet.compute(view)
end

--- Re-anchor a non-live record into `bufnr` when the stored span still matches its fingerprint.
---@param id integer
---@param bufnr integer
---@return boolean anchored
function M.anchor(id, bufnr)
  local rec = store[id]
  if not rec then return false end
  bufnr = (bufnr == nil or bufnr == 0) and vim.api.nvim_get_current_buf() or bufnr
  if not is_loaded(bufnr) or M.resolve(id) then return false end
  local span = snippet.span({
    bufnr = bufnr, start_line = rec.start_line, end_line = rec.end_line, cols = rec.cols,
    has_cols = rec.has_cols, file = rec.file,
  })
  if not span or type(rec.fingerprint) ~= "string" or rec.fingerprint == "" then return false end
  if snippet.fingerprint(span) ~= rec.fingerprint then return false end
  if type(rec.extmark) == "number" and is_valid(rec.bufnr) then
    pcall(vim.api.nvim_buf_del_extmark, rec.bufnr, ns, rec.extmark)
  end
  local mark = place_extmark(bufnr, rec.start_line, rec.end_line, rec.cols, rec.text)
  if not mark then return false end
  rec.bufnr, rec.extmark = bufnr, mark
  return true
end

return M
