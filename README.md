# clipreview.nvim

Code review comments from Neovim to your clipboard: extmark-anchored
annotations on any named buffer, exported as one agent-ready markdown payload.
Zero dependencies, no network, no daemon, no agent spawning.

Comment any line or range in a named file buffer, edit the code above it and
the anchor follows your edits, then copy one markdown payload and paste it into
your agent chat.

Each comment also renders a callout above its block (`╭─ 💬 <text>`), attached to
the same extmark as the sign, so it moves with the code and updates as you edit
the comment. The callout is display-only: the payload never contains it.

## Demo

Three comments in two files, `<leader>ay` (`:ClipReview copy`) puts this on the
clipboard:

```
Code review comments from my editor (repo: myapp, branch: feat/review):

1. app/Services/BookingService.php:42-58
   > public function store(array $data): Booking
   > {
   >     $this->db->transaction(function () use ($data) {
   Comment: bọc lock ngoài transaction, hiện race ở 2 request đồng thời

2. app/Models/Booking.php:12
   > protected $fillable = ['user_id', 'slot_id'];
   Comment: thiếu slot_id trong migration unique index

Please address each comment. Reply with what you changed per item.
```

## Keys and commands

| Keymap (default) | Command | Action |
|---|---|---|
| `<leader>ac` (n, x) | `:ClipReview comment` | One-line input attached to the current line or selection (`range`-aware: `:'<,'>ClipReview comment`) |
| `<leader>al` | `:ClipReview list` | Float panel: `j`/`k` hover + jump, `<CR>` edit, `d` delete, `q`/`<Esc>` close |
| `<leader>ay` | `:ClipReview copy` | Build the payload and put it on the clipboard, with an honest result |
| `<leader>aY` | `:ClipReview preview` | Show the payload in a markdown scratch buffer, copy nothing |
| `<leader>ai` | `:ClipReview ref` | Copy just `path:12-20` (no header, no code) for mid-sentence use |
| — | `:ClipReview clear` | Delete every comment in the current scope |
| — | `:ClipReview export <path>` | Write the payload to a file |

`ref` always uses the range form and appends a single trailing space, so
`cr.ref()` can be dropped into prose without extra fiddling. A comment store is
scoped to the git work tree of the buffer it was created in; `:ClipReview copy`
with `scope = "all"` collects every repo in the session.

## Install

lazy.nvim:

```lua
{
  "l3aro/clipreview.nvim",
  config = function()
    require("clipreview").setup()
  end,
}
```

Native packages (`:packadd`):

```bash
mkdir -p ~/.local/share/nvim/site/pack/plugins/opt
git clone https://github.com/l3aro/clipreview.nvim \
  ~/.local/share/nvim/site/pack/plugins/opt/clipreview.nvim
```

```lua
vim.cmd.packadd("clipreview.nvim")
```

`plugin/clipreview.lua` registers `:ClipReview` and the default keymaps on
startup, so `setup()` is optional; call it only to change options.

## Configuration

Defaults, exactly as shipped:

```lua
require("clipreview").setup({
  keymaps = {
    comment = "<leader>ac", list = "<leader>al",
    copy = "<leader>ay",    preview = "<leader>aY",
    ref = "<leader>ai",
  },
  register = "+",              -- "+"/"*" need a provider; "0"-"9"/"a"-"z"/"-" do not
  clear_after_copy = false,    -- true = delete the comments after a successful copy
  scope = "repo",              -- "repo" (git root of the current buffer) | "all"
  snippet = {
    max_lines = 10,            -- code context quoted into the payload
    quote = "> ",
  },
  header = {
    enabled = true,
    text = "Code review comments from my editor",
    repo_branch = true,        -- "(repo: X, branch: Y)" when inside git
  },
  footer = "Please address each comment. Reply with what you changed per item.",
  signs = { text = "▌", hl = "DiagnosticInfo", line_hl = "Visual" },
  preview = { enabled = true, hl = "Comment" },  -- callout above each comment
  persist = false,             -- true -> JSON under stdpath("state")/clipreview/
  list_ui = "float",           -- "float" | "ui.select"
})
```

## Clipboard honesty

`copy()` writes the payload with `setreg` and then reads the register back; it
notifies `copied N comment(s)` only when the readback matches the payload
exactly. If the write is rejected or unverifiable it opens the payload in the
preview buffer and reports the failure instead of pretending. With a system
register and no usable provider it says so and never claims a successful copy —
the exact bug this plugin exists to avoid (`agent-review.nvim` notified "copied"
unconditionally). Outside git the header drops the `(repo: …, branch: …)`
context; with `register = "+"`/`"*"` a missing provider means no write, ever.

Check the machine with:

```
:checkhealth clipreview
```

It reports the configured register, `has("clipboard")`, the
`g:loaded_clipboard_provider` flag, whether a write would actually be usable,
the persistence location when enabled, and the current comment count.

Over SSH there is usually no clipboard provider. Neovim ships an OSC 52
implementation (`vim.ui.clipboard.osc52`) with both a `copy` and a `paste`
side: `paste` queries the terminal (OSC 52 `?`) and waits for its answer, so
clipreview's readback goes through the terminal too:

```lua
-- Only if your terminal speaks OSC 52; clipreview does not enable this for you.
vim.g.clipboard = {
  name = "OSC 52",
  copy = {
    ["+"] = require("vim.ui.clipboard.osc52").copy("+"),
    ["*"] = require("vim.ui.clipboard.osc52").copy("*"),
  },
  paste = {
    ["+"] = require("vim.ui.clipboard.osc52").paste("+"),
    ["*"] = require("vim.ui.clipboard.osc52").paste("*"),
  },
  cache_enabled = 0,
}
```

Terminals that do not answer OSC 52 queries make that readback time out, and
clipreview then reports the write as failed and opens the preview instead of
claiming a copy.

`register` chooses the destination. `+` and `*` need a provider; the internal
registers (`0`–`9`, `a`–`z`, `-`) are written by nvim itself and verified by the
same readback, so they need no provider at all — `register = "0"` is the real
no-provider path and succeeds without any provider. When you would rather move
the text by hand, `:ClipReview preview` still gives you the payload:

```lua
require("clipreview").setup({ register = "0" })
```

## Tests

```bash
nvim --headless --clean --cmd "set rtp+=." -l tests/run.lua
nvim --headless --clean --cmd "set rtp+=." -c "checkhealth clipreview" -c "qa!"
```

## License

MIT — see [LICENSE](LICENSE).

