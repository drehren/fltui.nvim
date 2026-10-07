local ui = require('fltui.util')

local win_is_valid = vim.api.nvim_win_is_valid
local win_close = vim.api.nvim_win_close
local win_get_height = vim.api.nvim_win_get_height

local buf_get_lines = vim.api.nvim_buf_get_lines
local buf_set_keymap = vim.api.nvim_buf_set_keymap
local buf_set_extmark = vim.api.nvim_buf_set_extmark

local hlids = {}
do
    local get_hl_id_by_name = vim.api.nvim_get_hl_id_by_name
    hlids.Search = get_hl_id_by_name('Search')
    hlids.CurSearch = get_hl_id_by_name('CurSearch')
end

---@class fltui.select.search: fltui.select
---@field fwin integer
---@field fbuf integer
---@field lines string[] buffer lines
---@field promptcr boolean
---@field matches [integer, integer, integer[]][]
local M = setmetatable({}, require('fltui.select').Select)
M.__index = M
M.super = require('fltui.select').Select

function M:get_action_buffer()
    return self.fbuf
end

function M:item_index(linenr)
    return self.matches[linenr][1]
end

function M:item_linenr(index)
    for i, xi in ipairs(self.matches) do
        if xi[2] == index then
            return i
        end
    end
    return -1
end

local function remove_completers(buf)
    if package.loaded.cmp then
        -- if cmp, remove from buffer
        vim.api.nvim_buf_call(buf, function()
            package.loaded.cmp.setup.buffer({})
        end)
    end
    if package.loaded['blink.cmp'] then
        -- if blink.cmp, remove from buffer
        vim.b[buf].completion = false
    end
end

function M:create_buf()
    M.super.create_buf(self)

    self.fbuf = ui.create_prompt_buf('selection.filter', '> ', function()
        self.promptcr = true
        win_close(self.fwin, true)
    end)

    remove_completers(self.fbuf)

    -- Start search
    buf_set_keymap(self.fbuf, 'n', '/', 'i', {})
    buf_set_keymap(self.fbuf, 'n', '?', 'i', {})

    -- Weird stuff with O mode.. kill it
    buf_set_keymap(self.fbuf, 'i', '<C-O>', '', {})

    -- Buffer close without selection
    buf_set_keymap(self.fbuf, 'n', '<ESC>', '', {
        callback = function()
            if win_is_valid(self.win) then
                win_close(self.win, true)
            else
                win_close(self.fwin, true)
            end
        end,
    })
    buf_set_keymap(self.fbuf, 'n', 'q', '<ESC>', {})
    buf_set_keymap(self.fbuf, 'n', '<C-C>', '<ESC>', {})

    local changedtick = vim.api.nvim_buf_get_changedtick(self.fbuf)
    vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
        nested = true,
        group = ui.augid,
        buffer = self.fbuf,
        callback = function(args)
            local newchange = vim.api.nvim_buf_get_changedtick(args.buf)
            if newchange > changedtick then
                changedtick = newchange
                self:action_reload({ type = 'reload' })
            end
        end,
    })
end

function M:open_win(enter)
    M.super.open_win(self, false)

    -- we want the filter + items window to be centered

    local itemswinconf = vim.api.nvim_win_get_config(self.win)

    local totalheight = itemswinconf.height + 2 -- 1 for filter height, 1 for border in between

    local row = (ui.editor_height() - totalheight) / 2

    -- update items window border and position
    ---@type vim.api.keyset.win_config
    local conf = {
        border = { '├', '─', '┤', '│', '╯', '─', '╰', '│' },
        zindex = 99,
        title = '',
        row = row + 2,
        col = itemswinconf.col,
        relative = 'editor',
    }
    vim.api.nvim_win_set_config(self.win, conf)

    ---@type vim.api.keyset.win_config
    local config = {
        title = self.opts.prompt,
        relative = 'editor',
        row = row,
        col = itemswinconf.col,
        width = itemswinconf.width,
        height = 1,
        style = 'minimal',
        zindex = itemswinconf.zindex,
        noautocmd = true,
        border = { '╭', '─', '╮', '│', '', '', '', '│' },
    }
    self.fwin = vim.api.nvim_open_win(self.fbuf, enter, config)
    vim.api.nvim_win_set_hl_ns(self.fwin, self.ns)
    vim.api.nvim_set_option_value('scrolloff', 0, { win = self.fwin })

    -- both windows should be centered, calculate correct offsets
    ui.keep_centered(self.win, { 1, 0 })
    ui.keep_centered(self.fwin, {
        function()
            return (-win_get_height(self.win) - 1) / 2
        end,
        0,
    })
    ui.close_on_leave_allowed(self.win, self.fwin)
    ui.close_on_buf_change(self.fwin)

    vim.api.nvim_create_autocmd('WinEnter', {
        nested = true,
        group = ui.augid,
        callback = function()
            if self.promptcr or not win_is_valid(self.fwin) then
                return true
            end
            local cw = vim.api.nvim_get_current_win()
            if cw == self.win then
                if win_is_valid(self.win) then
                    vim.api.nvim_set_current_win(self.fwin)
                end
            elseif cw ~= self.fwin then
                win_close(self.fwin, true)
                return true
            end
        end,
    })

    vim.api.nvim_create_autocmd('WinClosed', {
        nested = true,
        group = ui.augid,
        pattern = tostring(self.fwin),
        once = true,
        callback = function()
            vim.api.nvim_set_current_win(self.win)
            if self.promptcr then
                self:select()
            else
                win_close(self.win, true)
            end
        end,
    })

    vim.api.nvim_create_autocmd('WinClosed', {
        nested = true,
        group = ui.augid,
        pattern = tostring(self.win),
        once = true,
        callback = function()
            vim.cmd.stopinsert()
            if win_is_valid(self.fwin) then
                win_close(self.fwin, true)
            end
        end,
    })

    local kmopts = {
        group = ui.augid,
        buffer = self.buf,
    }
    require('fltui.select.keymaps').proxy_motions(self.fbuf, self.win, function()
        vim.api.nvim_exec_autocmds('CursorMoved', kmopts)
    end)
end

function M:show(enter)
    M.super.show(self, enter)

    if enter then
        vim.api.nvim_set_current_win(self.fwin) -- just in case
        if #self.items > 0 then
            vim.cmd.startinsert()
        end
    end
end

local fuzzy

---@param lines string[]
---@param first integer
---@param last integer
function M:filter(lines, first, last)
    local txt = buf_get_lines(self.fbuf, 0, 1, true)[1]
    local prompt = vim.fn.prompt_getprompt(self.fbuf)
    local pattern = txt:sub(#prompt + 1)

    for i = 1, #self.items do
        -- reset item indexes
        self.matches[i][1] = i
        self.matches[i][2] = #self.items - i + 1
        self.matches[i][3] = nil
    end

    local totallines = #self.items

    if #self.items > 0 and #pattern > 0 then
        if not fuzzy then
            fuzzy = require('fltui.fuzzy')
        end
        local _, noscored = fuzzy.match3(
            self.lines,
            pattern,
            { fuzzy = self.opts.search == 'fuzzy' },
            self.matches
        )

        if self.opts.filter then
            totallines = totallines - noscored
        end
        table.sort(self.matches, function(l, r)
            return l[2] > r[2]
        end)
    end
    for i = 1, #lines do
        lines[i] = nil
    end
    last = math.min(last, totallines)
    for i = first, last do
        lines[i - first + 1] = self.lines[self.matches[i][1]]
    end
    return lines
end

function M:process_items(first, last)
    first = first or 1
    last = last or #self.items
    local lines = M.super.process_items(self, first, last)
    for i = first, last do
        self.lines[i] = lines[i - first + 1]
    end
    return self:filter(lines, first, last)
end

local function linehl(self, linenr, ext, pos, hl_group)
    ext.end_line = nil
    ext.hl_eol = nil
    for _, c in ipairs(pos) do
        local cs = c - 1
        ext.end_col = c
        ext.hl_group = hl_group
        buf_set_extmark(self.buf, self.ns, linenr - 1, cs, ext)
    end
end

function M:item_highlight(linenr)
    local pos = self.matches[linenr][3]
    if not pos then
        return
    end
    local ext = {}
    linehl(self, linenr, ext, pos, hlids.Search)
end

function M:cursorline_highlight(linenr)
    local pos = self.matches[linenr][3]
    if not pos then
        return
    end

    local ext = {}
    linehl(self, linenr, ext, pos, hlids.CurSearch)
end

function M:update_win_width(wins)
    wins = wins or {}
    wins[#wins + 1] = self.fwin
    M.super.update_win_width(self, wins)
end

function M:new(items, opts, on_choice, actions)
    local sel = M.super:new(items, opts, on_choice, actions) --[[@as fltui.select.search]]
    sel.matches = {}
    sel.lines = {}
    sel.promptcr = false
    for i = 1, #items do
        sel.matches[i] = { #sel.items - i + 1, i }
    end
    return setmetatable(sel, self)
end

return M
