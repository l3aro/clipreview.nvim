-- Leaf module: honest clipboard access + markdown preview buffer. No other clipreview module.
local M = {}

local PREVIEW_NAME = "clipreview-export.md"

--- Clipboard usability, probed on nvim 0.12 (`runtime/autoload/provider/clipboard.vim`):
--- `has("clipboard")` sources the provider script on first use and returns 1 iff a provider was
--- found. The flag it leaves behind is 0 = none, 2 = available; value 1 only appears when a user
--- writes it by hand, which makes the script `finish` early and leaves `provider#clipboard#Call`
--- undefined, so 1 must never be treated as usable. `exists("g:loaded_clipboard_provider")` is
--- useless (1 whenever the flag exists, including 0).
--- A write is still only reported as successful after a readback in `M.write`.
---@return boolean
function M.provider_ok()
  -- An explicit dict (user config, osc52, tests) is authoritative for *availability*; whether the
  -- write actually lands is still decided by the readback in M.write.
  if type(vim.g.clipboard) == "table" then
    return true
  end
  -- pcall: has() throws when the flag is unset but the provider script state is half-initialised.
  local ok, has = pcall(vim.fn.has, "clipboard")
  return ok and has == 1
end

---@param reg string
---@return boolean system register ("+" or "*") — the only ones that need a provider
local function system_register(reg)
  return reg == "+" or reg == "*"
end

--- Write and verify by reading the register back. Internal registers ("0"–"9", "a"–"z", "-")
--- are written by nvim itself and work without any clipboard provider, which is the documented
--- SSH workaround (`register = "0"`).
---@param text string
---@param reg string
---@return boolean ok, string|nil err   -- "no-provider" | "setreg-failed" | "verify-failed"
function M.write(text, reg)
  if system_register(reg) and not M.provider_ok() then
    return false, "no-provider"
  end
  if not pcall(vim.fn.setreg, reg, text) then
    return false, "setreg-failed"
  end
  local got_ok, got = pcall(vim.fn.getreg, reg, 1, 1)
  if not got_ok or type(got) ~= "table" or table.concat(got, "\n") ~= text then
    return false, "verify-failed"
  end
  return true, nil
end

---@param name string
---@return boolean
local function name_taken(name)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) then
      local bufname = vim.api.nvim_buf_get_name(buf)
      if bufname ~= "" and vim.fs.basename(bufname) == name then
        return true
      end
    end
  end
  return false
end

--- `clipreview-export.md`, else `clipreview-export-1.md`, `-2`, …
---@return string
local function unique_name()
  if not name_taken(PREVIEW_NAME) then
    return PREVIEW_NAME
  end
  local stem, ext = PREVIEW_NAME:match("^(.+)(%.[^.]*)$")
  stem, ext = stem or PREVIEW_NAME, ext or ""
  local i = 1
  while name_taken(string.format("%s-%d%s", stem, i, ext)) do
    i = i + 1
  end
  return string.format("%s-%d%s", stem, i, ext)
end

--- Markdown scratch buffer holding the payload. Shown in the current window when possible.
---@param text string
---@return integer bufnr
function M.preview(text)
  text = type(text) == "string" and text or ""

  local buf = vim.api.nvim_create_buf(false, true) -- unlisted scratch: buftype=nofile
  pcall(vim.api.nvim_buf_set_name, buf, unique_name())

  local lines = {}
  local from = 1
  while true do
    local nl = text:find("\n", from, true)
    lines[#lines + 1] = text:sub(from, (nl and nl - 1) or #text)
    if not nl then
      break
    end
    from = nl + 1
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "markdown"

  pcall(function()
    vim.api.nvim_win_set_buf(0, buf)
  end)
  return buf
end

return M
