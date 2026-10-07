local M = {}

local win_call = vim.api.nvim_win_call
local win_get_buf = vim.api.nvim_win_get_buf
local win_get_cursor = vim.api.nvim_win_get_cursor
local win_get_height = vim.api.nvim_win_get_height
local win_set_cursor = vim.api.nvim_win_set_cursor
local win_saveview = vim.fn.winsaveview
local win_restview = vim.fn.winrestview
local buf_line_count = vim.api.nvim_buf_line_count
local mfloor = math.floor
local mmax = math.max
local mmin = math.min
local function clamp(value, min, max)
    return mmin(mmax(value, min), max)
end

local function move_cursor(win, amount, wrap)
    local wrapped
    win_call(win, function()
        local buflines = buf_line_count(win_get_buf(win))
        local pos = win_get_cursor(win)
        local newpos = { 0, pos[2] }
        if not wrap then
            newpos[1] = clamp(pos[1] + amount, 1, buflines)
        else
            newpos[1] = ((pos[1] - 1 + amount) % buflines) + 1
        end
        win_set_cursor(win, newpos)

        if wrap then
            wrapped = (amount < 0 and newpos[1] > pos[1])
                or (amount > 0 and newpos[1] < pos[1])
        end
    end)
    return wrapped
end

local function move_screen(win, amount, with_cursor)
    win_call(win, function()
        local buflines = buf_line_count(0)
        local winview = win_saveview()
        local winheight = win_get_height(win)
        winview.topline = clamp(
            winview.topline + amount,
            1,
            not with_cursor and buflines or buflines - winheight + 1
        )
        if with_cursor then
            winview.lnum = clamp(winview.lnum + amount, 1, buflines)
        end
        local scrolloff = vim.o.scrolloff
        -- only scrolloff in between window
        if winview.topline == 1 or winview.topline + winheight >= buflines then
            scrolloff = 0
        end
        if winview.lnum < winview.topline + scrolloff then
            if scrolloff < winheight then
                winview.lnum = winview.topline + scrolloff
            else
                winview.lnum = winview.topline + mfloor(winheight / 2)
            end
        elseif winview.lnum > winview.topline + winheight - scrolloff - 1 then
            if scrolloff < winheight then
                winview.lnum = winview.topline + winheight - scrolloff - 1
            else
                winview.lnum = winview.topline
                    + winheight
                    - mfloor(winheight / 2)
            end
        end
        win_restview(winview)
    end)
end

local function move_page_down(win, call)
    if call then
        return function()
            local winid = win()
            local scroll = vim.v.count
            if scroll == 0 then
                scroll = vim.wo[winid].scroll
            end
            move_screen(winid, scroll, true)
        end
    end
    return function()
        local scroll = vim.v.count
        if scroll == 0 then
            scroll = vim.wo[win].scroll
        end
        move_screen(win, scroll, true)
    end
end

local function move_page_up(win, call)
    if call then
        return function()
            local winid = win()
            local scroll = vim.v.count
            if scroll == 0 then
                scroll = vim.wo[winid].scroll
            end
            move_screen(winid, -scroll, true)
        end
    end
    return function()
        local scroll = vim.v.count
        if scroll == 0 then
            scroll = vim.wo[win].scroll
        end
        move_screen(win, -scroll, true)
    end
end

local function move_to_first_line(win, call)
    if call then
        return function()
            local winid = win()
            local curline = vim.fn.line('.', winid)
            local c = vim.v.count1
            move_cursor(winid, c - curline)
        end
    end
    return function()
        local curline = vim.fn.line('.', win)
        local c = vim.v.count1
        move_cursor(win, c - curline)
    end
end

local function move_to_last_line(win, call)
    if call then
        return function()
            local winid = win()
            local curline = vim.fn.line('.', winid)
            local c = vim.v.count > 0 and vim.v.count or vim.fn.line('$', winid)
            move_cursor(winid, c - curline)
        end
    end
    return function()
        local curline = vim.fn.line('.', win)
        local c = vim.v.count > 0 and vim.v.count or vim.fn.line('$', win)
        move_cursor(win, c - curline)
    end
end

---@class fltui.ui.proxy_movements
---Moves cursor `v:count` lines down.
---@field line_down function
---Moves cursor `v:count` lines up.
---@field line_up function
---Moves cursor `v:count` lines down.
---
---Wraps to top after reaching last line.
---@field line_down_wrap fun():boolean
---Moves cursor `v:count` lines up.
---
---Wraps to bottom after reaching first line.
---@field line_up_wrap fun():boolean
---Scrolls window `v:count` lines down.
---@field screen_down function
---Scrolls window `v:count` lines up.
---@field screen_up function
---Scrolls window `v:count` lines up or to first line.
---@field to_top function
---Scrolls window `v:count` lines down or to last line.
---@field to_bottom function
---Scrolls window `v:count` or `scroll` lines down.
---@field page_down function
---Scrolls window `v:count` or `scroll` lines up.
---@field page_up function

---@param winsel fun(): integer Window-ID function selector
---@return fltui.ui.proxy_movements
function M.proxy_to_callable(winsel)
    return {
        line_down = function(count)
            count = count or vim.v.count1
            move_cursor(winsel(), count)
        end,
        line_down_wrap = function(count)
            count = count or vim.v.count1
            return move_cursor(winsel(), count, true)
        end,
        line_up = function(count)
            count = count or vim.v.count1
            move_cursor(winsel(), -count)
        end,
        line_up_wrap = function(count)
            count = count or vim.v.count1
            return move_cursor(winsel(), -count, true)
        end,
        screen_down = function(count)
            count = count or vim.v.count1
            move_screen(winsel(), count)
        end,
        screen_up = function(count)
            count = count or vim.v.count1
            move_screen(winsel(), -count)
        end,
        to_top = move_to_first_line(winsel, true),
        to_bottom = move_to_last_line(winsel, true),
        page_down = move_page_down(winsel, true),
        page_up = move_page_up(winsel, true),
    }
end

---Create momevent proxy functions for the specified window-ID
---@param win integer|fun(): integer
---@return fltui.ui.proxy_movements
function M.proxy_to(win)
    if type(win) == 'function' then
        return M.proxy_to_callable(win)
    end
    local mt = getmetatable(win)
    if mt and mt.__call then
        ---@cast win fun():integer
        return M.proxy_to_callable(win)
    end
    ---@type fltui.ui.proxy_movements
    return {
        line_down = function()
            move_cursor(win, vim.v.count1)
        end,
        line_down_wrap = function()
            return move_cursor(win, vim.v.count1, true)
        end,
        line_up = function()
            move_cursor(win, -vim.v.count1)
        end,
        line_up_wrap = function()
            return move_cursor(win, -vim.v.count1, true)
        end,
        screen_down = function()
            move_screen(win, vim.v.count1)
        end,
        screen_up = function()
            move_screen(win, -vim.v.count1)
        end,
        to_top = move_to_first_line(win),
        to_bottom = move_to_last_line(win),
        page_down = move_page_down(win),
        page_up = move_page_up(win),
    }
end

return M
