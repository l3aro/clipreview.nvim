-- Leaf module: defaults + deep merge. No other clipreview module required here.
local M = {}

M.defaults = {
  keymaps = {
    comment = "<leader>ac",
    list = "<leader>al",
    copy = "<leader>ay",
    preview = "<leader>aY",
    ref = "<leader>ai",
    selection = "<leader>as",
  },
  register = "+",
  clear_after_copy = false,
  scope = "repo", -- "repo" | "all"
  snippet = {
    max_lines = 10,
    quote = "> ",
  },
  header = {
    enabled = true,
    text = "Code review comments from my editor",
    repo_branch = true,
  },
  footer = "Please address each comment. Reply with what you changed per item.",
  signs = {
    text = "▌",
    hl = "DiagnosticInfo",
    line_hl = "Visual",
  },
  preview = {
    enabled = true,
    hl = "Comment",
  },
  persist = false,
  list_ui = "float", -- "float" | "ui.select"
}

--- Merged configuration table. Replaced in place by setup().
M.config = vim.deepcopy(M.defaults)

local function merge(dst, src)
  for k, v in pairs(src) do
    if type(v) == "table" and type(dst[k]) == "table" then
      merge(dst[k], v)
    else
      dst[k] = v
    end
  end
  return dst
end

---@param opts table|nil
---@return table config
function M.setup(opts)
  local fresh = vim.deepcopy(M.defaults)
  if opts then
    merge(fresh, opts)
  end
  M.config = fresh
  return M.config
end

return M
