-- Comment views + agent payload construction.
local M = {}

local config = require("clipreview.config")

local function cfg()
  return config.config
end

---@param scope_name string|nil
---@return table[] views in (path, line) order for the configured scope
function M.views(scope_name)
  local comments = require("clipreview.comments")
  local scope = require("clipreview.scope")
  local sc = scope_name or cfg().scope
  local ids = comments.ids()
  if sc ~= "all" then
    local root = scope.root(0)
    local filtered = {}
    for _, id in ipairs(ids) do
      local rec = comments.get(id)
      if rec and rec.root == root then
        filtered[#filtered + 1] = id
      end
    end
    ids = filtered
  end
  local out = {}
  for _, id in ipairs(ids) do
    local view = comments.view(id)
    if view then
      out[#out + 1] = view
    end
  end
  return out
end

---@param scope_name string
---@param views table[]
---@return { repo: string, branch: string }|nil
local function header_context(scope_name, views)
  if not cfg().header.enabled or not cfg().header.repo_branch then
    return nil
  end
  local scope = require("clipreview.scope")
  local root, is_git
  if scope_name == "all" then
    for _, view in ipairs(views) do
      if root == nil then
        root, is_git = view.root, view.is_git
      elseif view.root ~= root then
        return nil
      end
    end
  else
    root, is_git = scope.root(0)
  end
  if not root or not is_git then
    return nil
  end
  return scope.context(root)
end

---@param scope_name string
---@param views table[]
---@return string|nil
local function build_header(scope_name, views)
  if not cfg().header.enabled then
    return nil
  end
  local text = cfg().header.text
  local ctx = header_context(scope_name, views)
  if ctx and ctx.repo and ctx.branch then
    return string.format("%s (repo: %s, branch: %s):", text, ctx.repo, ctx.branch)
  end
  return text .. ":"
end

---@param scope_name string|nil
---@return string payload, integer n
function M.build(scope_name)
  local sc = scope_name or cfg().scope
  local views = M.views(sc)
  if #views == 0 then
    return "", 0
  end
  local comments = require("clipreview.comments")
  local prompt = require("clipreview.prompt")
  local scope = require("clipreview.scope")
  local items = {}
  for _, view in ipairs(views) do
    local snip = comments.snippet(view)
    items[#items + 1] = {
      path = scope.shorten(view.root, view.file),
      start_line = view.start_line,
      end_line = view.end_line,
      cols = view.cols,
      lines = snip.lines,
      more = snip.more,
      shifted = snip.shifted,
      text = view.text,
    }
  end
  local text = prompt.format(items, {
    header = build_header(sc, views),
    footer = cfg().footer,
    quote = cfg().snippet.quote,
    max_lines = cfg().snippet.max_lines,
  })
  return text, #items
end

return M
