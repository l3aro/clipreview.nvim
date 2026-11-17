-- Leaf module: git root discovery, path shortening, header context.
-- No dependency on any other clipreview module.
local M = {}

--- Directory -> git toplevel string, or false when not inside a work tree.
---@type table<string, string|false>
local git_cache = {}

---@param s string
---@return string
local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

---@param out string
---@return string
local function first_line(out)
  return trim((out:gsub("\r", ""):gsub("\n.*$", "")))
end

--- First existing directory at or above `dir`.
---@param dir string
---@return string|nil
local function existing_dir(dir)
  local d = vim.fs.normalize(dir)
  while d and d ~= "" do
    if vim.fn.isdirectory(d) == 1 then
      return d
    end
    local parent = vim.fs.dirname(d)
    if parent == d then
      return nil
    end
    d = parent
  end
  return nil
end

--- Run git in `dir` and return trimmed stdout on success.
---@param args string[]
---@param dir string
---@return string|nil
local function git(args, dir)
  local ok, obj = pcall(vim.system, args, { cwd = dir, text = true })
  if not ok or type(obj) ~= "table" then
    return nil
  end
  local wok, res = pcall(function()
    return obj:wait()
  end)
  if not wok or type(res) ~= "table" or res.code ~= 0 or type(res.stdout) ~= "string" then
    return nil
  end
  local line = first_line(res.stdout)
  if line == "" then
    return nil
  end
  return line
end

--- Git toplevel for a directory, cached (non-git directories cache `false`).
---@param dir string
---@return string|nil
local function toplevel(dir)
  local cached = git_cache[dir]
  if cached ~= nil then
    return cached or nil
  end
  local top = git({ "git", "rev-parse", "--show-toplevel" }, dir)
  git_cache[dir] = top or false
  return top
end

---@param bufnr integer
---@return string|nil -- absolute path of the buffer's file, nil for unnamed / buftype ~= ""
function M.file(bufnr)
  bufnr = bufnr or 0
  if bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return nil
  end
  local ok, buftype = pcall(function()
    return vim.bo[bufnr].buftype
  end)
  if not ok or buftype ~= "" then
    return nil
  end
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == "" then
    return nil
  end
  local abs = vim.fn.fnamemodify(name, ":p")
  if vim.fn.isdirectory(abs) == 1 then
    return nil
  end
  return vim.fs.normalize(abs)
end

--- Scope root for a buffer: git toplevel of its file, else the current cwd.
---@param bufnr integer|nil
---@return string root
---@return boolean is_git
function M.root(bufnr)
  local cwd = vim.fs.normalize(vim.fn.getcwd())
  local file = M.file(bufnr)
  if not file then
    return cwd, false
  end
  local dir = existing_dir(vim.fs.dirname(file))
  if not dir then
    return cwd, false
  end
  local top = toplevel(dir)
  if not top then
    return cwd, false
  end
  return vim.fs.normalize(top), true
end

--- Repo name and branch for a git work tree root.
---@param root string
---@return { repo: string, branch: string }|nil
function M.context(root)
  if type(root) ~= "string" or root == "" then
    return nil
  end
  local dir = existing_dir(root)
  local top = dir and toplevel(dir)
  if not top then
    return nil
  end
  local branch = git({ "git", "rev-parse", "--abbrev-ref", "HEAD" }, dir)
    or git({ "git", "symbolic-ref", "--short", "HEAD" }, dir)
  if not branch then
    return nil
  end
  return { repo = vim.fs.basename(top), branch = branch }
end

---@param base string|nil
---@param file string
---@return string|nil
local function relative_to(base, file)
  if type(base) ~= "string" or base == "" then
    return nil
  end
  local rel = vim.fs.relpath(vim.fs.normalize(base), file)
  if type(rel) ~= "string" or rel == "" or rel == ".." or rel:match("^%.%./") then
    return nil
  end
  return rel
end

--- Display path for `file`: relative to `root` when under it, else relative to
--- the current cwd, else absolute.
---@param root string
---@param file string
---@return string
function M.shorten(root, file)
  if type(file) ~= "string" or file == "" then
    return ""
  end
  local abs = vim.fs.normalize(file)
  local rel = relative_to(root, abs) or relative_to(vim.fn.getcwd(), abs)
  return rel or abs
end

return M
