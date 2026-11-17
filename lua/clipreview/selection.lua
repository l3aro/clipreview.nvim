-- Visual selection → comment span. Lead-owned helper, no plugin state.
local M = {}

---@param bufnr integer
---@param lnum integer 1-indexed
---@return string
local function buffer_line(bufnr, lnum)
  local lines = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)
  return lines[1] or ""
end

--- Span of the last visual selection in `bufnr` ('<' / '>'), with byte-exact cols for
--- charwise/blockwise selections. Returns nil when the marks do not belong to `bufnr`.
---@param bufnr integer
---@return { start_line: integer, end_line: integer, cols: integer[]|nil }|nil
function M.span(bufnr)
  local p1, p2 = vim.fn.getpos("'<"), vim.fn.getpos("'>")
  if p1[2] == 0 or p2[2] == 0 then
    return nil
  end
  if p1[1] ~= 0 and p1[1] ~= bufnr then
    return nil
  end
  if p1[2] > p2[2] then
    p1, p2 = p2, p1
  end
  local start_line, end_line = p1[2], p2[2]
  local mode = vim.fn.visualmode()
  if mode == "V" then
    return { start_line = start_line, end_line = end_line }
  end

  local cols
  local ok, region = pcall(vim.fn.getregionpos, p1, p2, { type = mode ~= "" and mode or "v", eol = true })
  if ok and type(region) == "table" and region[1] then
    local first, last = region[1][1], region[#region][2]
    start_line, end_line = first[2], last[2]
    cols = { math.max(0, first[3] - 1), math.max(0, last[3]) }
  else
    cols = { math.max(0, p1[3] - 1), math.max(0, p2[3]) }
  end

  local last_line_len = #buffer_line(bufnr, end_line)
  if cols[2] > last_line_len then
    cols[2] = last_line_len
  end
  if start_line == end_line and cols[1] > last_line_len then
    cols[1] = last_line_len
  end
  -- Selecting whole lines charwise is equivalent to a whole-line comment; the whole-line
  -- anchor survives line joins/splits better than a raw col range.
  if cols[1] == 0 and cols[2] >= last_line_len then
    return { start_line = start_line, end_line = end_line }
  end
  if cols[1] >= cols[2] then
    return { start_line = start_line, end_line = end_line }
  end
  return { start_line = start_line, end_line = end_line, cols = cols }
end

return M
