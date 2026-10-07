# fltui.nvim

Simple ui widgets and utilities to complement your Neovim experience.

This plugin currently contains replacements for `vim.ui.select` and
`vim.ui.input`.

This plugin does not replace them by default.

## Requirements

* neovim >= 0.11.0

Optional
* telescope-fzf-native: "fuzzy" search for `fltui.select`.

## Instalation

* neovim-0.12 `vim.pack`:
```lua
vim.pack.add({ 'https://github.com/drehren/fltui.nvim' })
```

* Clone the repository:
  * linux/macOS:
```bash
$ mkdir -p ~/.loca/share/nvim/site/pack/fltui/start
$ git clone https://github.com/drehren/fltui.nvim ~/.local/share/nvim/site/pack/fltui/start/fltui.nvim
```
  * Windows:
```bat
> md %LOCALAPPDATA%\nvim-data\site\pack\fltui\start
> git clone https://github.com/drehren/fltui.nvim %LOCALAPPDATA%\nvim-data\site\pack\fltui\start\fltui.nvim
```

* Using [lazy.nvim](https://github.com/folke/lazy.nvim):
```lua
return { 'drehren/fltui.nvim' }
```

* Using [vim-plug](https://github.com/junegunn/vim-plug.git):
```vim
call plug#begin()

Plug 'drehren/fltui.nvim'

call plug#end()
```

* Using [pckr.nvim](https://github.com/lewis6991/pckr.nvim):
```lua
use 'drehren/fltui.nvim'
```

## Configuration

* To replace `vim.ui.input`:
```lua
vim.g.fltui_replace_input = 1
```

* To replace `vim.ui.select`:
```lua
vim.g.fltui_replace_select = 1
```

or via vimscript, replace `vim.ui.select` with fuzzy search and filter out
unmatched entries:
```vim
let g:fltui_replace_select = 1
" This variable configures the default "serch" and "filter" for any selector
let g:fltui_select_search = { 'search': 'fuzzy', 'filter': v:true }
```

## Module

### Input

When replacing `vim.ui.input`, the following function is used.

```lua
vim.ui.input = require('fltui.input').input
```

It is a simple prompt at the middle of the screen, when no scope or if it is
`editor`.

* When closed it returns `nil`.
* It has autocomplete.
* It has highlight support. The function passed for highlight needs to output
  an array of 3-tuples (start, end, highlight group).
* Supprts nvim-0.12 scopes.

### Select

You can use `vim.ui.select` having replaced it, or use it directly.

When using the selector via `vim.ui.select`, you can change its behavior via
`opts.kind` string option.

#### kind

The selector has a mechanism where its behavior and some options can be set
by using kind, which is user configurable.

To do so, return a `metatable` for module *'fltui.select.kind.kind_name'*

```lua
-- The kind handler must be reachable by 
local yourkind = require('fltui.select.kind.yourkind')
```

The only requirement for this table is to override the method `new` from type
`fltui.select`.

The system will use this metatable for `kind` when items are selectable or
searchable.

This means you can override methods from both `fltui.select` and
`fltui.select.search`.

`self` table will contain a `super` key with `fltui.select` if no search will
be performed on the items or `fltui.select.search` otherwise.

```lua
local kind = {}
kind.__index = kind

-- (Required) Initialize the kind value handler; call self.super:new()
-- and return by setting self as metatable of the object that super:new()
-- returns.
function kind:new(items, opts, on_choice, actions) end

-- Override to format the specified item
function kind:format_item(item) end

-- Override to change item entry highlight
function kind:item_highlight(linenr, line) end

-- Override to change item entry highlight when is selected
function kind:cursorline_highlight(linenr, line) end

```

### Autocomplete

There is a simple autocomplete system (used by `fltui.input`) that will
autocomplete based on the completer function return values supplied.


### Scrollbar

Adds a vertical scrollbar to any floating window. The scrollbar will follow
the window viewport.

```lua
    local win = ... -- window-ID
    local sbw = require('fltui.scrb').add_vertical_scrollbar(win)
```

If for any reason it does not update, use the following:
```lua
    require('fltui.scrb').update_scrollbar(sbw)
```

### Proxy cursor movement

Create a manager object that changes the cursor or view of a window
programatically.

```lua
    local movemgr = require('fltui.movement').proxy_to(otherwin)
    -- set it up to move otherwin when doing <leader>k
    vim.keyset.set('n', '<leader>k', movemgr.line_up, { buf = 0 })
```

## LICENSE

MIT.
