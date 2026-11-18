-- Leaf module: pure payload formatting. No other clipreview module is required here.
local M = {}

--- 0-indexed, end-exclusive cols -> 1-indexed, inclusive "c1-c2".
---@param cols integer[]
---@return string
local function cols_range(cols)
  return string.format("%d-%d", cols[1] + 1, cols[2])
end

--- "path:12-20" | "path:12" | "path:12:3-9"
---@param item { path: string, start_line: integer, end_line: integer, cols: integer[]|nil }
---@return string
function M.location(item)
  if item.cols then
    return string.format("%s:%d:%s", item.path, item.start_line, cols_range(item.cols))
  end
  if item.start_line == item.end_line then
    return string.format("%s:%d", item.path, item.start_line)
  end
  return string.format("%s:%d-%d", item.path, item.start_line, item.end_line)
end

--- Fenced block: location, then ```<lang>, exact lines, closing fence. No trailing newline.
--- The fence outgrows any literal backtick run in the lines, so selecting markdown
--- that contains ``` still pastes as one valid block.
---@param item { path: string, start_line: integer, end_line: integer, cols: integer[]|nil, lines: string[], lang: string|nil }
---@return string
function M.format_selection(item)
  local longest = 0
  for _, line in ipairs(item.lines or {}) do
    for run in line:gmatch("`+") do
      longest = math.max(longest, #run)
    end
  end
  local fence = string.rep("`", math.max(3, longest + 1))
  local out = { M.location(item), fence .. (item.lang or "") }
  for _, line in ipairs(item.lines or {}) do
    out[#out + 1] = line
  end
  out[#out + 1] = fence
  return table.concat(out, "\n")
end

--- Inline citation: always range form (`path:12-20`), always exactly one trailing space.
---@param item { path: string, start_line: integer, end_line: integer }
---@return string
function M.format_ref(item)
  return string.format("%s:%d-%d ", item.path, item.start_line, item.end_line)
end

--- Append `text` as an indented block, prefix on its first line, 3 spaces on continuations.
---@param lines string[]
---@param prefix string
---@param text string
local function append_indented(lines, prefix, text)
  local nl = text:find("\n", 1, true)
  lines[#lines + 1] = prefix .. (nl and text:sub(1, nl - 1) or text)
  while nl do
    local next_nl = text:find("\n", nl + 1, true)
    lines[#lines + 1] = "   " .. text:sub(nl + 1, (next_nl and next_nl - 1) or #text)
    nl = next_nl
  end
end

--- Agent-ready payload. Items must already be sorted by the caller.
---@param items { path: string, start_line: integer, end_line: integer, cols: integer[]|nil,
---               lines: string[], more: integer, text: string, shifted: boolean }[]
---@param opts { header: string|nil, footer: string|nil, quote: string|nil }|nil
---@return string
function M.format(items, opts)
  if type(items) ~= "table" or #items == 0 then
    return ""
  end
  opts = opts or {}
  local quote = opts.quote or "> "

  local blocks = {}
  for i, item in ipairs(items) do
    local lines = { string.format("%d. %s", i, M.location(item)) }
    for _, src in ipairs(item.lines or {}) do
      lines[#lines + 1] = "   " .. quote .. src
    end
    if (item.more or 0) > 0 then
      lines[#lines + 1] = string.format("   %s… (+%d more lines)", quote, item.more)
    end
    if item.shifted then
      lines[#lines + 1] = "   " .. quote .. "(lines may have shifted on disk)"
    end
    append_indented(lines, "   Comment: ", item.text or "")
    blocks[#blocks + 1] = table.concat(lines, "\n")
  end

  local body = table.concat(blocks, "\n\n")
  if opts.header and opts.header ~= "" then
    body = opts.header .. "\n\n" .. body
  end
  if opts.footer and opts.footer ~= "" then
    body = body .. "\n\n" .. opts.footer
  end
  return body
end

return M
