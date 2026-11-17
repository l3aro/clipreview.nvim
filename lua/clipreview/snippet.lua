-- Byte-exact span extraction and snippet computation. Leaf module: config is read lazily.
local M = {}

---@param bufnr integer|nil
---@return boolean
local function is_loaded(bufnr)
  if type(bufnr) ~= "number" or bufnr < 0 then return false end
  local ok, res = pcall(vim.api.nvim_buf_is_loaded, bufnr)
  return ok and res == true
end

--- sha256 of span lines joined by "\n" (the record fingerprint).
---@param lines string[]
---@return string
function M.fingerprint(lines)
  return vim.fn.sha256(table.concat(lines, "\n"))
end

--- Byte-exact slice of whole lines down to `cols` (no normalization).
---@param lines string[]
---@param view { has_cols: boolean|nil, cols: integer[]|nil }
---@return string[]
local function slice(lines, view)
  if not view.has_cols or type(view.cols) ~= "table" or #lines == 0 then return lines end
  local c1 = math.max(0, math.floor(tonumber(view.cols[1]) or 0))
  local c2 = math.max(0, math.floor(tonumber(view.cols[2]) or 0))
  if #lines == 1 then return { lines[1]:sub(c1 + 1, c2) } end
  local out = { lines[1]:sub(c1 + 1) }
  for i = 2, #lines - 1 do out[#out + 1] = lines[i] end
  if c2 > 0 then out[#out + 1] = lines[#lines]:sub(1, c2) end
  return out
end

--- Span lines from the loaded buffer, nil when it cannot be read.
---@param view table
---@return string[]|nil
function M.read_buffer(view)
  if not is_loaded(view.bufnr) then return nil end
  local lc = vim.api.nvim_buf_line_count(view.bufnr)
  local s = math.max(1, math.floor(tonumber(view.start_line) or 1))
  local e = math.min(math.floor(tonumber(view.end_line) or s), lc)
  if s > lc or e < s then return {} end
  return slice(vim.api.nvim_buf_get_lines(view.bufnr, s - 1, e, false), view)
end

--- Span lines from disk, nil when the file cannot be read.
---@param view table
---@return string[]|nil
function M.read_disk(view)
  if type(view.file) ~= "string" or view.file == "" then return nil end
  local ok, all = pcall(vim.fn.readfile, view.file)
  if not ok or type(all) ~= "table" then return nil end
  local s = math.max(1, math.floor(tonumber(view.start_line) or 1))
  local e = math.floor(tonumber(view.end_line) or s)
  local lines = {}
  for i = s, e do
    if all[i] == nil then break end
    lines[#lines + 1] = all[i]
  end
  return slice(lines, view)
end

--- Span lines for a view: loaded buffer first, then disk.
---@param view table
---@return string[]|nil
function M.span(view)
  return M.read_buffer(view) or M.read_disk(view)
end

--- Snippet lines for one view, honouring config.snippet.max_lines.
---@param view CRComment
---@return { lines: string[], more: integer, shifted: boolean }
function M.compute(view)
  if type(view) ~= "table" then return { lines = {}, more = 0, shifted = false } end
  local cfg = require("clipreview.config").config.snippet
  local max_lines = 10
  if type(cfg) == "table" and type(cfg.max_lines) == "number" then
    max_lines = math.max(0, math.floor(cfg.max_lines))
  end
  local span, from_buffer
  if view.live and view.loaded then
    span = M.read_buffer(view)
    from_buffer = span ~= nil
  end
  if not span then span = M.read_disk(view) end
  local shifted = false
  if not from_buffer and span and type(view.fingerprint) == "string" and view.fingerprint ~= "" then
    shifted = M.fingerprint(span) ~= view.fingerprint
  end
  span = span or {}
  local lines, more = span, 0
  if #span > max_lines then
    lines = {}
    for i = 1, max_lines do lines[i] = span[i] end
    more = #span - max_lines
  end
  view.shifted = shifted
  return { lines = lines, more = more, shifted = shifted }
end

return M
