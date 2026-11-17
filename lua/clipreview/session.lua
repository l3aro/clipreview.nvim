-- Persistence glue: save current views, restore JSON records, re-anchor them on buffer load.
local M = {}

local config = require("clipreview.config")

local AUTOCMD_GROUP = "clipreview_persist"
local restored = false

local function cfg()
  return config.config
end

--- Roots that have ever been persisted (or restored) this session. Needed so deleting the last
--- comment of a scope rewrites its JSON with an empty record set instead of leaving stale
--- comments behind for the next session.
---@type table<string, boolean>
local known_roots = {}

---@param views table[]
function M.save(views)
  if not cfg().persist then
    return
  end
  local comments = require("clipreview.comments")
  local persist = require("clipreview.persist")
  local by_root = {}
  for _, view in ipairs(views) do
    local rec = comments.get(view.id)
    if rec then
      local list = by_root[view.root]
      if not list then
        list = {}
        by_root[view.root] = list
      end
      known_roots[view.root] = true
      list[#list + 1] = {
        file = view.file,
        root = view.root,
        is_git = view.is_git,
        start_line = view.start_line,
        end_line = view.end_line,
        cols = view.cols,
        text = view.text,
        created_at = view.created_at,
        fingerprint = rec.fingerprint,
      }
    end
  end
  for root, records in pairs(by_root) do
    persist.save(root, records)
  end
  for root in pairs(known_roots) do
    if not by_root[root] then
      persist.save(root, {})
    end
  end
end

---@param bufnr integer
---@return boolean anchored
function M.anchor_buffer(bufnr)
  local comments = require("clipreview.comments")
  local file = require("clipreview.scope").file(bufnr)
  if not file then
    return false
  end
  local anchored = false
  for _, id in ipairs(comments.ids()) do
    local view = comments.view(id)
    if view and not view.live and view.file == file then
      anchored = comments.anchor(id, bufnr) or anchored
    end
  end
  return anchored
end

function M.anchor_loaded_buffers()
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      M.anchor_buffer(bufnr)
    end
  end
end

function M.install_hooks()
  local group = vim.api.nvim_create_augroup(AUTOCMD_GROUP, { clear = true })
  vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
    group = group,
    callback = function(args)
      M.anchor_buffer(args.buf)
    end,
  })
end

function M.clear_hooks()
  pcall(vim.api.nvim_del_augroup_by_name, AUTOCMD_GROUP)
end

--- Load every persisted root once per session and try to re-anchor its records.
function M.restore()
  if restored or not cfg().persist then
    return
  end
  restored = true
  local comments = require("clipreview.comments")
  for _, entry in ipairs(require("clipreview.persist").load_all()) do
    if type(entry.root) == "string" and entry.root ~= "" then
      known_roots[entry.root] = true
    end
    for _, rec in ipairs(entry.records or {}) do
      if type(rec) == "table" and type(rec.file) == "string" then
        rec.root = rec.root or entry.root
        rec.is_git = rec.is_git == true
        comments.restore(rec)
      end
    end
  end
  M.anchor_loaded_buffers()
end

return M
