-- tests/run.lua — headless, zero-dependency entry point for clipreview.nvim.
-- Usage: nvim --headless --clean --cmd "set rtp+=." -l tests/run.lua
--
-- Cases (tests/cases.lua) assert the contract's API exactly; helpers and
-- fixtures live in tests/support.lua. Every case is isolated: fresh setup{},
-- cleared store, its own tmp repo, and a fake clipboard provider restored
-- around it. A case that raises is reported as FAIL, never dumped as a crash.

-- The documented invocation appends a RELATIVE rtp entry ("."), which nvim
-- resolves against the cwd at require time. Cases chdir into tmp repos, and the
-- plugin requires sibling modules lazily, so pin an absolute entry and warm the
-- module hub before anything changes cwd.
local ROOT = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:append(ROOT)
-- Warm the hub before any chdir: sibling modules are required lazily, and the
-- documented rtp entry is relative.
require("clipreview")

local support = dofile(ROOT .. "/tests/support.lua")

local cases = {}
local function case(name, fn)
  cases[#cases + 1] = { name = name, fn = fn }
end
dofile(ROOT .. "/tests/cases.lua")(support, case)
dofile(ROOT .. "/tests/cases_extra.lua")(support, case)

-- Cases always supply the comment text; a prompting comment() must fail rather
-- than block a headless run.
vim.ui.input = function(_, on_confirm)
  if on_confirm then
    on_confirm(nil)
  end
end

local passed, failed = 0, 0
local failed_names = {}

for _, c in ipairs(cases) do
  local prev_cwd = vim.fn.getcwd()
  support.reset_clipboard()
  local okrun, err = xpcall(function()
    local cr = require("clipreview")
    cr.setup({})
    cr.clear("all")
    c.fn(cr)
  end, function(e)
    if type(e) == "string" then
      return e
    end
    return support.fmt(e)
  end)
  support.teardown(prev_cwd)

  if okrun then
    passed = passed + 1
    io.write("PASS " .. c.name .. "\n")
  else
    failed = failed + 1
    failed_names[#failed_names + 1] = c.name
    io.write("FAIL " .. c.name .. "\n")
    io.write("     " .. tostring(err) .. "\n")
  end
  io.flush()
end

io.write(("\n%d passed, %d failed, %d total\n"):format(passed, failed, #cases))
if failed > 0 then
  io.write("failed: " .. table.concat(failed_names, "; ") .. "\n")
  os.exit(1)
end
