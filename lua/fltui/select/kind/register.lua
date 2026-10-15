local get_hl_id_by_name = vim.api.nvim_get_hl_id_by_name

local mode2regtype = { [''] = 'b', v = 'c', V = 'l' }

local numberid = get_hl_id_by_name('@number')
local spkeyid = get_hl_id_by_name('SpecialKey')

local buf_set_extmark = vim.api.nvim_buf_set_extmark

---@class fltui.select.kind.register : fltui.select
---@field linefmt string
---@field regtype string[]
local M = {}
M.__index = M

function M:process_format(index)
    local item = self.items[index]
    local regcont = vim.fn.getreg(item):gsub('\n', '^J')
    if self.regtype[index] ~= '' and regcont ~= '' then
        return self.linefmt:format(item, self.regtype[index], regcont)
    end
    return ''
end

function M:process_items(first, last)
    local lines = self.super.process_items(self, first, last)
    local e = 1
    for i = 1, #lines do
        if lines[i] == '' then
            lines[e] = lines[i + 1]
        end
        if lines[e] ~= '' then
            e = e + 1
        end
    end
    for i = e, #lines do
        lines[i] = nil
    end
    self._lc = #lines
    return lines
end

function M:calc_height()
    return self._lc or #self.items
end

local function hl(self, linenr, line)
    local ext = {}
    ext.end_col = 6
    ext.hl_group = numberid
    buf_set_extmark(self.buf, self.ns, linenr - 1, 4, ext)

    ext.hl_group = spkeyid
    for s, e in line:gmatch('()^J()') do
        ext.end_col = e - 1
        buf_set_extmark(self.buf, self.ns, linenr - 1, s - 1, ext)
    end
end

function M:item_highlight(linenr, line)
    hl(self, linenr, line)
    self.super.item_highlight(self, linenr, line)
end

function M:cursorline_highlight(linenr, line)
    hl(self, linenr, line)
    self.super.cursorline_highlight(self, linenr, line)
end

function M:open_win(enter)
    self.super.open_win(self, enter)

    vim.api.nvim_win_set_config(self.win, {
        anchor = 'SW',
        relative = 'editor',
        col = 0,
        row = require('fltui.util').editor_height(),
        border = 'single',
    })
end

function M:new(items, opts, on_choice, actions)
    local sel = self.super:new(items, opts, on_choice, actions) --[[@as fltui.select.kind.register]]

    sel.linefmt = ' "%s  %s  %s'
    sel.custom_index = '%s*".  '

    sel.regtype = {}
    for i, item in ipairs(sel.items) do
        sel.regtype[i] = mode2regtype[vim.fn.getregtype(item):sub(1, 1)]
    end

    return setmetatable(sel, self)
end

return M
