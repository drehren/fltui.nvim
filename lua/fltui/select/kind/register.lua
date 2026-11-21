local get_hl_id_by_name = vim.api.nvim_get_hl_id_by_name

local mode2regtype = { [''] = 'b', v = 'c', V = 'l' }

local numberid = get_hl_id_by_name('@number')
local spkeyid = get_hl_id_by_name('SpecialKey')

local aug = vim.api.nvim_create_augroup('fltui.select.register', {})

local buf_set_extmark = vim.api.nvim_buf_set_extmark

---@class fltui.select.kind.register : fltui.select
---@field linefmt string
---@field regtype string[]
local M = {}
M.__index = M

function M:process_format(index)
    local item = self.items[index]
    local regcont = vim.fn.getreg(item):gsub('\n', '^J')
    return self.linefmt:format(item, self.regtype[index] or '', regcont or '')
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
    if #line > 0 then
        hl(self, linenr, line)
    end
    self.super.item_highlight(self, linenr, line)
end

function M:cursorline_highlight(linenr, line)
    if #line > 0 then
        hl(self, linenr, line)
    end
    self.super.cursorline_highlight(self, linenr, line)
end

function M:create_win(buf, enter, config)
    local ui = require('fltui.util')
    config.row = ui.editor_height()
    config.col = 0
    config.width = vim.o.columns
    config.anchor = 'SW'
    config.border = 'single'
    local win = self.super.create_win(self, buf, enter, config)

    vim.api.nvim_create_autocmd('TextYankPost', {
        group = aug,
        nested = true,
        callback = function()
            if not vim.api.nvim_win_is_valid(win) then
                return true
            end
            vim.schedule(function()
                self:action_reload({ type = 'reload' })
            end)
        end,
    })

    return win
end

function M:add_win_behaviors(win)
    local ui = require('fltui.util')
    ui.keep_pos(win, { row = ui.editor_height })
    ui.keep_size(win, {
        height = function()
            return self:calc_height()
        end,
        width = function()
            return vim.o.columns
        end,
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
