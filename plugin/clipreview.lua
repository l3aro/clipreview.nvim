if vim.g.loaded_clipreview == 1 then
  return
end
vim.g.loaded_clipreview = 1

require("clipreview.commands").install()
