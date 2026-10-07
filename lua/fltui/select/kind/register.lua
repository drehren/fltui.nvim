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

function M:format_item(item)
    local regcont = vim.fn.getreg(item):gsub('\n', '^J')
    local line = ''
    if self.regtype[item] ~= '' and regcont ~= '' then
        line = self.linefmt:format(item, self.regtype[item], regcont)
    end
    return line
end

local function hl(self, linenr, line)
    local ext = {}
    ext.end_col = 5
    ext.hl_group = numberid
    buf_set_extmark(self.buf, self.ns, linenr - 1, 3, ext)

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

function M:new(items, opts, on_choice, actions)
    local sel = self.super:new(items, opts, on_choice, actions) --[[@as fltui.select.kind.register]]

    sel.linefmt = '"%s  %s  %s'
    sel.custom_index = ' ..'

    sel.regtype = {}
    for _, item in ipairs(sel.items) do
        sel.regtype[item] = mode2regtype[vim.fn.getregtype(item):sub(1, 1)]
    end

    return setmetatable(sel, self)
end

return M
