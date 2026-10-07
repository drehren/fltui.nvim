---@class fltui
local M = {}

M.close_on_leave = require('fltui.util').close_on_leave

---A [vim.ui.input()](lua://vim.ui.input()) replacement.
---@param opts vim.ui.input.Opts
---@param on_confirm fun(input: string?)
function M.input(opts, on_confirm)
    require('fltui.input').input(opts, on_confirm)
end

---Simple selection floating window
---@param items any[] Arbitrary items
---@param opts vim.ui.select.Opts Additional options
---@param on_choice fun(item?: any, index?: integer)
function M.select(items, opts, on_choice)
    require('fltui.select').select(items, opts, on_choice)
end

---Selection floating window with additional arbitrary actions that can be
---performed to items in list
---@generic T
---@param items `T`[] Arbitrary items
---@param opts vim.ui.select.Opts Additional options
---@param on_choice fun(item: T?, index: integer?)
---@param actions fltui.select.action_map Action list
function M.select_actions(items, opts, on_choice, actions)
    require('fltui.select').select(items, opts, on_choice, actions)
end

---Adds autocompletion to the specified buffer
---@param buf integer
---@param completer fun(line: string, cword: string, col:number): string[]
---@param opts fltui.acmp.opts?
function M.install_autocomplete(buf, completer, opts)
    return require('fltui.acmp').install(buf, completer, opts or {})
end

return M
