-- tests/support.lua — shared helpers for clipreview.nvim's headless suite.
-- Loaded by tests/run.lua through dofile() with an absolute path, because the
-- cases chdir into tmp repos and the documented rtp entry is relative.

local M = {}

local TMP = {}

---@param v any
---@return string
function M.fmt(v)
  if type(v) == "string" then
    return string.format("%q", v)
  end
  if type(v) == "table" then
    local okv, s = pcall(vim.inspect, v)
    if okv then
      return (s:gsub("%s+", " "))
    end
  end
  return tostring(v)
end

function M.eq(actual, expected, label)
  if not vim.deep_equal(actual, expected) then
    error(("%s: expected %s, got %s"):format(label, M.fmt(expected), M.fmt(actual)), 0)
  end
end

function M.ok(cond, label)
  if not cond then
    error(("%s: expected truthy, got %s"):format(label, M.fmt(cond)), 0)
  end
end

function M.contains(s, needle, label)
  if type(s) ~= "string" or not s:find(needle, 1, true) then
    error(("%s: %s does not contain %s"):format(label, M.fmt(s), M.fmt(needle)), 0)
  end
end

function M.absent(s, needle, label)
  if type(s) == "string" and s:find(needle, 1, true) then
    error(("%s: %s unexpectedly contains %s"):format(label, M.fmt(s), M.fmt(needle)), 0)
  end
end

function M.matches(s, pat, label)
  if type(s) ~= "string" or not s:find(pat) then
    error(("%s: %s does not match %s"):format(label, M.fmt(s), M.fmt(pat)), 0)
  end
end

function M.tmpdir()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  dir = vim.uv.fs_realpath(dir) or dir
  TMP[#TMP + 1] = dir
  return dir
end

function M.write_file(path, lines)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  if vim.fn.writefile(lines, path) ~= 0 then
    error("writefile failed: " .. path, 0)
  end
end

function M.git(cwd, args)
  local okp, proc = pcall(vim.system, vim.list_extend({ "git" }, args), { cwd = cwd, text = true })
  if not okp then
    error("vim.system failed: " .. tostring(proc), 0)
  end
  local res = proc:wait()
  if res.code ~= 0 then
    error(("git %s failed (%s): %s"):format(table.concat(args, " "), res.code, vim.trim(res.stderr or "")), 0)
  end
  return vim.trim(res.stdout or "")
end

--- Fake git repo at <tmp>/demo so header repo naming is deterministic.
--- A commit is required: `git rev-parse --abbrev-ref HEAD` fails on an unborn
--- branch, which is exactly the "header context unavailable" path.
function M.repo(branch)
  local dir = M.tmpdir() .. "/demo"
  vim.fn.mkdir(dir, "p")
  M.git(dir, { "init", "-q" })
  if branch then
    M.git(dir, { "symbolic-ref", "HEAD", "refs/heads/" .. branch })
  end
  M.git(dir, {
    "-c",
    "user.email=clipreview@example.com",
    "-c",
    "user.name=clipreview-test",
    "commit",
    "-q",
    "--allow-empty",
    "-m",
    "init",
  })
  return dir
end

function M.enter(dir)
  vim.cmd.cd(vim.fn.fnameescape(dir))
end

function M.open(path)
  vim.cmd.edit(vim.fn.fnameescape(path))
  return vim.api.nvim_get_current_buf()
end

function M.add(cr, bufnr, spec)
  local s = vim.tbl_extend("force", { bufnr = bufnr, text = "note" }, spec or {})
  local id = cr.comment(s)
  if type(id) ~= "number" then
    error("comment() returned " .. M.fmt(id) .. " although text was supplied", 0)
  end
  return id
end

-- Clipboard fixture. nvim caches the provider per session, so each case that
-- needs clipboard writes installs the fake provider: dict first, then the flag
-- is cleared so `has("clipboard")` sources the provider script on demand. Once
-- a provider has been loaded, nvim freezes the flag state and a later `has()`
-- raises "missing required variable g:loaded_clipboard_provider"; the install
-- then sets the flag to 2 (provider available), the state nvim accepted (setreg
-- + getreg round-trip verified after the fallback). Startup values are captured
-- once and restored in teardown.
local START_CLIPBOARD = vim.g.clipboard
local START_FLAG = vim.g.loaded_clipboard_provider

---@return table store  -- lines written by the provider, per register
function M.fake_clipboard()
  local store = {}
  vim.g.clipboard = {
    name = "clipreview-test",
    copy = {
      ["+"] = function(lines) store["+"] = lines end,
      ["*"] = function(lines) store["*"] = lines end,
    },
    paste = {
      ["+"] = function() return store["+"] or {} end,
      ["*"] = function() return store["*"] or {} end,
    },
    cache_enabled = 0,
  }
  vim.g.loaded_clipboard_provider = nil
  local okh, has = pcall(vim.fn.has, "clipboard")
  if not okh or has ~= 1 then
    vim.g.loaded_clipboard_provider = 2
  end
  return store
end

---@return nil
function M.reset_clipboard()
  vim.g.clipboard = START_CLIPBOARD
  vim.g.loaded_clipboard_provider = START_FLAG
end

---@return nil
function M.no_clipboard()
  vim.g.clipboard = nil
  vim.g.loaded_clipboard_provider = 0
end

function M.reg_text(reg)
  local okg, lines = pcall(vim.fn.getreg, reg, 1, 1)
  if not okg then
    return "<getreg failed: " .. tostring(lines) .. ">"
  end
  return table.concat(lines, "\n")
end

local unpack = table.unpack or unpack

local function pack(...)
  return { n = select("#", ...), ... }
end

function M.with_notify_spy(fn)
  local calls = {}
  local orig = vim.notify
  vim.notify = function(msg, level, opts)
    calls[#calls + 1] = { msg = tostring(msg), level = level or vim.log.levels.INFO, opts = opts }
  end
  local res = pack(pcall(fn))
  vim.notify = orig
  if not res[1] then
    error(res[2], 0)
  end
  return calls, unpack(res, 2, res.n)
end

function M.joined(calls)
  local out = {}
  for _, c in ipairs(calls) do
    out[#out + 1] = c.msg
  end
  return table.concat(out, "\n")
end

function M.teardown(prev_cwd)
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    pcall(vim.api.nvim_buf_delete, b, { force = true })
  end
  pcall(vim.cmd.cd, vim.fn.fnameescape(prev_cwd))
  for _, dir in ipairs(TMP) do
    pcall(vim.fn.delete, dir, "rf")
  end
  TMP = {}
  M.reset_clipboard()
end

return M
