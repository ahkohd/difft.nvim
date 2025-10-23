<div align="center">

# difft.nvim

A Neovim frontend for [Difftastic](https://difftastic.wilfred.me.uk/).

[![Neovim](https://img.shields.io/badge/Neovim%200.10+-green.svg?style=for-the-badge&logo=neovim)](https://neovim.io)
[![Lua](https://img.shields.io/badge/Lua-blue.svg?style=for-the-badge&logo=lua)](http://www.lua.org)


<!-- Demo source: https://github.com/user-attachments/assets/04070894-71ec-4051-92ce-d3140827370d -->
https://github.com/user-attachments/assets/04070894-71ec-4051-92ce-d3140827370d

</div>

## Features

- Parse and display difftastic output with full ANSI color support
- Navigate between file changes with keybindings
- Jump to changed files directly from diff view
- Customizable window layouts (buffer, float, ivy-style)
- File header customization support

## Requirements

- Neovim 0.10+
- [Difftastic](https://github.com/Wilfred/difftastic) (external diff tool)

> [!IMPORTANT]
> `difft.nvim` requires ANSI color codes to render colored diffs.
> You **must** use the `--color=always` flag when calling `difft`, otherwise no colors will be visible in the diff output.

```bash
# Example difft command format
difft --color=always $left $right

# For git, use:
GIT_EXTERNAL_DIFF='difft --color=always' git diff
```

For more difftastic options and usage examples, see the [documentation](https://difftastic.wilfred.me.uk/usage.html).

## Installation

### lazy.nvim

```lua
return {
  "ahkohd/difft.nvim",
  config = function()
    require("difft").setup()
  end,
}
```

## Quick Setup

```lua
--luacheck: globals Difft

return {
  "ahkohd/difft.nvim",
  keys = {
    {
      "<leader>d",
      function()
        if Difft.is_visible() then
          Difft.hide()
        else
          Difft.diff()
        end
      end,
      desc = "Toggle Difft",
    },
  },
  config = function()
    require("difft").setup({
      command = "jj diff --no-pager",  -- or "GIT_EXTERNAL_DIFF='difft --color=always' git diff"
      layout = "float",  -- nil (buffer), "float", or "ivy_taller"
    })
  end,
}
```

## Example Setup

```lua
--luacheck: globals Difft

return {
  "ahkohd/difft.nvim",
  keys = {
    {
      "<leader>d",
      function()
        if Difft.is_visible() then
          Difft.hide()
        else
          Difft.diff()
        end
      end,
      desc = "Toggle Difft",
    },
  },
  config = function()
    require("difft").setup({
      layout = "ivy_taller",
      no_diff_message = "All clean! No changes detected.",
      loading_message = "Loading diff...",
      window = {
        number = false,
        relativenumber = false,
        border = "rounded",
      },
    --- Custom header content with webdev icons
      header = {
        content = function(filename, step, _language)
          local devicons = require("nvim-web-devicons")
          local basename = vim.fn.fnamemodify(filename, ":t")
          local icon, hl = devicons.get_icon(basename)

          -- Get the bg from FloatTitle (what DifftFileHeader links to)
          local header_hl = vim.api.nvim_get_hl(0, { name = "FloatTitle", link = false })

          -- Create custom highlight with devicon fg + header bg
          local icon_hl = hl
          if hl and header_hl.bg then
            local devicon_colors = vim.api.nvim_get_hl(0, { name = hl })
            if devicon_colors.fg then
              local custom_hl_name = "DifftIcon_" .. hl
              vim.api.nvim_set_hl(0, custom_hl_name, {
                fg = devicon_colors.fg,
                bg = header_hl.bg,
              })
              icon_hl = custom_hl_name
            end
          end

          local result = {}
          table.insert(result, { " " })
          table.insert(result, { icon and (icon .. " ") or "", icon_hl })
          table.insert(result, { filename })
          table.insert(result, { " " })

          if step then
            table.insert(result, { "• " })
            table.insert(result, { tostring(step.current) })
            table.insert(result, { "/" })
            table.insert(result, { tostring(step.of) })
            table.insert(result, { " " })
          end

          return result
        end,
        highlight = {
          link = "FloatTitle",
          full_width = true,
        },
      },
    })
  end,
}
```

## Configuration

### Layout Options

```lua
layout = nil        -- Open in current buffer
layout = "float"    -- Centered floating window
layout = "ivy_taller" -- Bottom window (ivy-style)
```

### Window Options

```lua
window = {
  width = 0.9,           -- Float window width (0-1)
  height = 0.8,          -- Float window height (0-1)
  title = " Difft ",     -- Window title
  number = false,        -- Show line numbers
  relativenumber = false,
  border = "rounded",    -- Border style: "none", "single", "double", "rounded", "solid", "shadow", or custom array
}
```

### Keymaps

```lua
keymaps = {
  next = "<Down>",   -- Next file change
  prev = "<Up>",     -- Previous file change
  close = "q",       -- Close diff window (float only)
  refresh = "r",     -- Refresh diff
  first = "gg",      -- First file change
  last = "G",        -- Last file change
}
```

### Jump Configuration

```lua
jump = {
  enabled = true,       -- Enable file jumping
  ["<CR>"] = "edit",    -- Open file in current window
  ["<C-v>"] = "vsplit", -- Open file in vertical split
  ["<C-x>"] = "split",  -- Open file in horizontal split
  ["<C-t>"] = "tabedit", -- Open file in new tab
}
```

### Header Customization

#### Simple Header

```lua
header = {
  content = function(filename, step, language)
    if step then
      return string.format("[%d/%d] %s (%s)", step.current, step.of, filename, language)
    end
    return string.format("%s (%s)", filename, language)
  end,
  highlight = {
    link = "FloatTitle",
    full_width = true,
  },
}
```

#### Header with Icons

```lua
header = {
  content = function(filename, step, language)
    local devicons = require("nvim-web-devicons")
    local basename = vim.fn.fnamemodify(filename, ":t")
    local icon, hl = devicons.get_icon(basename)

    local result = {}
    table.insert(result, { " " })
    table.insert(result, { icon and (icon .. " ") or "", hl })
    table.insert(result, { filename })

    if step then
      table.insert(result, { " • " })
      table.insert(result, { tostring(step.current) })
      table.insert(result, { "/" })
      table.insert(result, { tostring(step.of) })
    end

    return result
  end,
  highlight = {
    link = "FloatTitle",
    full_width = true,
  },
}
```

#### Header Highlight Options

```lua
-- Link to existing highlight group
highlight = {
  link = "FloatTitle",
  full_width = false,
}

-- Custom colors
highlight = {
  fg = "#ffffff",
  bg = "#5c6370",
  full_width = true,
}

-- Link colors separately
highlight = {
  fg = { link = "Statement" },
  bg = { link = "Visual" },
  full_width = false,
}
```

### Diff Highlights

Customize the highlight groups used for diff colors. Supports both **string** (group name) and **table** (color object) values:

**String values (highlight group names):**
```lua
diff = {
  highlights = {
    add = "DifftAdd",          -- Additions (green) - ANSI codes 32, 92
    delete = "DifftDelete",    -- Deletions (red) - ANSI codes 31, 91
    change = "DifftChange",    -- Changes (yellow) - ANSI codes 33, 93
    info = "DifftInfo",        -- Info (blue/cyan) - ANSI codes 34, 94, 36, 96
    hint = "DifftHint",        -- Hints (magenta) - ANSI codes 35, 95
    dim = "DifftDim",          -- Dim text (gray/white) - ANSI codes 30, 90, 37, 97
  },
}
```

**Table values (color objects):**
```lua
diff = {
  highlights = {
    -- Direct colors
    add = {fg = "#00ff00"},
    delete = {fg = "#ff0000", bg = "#300000"},

    -- Link to existing group
    change = {link = "WarningMsg"},

    -- Mix and match
    info = "DifftInfo",       -- String
    hint = {fg = "#c678dd"},  -- Color object
  },
}
```

The ANSI bold, italic, and dim styles still layer on top of your custom color settings.

**Example:** GitHub-style diff colors, familiar and easy on the eyes:
```lua
require("difft").setup({
  diff = {
    highlights = {
      add = { bg = "#d6f5d6", fg = "#1a4d1a" },
      delete = { bg = "#ffe5e5", fg = "#6b1f1f" },
    },
  },
})
```

**Example:** Match your diffs to Devicon colors:

```lua
require("difft").setup({
  diff = {
    highlights = {
      add = "DevIconBashrc",    -- Green from bashrc icon
      delete = "DevIconGulpfile", -- Red from gulpfile icon
    },
  },
})
```

### Other Options

```lua
command = "jj diff --no-pager"  -- Diff command to execute
auto_jump = true                 -- Jump to first change on open
no_diff_message = "No changes found"
loading_message = "Loading diff..."
```

## Usage

### Basic Commands

```lua
-- Open diff
require("difft").diff()

-- Open with custom command
require("difft").diff({ cmd = "git diff" })

-- Close diff
require("difft").close()

-- Hide diff (float only, keeps buffer)
require("difft").hide()

-- Refresh current diff
require("difft").refresh()

-- Check if diff exists
if require("difft").exists() then
  -- ...
end

-- Check if diff is visible
if require("difft").is_visible() then
  -- ...
end
```

### Global API

The plugin also exposes a global `Difft` table:

```lua
Difft.diff()
Difft.close()
Difft.hide()
Difft.refresh()
Difft.exists()
Difft.is_visible()
```

### Example Keybinding

```lua
vim.keymap.set("n", "<leader>d", function()
  if Difft.is_visible() then
    Difft.hide()
  else
    Difft.diff()
  end
end, { desc = "Toggle difft" })
```

## Navigation

When viewing a diff:

- `<Down>` / `<Up>` - Navigate between file changes
- `gg` / `G` - Jump to first/last change
- `<CR>` - Open file at cursor (jump to changed line)
- `<C-v>` / `<C-x>` / `<C-t>` - Open file in split/tab
- `r` - Refresh diff
- `q` - Close diff (floating windows only)

## Highlight Groups

The plugin uses **terminal colors** by default, so it automatically matches your colorscheme
without any configuration.

**Color precedence** (from lowest to highest priority):

1. **ANSI defaults** - Standard terminal colors (red, green, yellow, etc.)
   - Always available, works even with `nvim --clean`
2. **Terminal colors** - `vim.g.terminal_color_N`
   - Set by most colorschemes
   - Automatically matches your terminal theme
3. **Theme-defined** - `Difft*` highlight groups
   - For theme authors who want difft-specific colors
4. **User config** - `diff.highlights` setting
   - Highest priority, full control

### Highlight Groups

**Diff Content:**
- `DifftAdd` - Added lines (uses `terminal_color_2` / green)
- `DifftDelete` - Deleted lines (uses `terminal_color_1` / red)
- `DifftChange` - Changed lines (uses `terminal_color_3` / yellow)

**ANSI Colors:**
- `DifftInfo` - Info text (uses `terminal_color_6` / cyan)
- `DifftHint` - Hint text (uses `terminal_color_5` / magenta)
- `DifftDim` - Dim text (uses `terminal_color_8` / gray)

See [Diff Highlights](#diff-highlights) for customization options.

To provide difft-specific colors for themes, define `Difft*` groups in your colorscheme.

### File Headers
- `DifftFileHeader` - File headers (uses `terminal_color_7` / white)
- `DifftFileHeaderBg` - Header background for full-width mode (transparent by default)

## Testing

Run tests with:

```bash
nvim -l tests/run.lua
```

See [tests/README.md](./tests/README.md) for details.

