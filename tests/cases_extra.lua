-- tests/cases_extra.lua — extra regression cases beyond the ten spec-mandated
-- ones (visual-selection path, emptied-root persistence). Same registrar
-- contract as tests/cases.lua; tests/run.lua loads both.

return function(S, case)
  local eq, ok = S.eq, S.ok
  local contains, absent = S.contains, S.absent
  local repo, enter, open, write_file = S.repo, S.enter, S.open, S.write_file
  local add = S.add

  case("11 selection: charwise cols and linewise whole-line comment", function(cr)
    local dir = repo("review")
    enter(dir)
    write_file(dir .. "/sel.lua", { "line one", "0123456789abcdef", "line three", "line four" })
    local buf = open(dir .. "/sel.lua")
    local comments = require("clipreview.comments")
    local keys = function(k)
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(k, true, false, true), "x", false)
    end
    local prev_input = vim.ui.input
    vim.ui.input = function(_, cb)
      cb("selection note")
    end
    local okbody, err = pcall(function()
      vim.api.nvim_win_set_cursor(0, { 2, 6 })
      keys("vll<Esc>")
      local id = cr.comment_selection()
      ok(type(id) == "number", "comment_selection() id")
      local view = comments.view(id)
      eq(view.cols, { 6, 9 }, "charwise selection cols")
      eq(view.start_line, 2, "charwise selection start_line")
      eq(view.end_line, 2, "charwise selection end_line")
      eq(comments.snippet(view).lines, { "678" }, "charwise selection snippet")
      contains(cr.build(), "\n1. sel.lua:2:7-9\n", "charwise selection location")

      vim.api.nvim_win_set_cursor(0, { 2, 0 })
      keys("Vj<Esc>")
      local line_id = cr.comment_selection()
      ok(type(line_id) == "number", "linewise comment_selection() id")
      local line_view = comments.resolve(line_id)
      ok(line_view ~= nil, "linewise resolve")
      eq(line_view.cols, nil, "linewise cols")
      eq(line_view.has_cols, false, "linewise has_cols")
      eq(line_view.start_line, 2, "linewise start_line")
      eq(line_view.end_line, 3, "linewise end_line")
      contains(cr.build(), "sel.lua:2-3", "linewise location")
    end)
    vim.ui.input = prev_input
    if not okbody then
      error(err, 0)
    end
  end)

  case("12 persistence does not resurrect deleted or cleared comments", function(cr)
    local dir = repo("review")
    enter(dir)
    write_file(dir .. "/persist.lua", { "p1", "p2" })
    local buf = open(dir .. "/persist.lua")
    local persist = require("clipreview.persist")
    local root = require("clipreview.scope").root(buf)
    local ppath = persist.path(root)
    local json = function()
      return table.concat(vim.fn.readfile(ppath), "\n")
    end

    -- Isolate restore() from unrelated persisted roots on this machine.
    local orig_load_all = persist.load_all
    persist.load_all = function()
      return {}
    end
    local oksetup, errsetup = pcall(cr.setup, { persist = true })
    persist.load_all = orig_load_all
    if not oksetup then
      error(errsetup, 0)
    end

    local okbody, err = pcall(function()
      local id = add(cr, buf, { start_line = 1, end_line = 1, text = "delete me" })
      eq(vim.fn.filereadable(ppath), 1, "json file after add")
      eq(#persist.load(root), 1, "records after add")
      eq(cr.delete(id), true, "delete() return")
      eq(#persist.load(root), 0, "records after delete")
      contains(json(), '"records":[]', "empty record set after delete")

      add(cr, buf, { start_line = 2, end_line = 2, text = "clear me" })
      eq(#persist.load(root), 1, "records after second add")
      eq(cr.clear("all"), 1, "clear() count")
      eq(#persist.load(root), 0, "records after clear")
      contains(json(), '"records":[]', "empty record set after clear")
    end)

    persist.load_all = orig_load_all
    cr.setup({ persist = false })
    pcall(vim.fn.delete, ppath)
    pcall(vim.fn.delete, ppath .. ".tmp")
    pcall(vim.fn.delete, vim.fs.dirname(ppath), "d")
    if not okbody then
      error(err, 0)
    end
  end)

  case("13 inline callout above the commented block", function(cr)
    local dir = repo("review")
    enter(dir)
    write_file(dir .. "/callout.lua", { "one", "two", "three", "four" })
    local buf = open(dir .. "/callout.lua")
    local comments = require("clipreview.comments")
    local ns = vim.api.nvim_get_namespaces()["clipreview"]
    local details = function(id)
      local rec = comments.get(id)
      local res = vim.api.nvim_buf_get_extmark_by_id(buf, ns, rec.extmark, { details = true })
      return res[3] or {}, rec.extmark
    end
    -- Text of the virtual lines, chunk highlights dropped.
    local callout = function(d)
      local out = {}
      for _, line in ipairs(d.virt_lines or {}) do
        local text = {}
        for _, chunk in ipairs(line) do text[#text + 1] = chunk[1] end
        out[#out + 1] = table.concat(text)
      end
      return table.concat(out, "\n")
    end

    local okbody, err = pcall(function()
      local id = add(cr, buf, { start_line = 1, end_line = 2, text = "first thought" })
      local d, mark = details(id)
      eq(d.virt_lines_above, true, "callout is drawn above the block")
      eq(vim.trim(d.sign_text), "▌", "sign drawn with the callout")
      contains(callout(d), "╭─ ", "callout corner")
      contains(callout(d), "💬 first thought", "callout text")

      eq(cr.edit(id, "changed text"), true, "edit() return")
      local after, mark2 = details(id)
      eq(mark2, mark, "same extmark id after edit")
      eq(vim.trim(after.sign_text), "▌", "sign kept after the update")
      contains(callout(after), "changed text", "callout text after the update")
      absent(callout(after), "first thought", "stale callout text replaced")

      local multi = add(cr, buf, { start_line = 3, end_line = 3, text = "line one\nline two" })
      local md = details(multi)
      eq(#md.virt_lines, 2, "one virtual line per comment line")
      contains(callout(md), "   line two", "continuation line")

      -- Re-anchored (restored) records get the callout as well.
      local restored = assert(comments.restore({
        file = dir .. "/callout.lua", start_line = 1, end_line = 2, text = "restored note",
        fingerprint = require("clipreview.snippet").fingerprint({ "one", "two" }),
      }))
      eq(comments.anchor(restored, buf), true, "restored record re-anchors")
      local rd = details(restored)
      eq(rd.virt_lines_above, true, "callout on the re-anchored mark")
      contains(callout(rd), "restored note", "re-anchored callout text")

      cr.setup({ preview = { enabled = false } })
      local quiet = add(cr, buf, { start_line = 4, end_line = 4, text = "no callout" })
      local qd = details(quiet)
      eq(qd.virt_lines, nil, "no callout when the preview is disabled")
      eq(vim.trim(qd.sign_text), "▌", "sign still drawn when the preview is disabled")

      local payload = cr.build()
      absent(payload, "╭─", "payload has no callout corner")
      absent(payload, "💬", "payload has no callout bubble")
      contains(payload, "Comment: changed text", "payload keeps the comment text")

      local detached = assert(comments.restore({
        file = dir .. "/callout.lua", start_line = 1, end_line = 1, text = "detached",
      }))
      ok(pcall(cr.edit, detached, "detached text"), "detached record edit does not throw")
    end)
    cr.setup({})
    if not okbody then
      error(err, 0)
    end
  end)
end
