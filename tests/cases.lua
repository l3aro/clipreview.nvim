-- tests/cases.lua — the ten mandated clipreview.nvim cases, in spec order.
-- Returns a registrar: cases(S, case) where S is tests/support.lua and case()
-- adds { name, fn } to the runner's list.

return function(S, case)
  local eq, ok = S.eq, S.ok
  local contains, absent, matches = S.contains, S.absent, S.matches
  local repo, tmpdir, enter, open, write_file = S.repo, S.tmpdir, S.enter, S.open, S.write_file
  local add, with_notify_spy, joined = S.add, S.with_notify_spy, S.joined
  local reg_text, no_clipboard, fmt = S.reg_text, S.no_clipboard, S.fmt
  local fake_clipboard = S.fake_clipboard

  case("1 extmark anchoring: range 3-5 shifts to 5-7 after inserting 2 lines", function(cr)
    local dir = repo("review")
    enter(dir)
    local lines = {}
    for i = 1, 10 do
      lines[i] = "l" .. i
    end
    write_file(dir .. "/lines.lua", lines)
    local buf = open(dir .. "/lines.lua")
    add(cr, buf, { start_line = 3, end_line = 5, text = "keep range" })

    vim.api.nvim_buf_set_lines(buf, 0, 0, false, { "new1", "new2" })

    local items = cr.list()
    eq(#items, 1, "list length after insert")
    eq(items[1].start_line, 5, "start_line after insert")
    eq(items[1].end_line, 7, "end_line after insert")
    eq(items[1].text, "keep range", "comment text")
    eq(items[1].cols, nil, "cols for a whole-line comment")
  end)

  case("2 mid-line cols: snippet is the exact slice, location prints :c1-c2", function(cr)
    local dir = repo("review")
    enter(dir)
    write_file(dir .. "/src/cols.lua", {
      "local head = 1",
      "local value = compute(alpha, beta)",
      "return value",
    })
    local buf = open(dir .. "/src/cols.lua")
    local id = add(cr, buf, { start_line = 2, end_line = 2, cols = { 14, 21 }, text = "partial" })

    local comments = require("clipreview.comments")
    local view = comments.view(id)
    ok(view ~= nil, "comments.view(id)")
    local snip = comments.snippet(view)
    eq(snip.lines, { "compute" }, "snippet lines for cols")
    eq(snip.more, 0, "snippet.more")
    eq(snip.shifted, false, "snippet.shifted for a live comment")

    local payload = cr.build()
    contains(payload, "\n1. src/cols.lua:2:15-21\n", "location with cols")
    contains(payload, "   > compute\n", "snippet line in payload")
    contains(payload, "   Comment: partial\n", "comment line in payload")
  end)

  case("3 payload shape: two files sorted, header/footer, clipping, no trailing newline", function(cr)
    local dir = repo("review")
    enter(dir)
    write_file(dir .. "/src/a.lua", { "alpha one", "alpha two", "alpha three", "alpha four", "alpha five" })
    write_file(dir .. "/src/b.lua", { "beta one", "beta two", "beta three" })
    cr.setup({ snippet = { max_lines = 2 } })

    local bbuf = open(dir .. "/src/b.lua")
    add(cr, bbuf, { start_line = 2, end_line = 2, text = "issue in b" })
    local abuf = open(dir .. "/src/a.lua")
    add(cr, abuf, { start_line = 2, end_line = 4, text = "issue in a" })

    local payload, n = cr.build()
    eq(n, 2, "item count")
    local expected = table.concat({
      "Code review comments from my editor (repo: demo, branch: review):",
      "",
      "1. src/a.lua:2-4",
      "   > alpha two",
      "   > alpha three",
      "   > … (+1 more lines)",
      "   Comment: issue in a",
      "",
      "2. src/b.lua:2",
      "   > beta two",
      "   Comment: issue in b",
      "",
      "Please address each comment. Reply with what you changed per item.",
    }, "\n")
    eq(payload, expected, "payload")
    ok(payload:sub(-1) ~= "\n", "payload must not end with a newline")
  end)

  case("4 no provider: copy -> false,'no-provider', preview opens, no success notify", function(cr)
    local dir = repo("review")
    enter(dir)
    write_file(dir .. "/noprov.lua", { "a", "b" })
    local buf = open(dir .. "/noprov.lua")
    add(cr, buf, { start_line = 1, end_line = 1, text = "needs copy" })

    no_clipboard()

    local calls, copied, err = with_notify_spy(function()
      return cr.copy()
    end)
    eq(copied, false, "copy() ok")
    eq(err, "no-provider", "copy() err")

    matches(vim.api.nvim_buf_get_name(0), "clipreview%-export%.md$", "preview buffer name")
    eq(vim.bo.filetype, "markdown", "preview filetype")
    local preview = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
    contains(preview, "1. noprov.lua:1", "preview holds the payload")

    local text = joined(calls)
    absent(text, "copied", "success notification")
    absent(text, "Copied", "success notification")
    contains(text, "clipboard provider", "warning about the missing provider")
  end)

  case("5 happy path: copy() writes build() to the '+' register", function(cr)
    local dir = repo("review")
    enter(dir)
    write_file(dir .. "/happy.lua", { "one", "two" })
    local buf = open(dir .. "/happy.lua")
    add(cr, buf, { start_line = 2, end_line = 2, text = "happy" })
    fake_clipboard()

    local expected = cr.build()
    ok(#expected > 0, "build() empty")
    local calls, copied, err = with_notify_spy(function()
      return cr.copy()
    end)
    eq(copied, true, "copy() ok (err=" .. fmt(err) .. ")")
    eq(err, nil, "copy() err")
    eq(reg_text("+"), expected, "register content")
    contains(joined(calls), "copied 1 comment", "success notification")
  end)

  case("6 delete: gone from list, extmark cleared, payload drops it", function(cr)
    local dir = repo("review")
    enter(dir)
    write_file(dir .. "/del.lua", { "a", "b", "c" })
    local buf = open(dir .. "/del.lua")
    local keep = add(cr, buf, { start_line = 1, end_line = 1, text = "keep me" })
    local gone = add(cr, buf, { start_line = 3, end_line = 3, text = "delete me" })

    local comments = require("clipreview.comments")
    local rec = comments.get(gone)
    ok(type(rec) == "table", "comments.get(gone) record")
    ok(type(rec.extmark) == "number", "record extmark id")
    local extmark = rec.extmark

    eq(cr.delete(gone), true, "delete() return")
    local ids = {}
    for _, item in ipairs(cr.list()) do
      ids[#ids + 1] = item.id
    end
    eq(ids, { keep }, "remaining ids")
    eq(comments.count(), 1, "comments.count()")
    local ns = vim.api.nvim_create_namespace("clipreview")
    local mark = vim.api.nvim_buf_get_extmark_by_id(buf, ns, extmark, {})
    eq(#mark, 0, "extmark after delete")
    absent(cr.build(), "delete me", "payload after delete")
  end)

  case("7 zero comments: build() -> '',0 and the register is untouched", function(cr)
    fake_clipboard()
    vim.fn.setreg("+", "sentinel")

    local text, n = cr.build()
    eq(text, "", "empty payload")
    eq(n, 0, "item count")

    local calls, copied, err = with_notify_spy(function()
      return cr.copy()
    end)
    eq(copied, false, "copy() ok")
    eq(err, "empty", "copy() err")
    eq(reg_text("+"), "sentinel", "register must not be overwritten")
    ok(#calls > 0, "expected an informational notification")
    absent(joined(calls), "copied", "no success notification")
  end)

  case("8 outside git: no repo/branch header, path relative to cwd", function(cr)
    local dir = tmpdir()
    enter(dir)
    write_file(dir .. "/main.lua", { "alpha", "beta" })
    local buf = open(dir .. "/main.lua")
    add(cr, buf, { start_line = 1, end_line = 1, text = "plain" })

    local payload = cr.build()
    eq(payload:match("^[^\n]*"), "Code review comments from my editor:", "header without repo/branch")
    absent(payload, "repo:", "repo context")
    absent(payload, "branch:", "branch context")
    contains(payload, "\n1. main.lua:1\n", "location relative to cwd")
    absent(payload, dir, "absolute path in payload")
  end)

  case("9 :bd! fallback snippet, disk rewrite adds the shifted note", function(cr)
    local dir = repo("review")
    enter(dir)
    local path = dir .. "/shift.lua"
    write_file(path, { "l1", "l2", "l3", "l4", "l5", "l6" })
    local buf = open(path)
    local id = add(cr, buf, { start_line = 2, end_line = 3, text = "disk fallback" })

    vim.cmd("silent! bd!")
    local still_loaded = vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_is_loaded(buf)
    eq(still_loaded, false, "buffer still loaded after :bd!")

    local before = cr.build()
    contains(before, "1. shift.lua:2-3", "fallback location")
    contains(before, "   > l2\n   > l3\n", "fallback snippet read from disk")
    absent(before, "lines may have shifted on disk", "shift note before the disk change")

    local comments = require("clipreview.comments")
    eq(comments.snippet(comments.view(id)).shifted, false, "shifted before rewrite")

    write_file(path, { "x1", "x2", "x3", "x4", "x5", "x6", "x7" })

    local after = cr.build()
    contains(after, "1. shift.lua:2-3", "location after rewrite")
    contains(after, "   > (lines may have shifted on disk)", "shift note after rewrite")
    eq(comments.snippet(comments.view(id)).shifted, true, "shifted after rewrite")
  end)

  case("10 ref(): 'path:12-20 ' with exactly one trailing space", function(cr)
    local dir = repo("review")
    enter(dir)
    local lines = {}
    for i = 1, 25 do
      lines[i] = "line " .. i
    end
    write_file(dir .. "/src/ref.lua", lines)
    open(dir .. "/src/ref.lua")

    local ref = cr.ref({ start_line = 12, end_line = 20 })
    eq(ref, "src/ref.lua:12-20 ", "ref text")
    eq(ref:sub(-1), " ", "trailing space")
    ok(ref:sub(-2) ~= " ", "exactly one trailing space")
    absent(ref, "\n", "ref must be a single line")
  end)

end
