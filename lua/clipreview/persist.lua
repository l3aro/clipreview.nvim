-- Leaf module: opt-in JSON persistence under stdpath("state"). No other clipreview module
-- besides the leaf config is required (lazily).
local M = {}

local DIR = "clipreview"

---@return boolean
function M.enabled()
  return require("clipreview.config").config.persist == true
end

--- One file per scope root: <state>/clipreview/<sha256(root):sub(1,16)>.json
---@param root string
---@return string
function M.path(root)
  local digest = vim.fn.sha256(root or ""):sub(1, 16)
  return vim.fs.joinpath(vim.fn.stdpath("state"), DIR, digest .. ".json")
end

--- Finite number -> integer; anything else (strings, tables, NaN, ±inf) -> nil.
---@param value any
---@return integer|nil
local function as_int(value)
  if type(value) ~= "number" or value ~= value then
    return nil
  end
  if value <= -math.huge or value >= math.huge then
    return nil
  end
  return math.floor(value)
end

--- JSON-safe subset: bufnr/extmark die with the session and are never stored.
--- Also the decoder: tolerates malformed-but-decodable fields, never throws.
---@param records table[]|nil
---@return table[]
local function sanitize(records)
  local out = {}
  if type(records) ~= "table" then
    return out
  end
  for _, rec in ipairs(records) do
    if type(rec) == "table" and type(rec.file) == "string" then
      local cols
      if type(rec.cols) == "table" then
        local first, second = as_int(rec.cols[1]), as_int(rec.cols[2])
        if first and second then
          cols = { first, second }
        end
      end
      out[#out + 1] = {
        file = rec.file,
        -- root/is_git keep a restored comment's scope and header context intact.
        root = type(rec.root) == "string" and rec.root or nil,
        is_git = rec.is_git == true,
        start_line = as_int(rec.start_line) or 0,
        end_line = as_int(rec.end_line) or 0,
        cols = cols,
        text = tostring(rec.text or ""),
        created_at = as_int(rec.created_at) or 0,
        fingerprint = tostring(rec.fingerprint or ""),
      }
    end
  end
  return out
end

---@param payload string
---@param path string
---@return boolean
local function write_atomic(payload, path)
  if not pcall(vim.fn.mkdir, vim.fs.dirname(path), "p") then
    return false
  end
  local tmp = path .. ".tmp"
  if not pcall(vim.fn.writefile, { payload }, tmp) then
    pcall(vim.fn.delete, tmp)
    return false
  end
  local ok, renamed = pcall(vim.uv.fs_rename, tmp, path)
  if not ok or not renamed then
    pcall(vim.fn.delete, tmp)
    return false
  end
  return true
end

---@param path string
---@return table|nil decoded
local function read_json(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or type(lines) ~= "table" or #lines == 0 then
    return nil
  end
  local decoded_ok, decoded = pcall(vim.json.decode, table.concat(lines, "\n"))
  if not decoded_ok or type(decoded) ~= "table" then
    return nil
  end
  return decoded
end

--- No-op (returns false) when persistence is disabled.
---@param root string
---@param records table[]
---@return boolean ok
function M.save(root, records)
  if not M.enabled() then
    return false
  end
  local ok, payload = pcall(vim.json.encode, { root = root, records = sanitize(records) })
  if not ok or type(payload) ~= "string" then
    return false
  end
  return write_atomic(payload, M.path(root))
end

--- Records of one root; empty on a missing or corrupt file. Never throws.
---@param root string
---@return table[]
function M.load(root)
  local decoded = read_json(M.path(root))
  if not decoded then
    return {}
  end
  return sanitize(decoded.records)
end

--- Every persisted root file, sorted by root.
---@return { root: string, records: table[] }[]
function M.load_all()
  local dir = vim.fs.joinpath(vim.fn.stdpath("state"), DIR)
  local out = {}
  local handle = vim.uv.fs_scandir(dir)
  if not handle then
    return out
  end
  while true do
    local name = vim.uv.fs_scandir_next(handle)
    if not name then
      break
    end
    if name:sub(-5) == ".json" then
      local decoded = read_json(vim.fs.joinpath(dir, name))
      if decoded and type(decoded.root) == "string" then
        out[#out + 1] = { root = decoded.root, records = sanitize(decoded.records) }
      end
    end
  end
  table.sort(out, function(a, b)
    return a.root < b.root
  end)
  return out
end

return M
