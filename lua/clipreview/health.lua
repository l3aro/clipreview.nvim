-- :checkhealth clipreview — clipboard, persistence and store diagnostics.
local M = {}

---@return nil
function M.check()
  local health = vim.health
  local config = require("clipreview.config").config
  health.start("clipreview")

  health.info(("register: %s"):format(tostring(config.register)))
  -- has("clipboard") sources the provider script and can throw in a half-initialised state.
  local has_ok, has = pcall(vim.fn.has, "clipboard")
  health.info(('has("clipboard"): %s'):format(has_ok and tostring(has) or ("error: " .. tostring(has))))

  local flag = vim.g.loaded_clipboard_provider
  health.info(("g:loaded_clipboard_provider: %s"):format(flag == nil and "unset" or tostring(flag)))

  local provider = vim.g.clipboard
  if type(provider) == "table" then
    health.info(("g:clipboard provider: %s"):format(tostring(provider.name or "anonymous")))
  end

  local ok_clipboard, clipboard = pcall(require, "clipreview.clipboard")
  if not ok_clipboard then
    health.error("clipreview.clipboard failed to load: " .. tostring(clipboard))
  elseif clipboard.provider_ok() then
    health.ok(("clipboard provider available for register %s"):format(tostring(config.register)))
  else
    health.warn("no clipboard provider: :ClipReview copy opens the payload instead of copying")
  end

  local osc52_ok, osc52 = pcall(require, "vim.ui.clipboard.osc52")
  local osc52_available = osc52_ok and type(osc52) == "table" and type(osc52.copy) == "function"
  if osc52_available then
    health.info('SSH: build vim.g.clipboard from require("vim.ui.clipboard.osc52")')
    health.info('     copy(reg)/paste(reg) factories, or set register = "0" to use the yank register.')
  else
    health.warn('require("vim.ui.clipboard.osc52") is unavailable: on SSH set register = "0"')
  end

  if config.persist then
    local ok_persist, persist = pcall(require, "clipreview.persist")
    local ok_scope, scope = pcall(require, "clipreview.scope")
    if ok_persist and ok_scope then
      health.ok("persistence enabled: " .. persist.path(scope.root(vim.api.nvim_get_current_buf())))
    else
      health.error("persistence enabled but clipreview.persist/scope failed to load")
    end
  else
    health.info("persistence disabled (config.persist = false)")
  end

  local ok_comments, comments = pcall(require, "clipreview.comments")
  if ok_comments then
    health.ok(("comments in store: %d"):format(comments.count()))
  else
    health.error("clipreview.comments failed to load: " .. tostring(comments))
  end
end

return M
