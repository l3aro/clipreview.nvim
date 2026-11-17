-- Display-only decorations: the callout rendered above a commented block.
-- Leaf module: no other clipreview module is required here.
local M = {}

---@param v any
---@return string
local function hl_or(v, fallback)
  if type(v) == "string" and v ~= "" then return v end
  return fallback
end

--- Virtual lines ("╭─ 💬 text") shown above a comment's anchor extmark.
---@param text string
---@param config table  -- merged clipreview config
---@return table|nil    -- extmark `virt_lines` chunks, nil when disabled or blank
function M.callout(text, config)
  if type(config) ~= "table" then return nil end
  local preview = config.preview
  if type(preview) ~= "table" or preview.enabled == false then return nil end
  if type(text) ~= "string" or not text:find("%S") then return nil end
  local signs = type(config.signs) == "table" and config.signs or {}
  local sign_hl, text_hl = hl_or(signs.hl, "DiagnosticInfo"), hl_or(preview.hl, "Comment")
  local lines = vim.split(text, "\n", { plain = true })
  local chunks = { { { "╭─ ", sign_hl }, { "💬 " .. lines[1], text_hl } } }
  for i = 2, #lines do
    chunks[#chunks + 1] = { { "   ", sign_hl }, { "   " .. lines[i], text_hl } }
  end
  return chunks
end

return M
