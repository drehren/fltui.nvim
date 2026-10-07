local ui = require('fltui.util')

local M = {}

local scrbns = vim.api.nvim_create_namespace('fltui.scrb')

local function calc_thumb(topline, viewport, total)
    local barh = math.max(1, math.floor((viewport ^ 2) / total))
    if barh >= total then
        return nil
    end

    -- bar top
    local bart = math.ceil((topline - 1) * viewport / total)
    bart = math.min(bart, viewport - barh)
    -- bar bottom
    local barb = math.min(bart + barh, viewport)

    return bart, barb
end

local buf_set_extmark = vim.api.nvim_buf_set_extmark
local sbar =
    { end_col = 1, hl_group = vim.api.nvim_get_hl_id_by_name('PmenuSbar') }
local sthumb =
    { end_col = 1, hl_group = vim.api.nvim_get_hl_id_by_name('PmenuThumb') }
local function draw_bar(scrb, topline, viewport, total)
    -- clear current draw
    vim.api.nvim_buf_clear_namespace(scrb, scrbns, 0, -1)

    local bart, barb = calc_thumb(topline, viewport, total)
    if not bart then
        return false
    end

    for i = 1, bart do
        buf_set_extmark(scrb, scrbns, i - 1, 0, sbar)
    end
    for i = bart + 1, barb do
        buf_set_extmark(scrb, scrbns, i - 1, 0, sthumb)
    end
    for i = barb + 1, viewport do
        buf_set_extmark(scrb, scrbns, i - 1, 0, sbar)
    end
    return true
end

local mousenoops = {
    '<A-LeftMouse>',
    '<C-LeftMouse>',
    '<S-LeftMouse>',
    '<LeftDrag>',
    '<LeftRelease>',
    '<MiddleMouse>',
    '<RightMouse>',
    '<A-RighMouse>',
    '<S-RightMouse>',
    '<C-RightMouse>',
    '<RightDrag>',
    '<RightRelease>',
    '<ScrollWhellLeft>',
    '<S-ScrollWhellLeft>',
    '<ScrollWhellRight>',
    '<S-ScrollWhellRight>',
}
local function set_keys_and_autocmds(scrb, scrw, win)
    local move = require('fltui.util.movement').proxy_to(win)

    local ks = vim.api.nvim_buf_set_keymap
    for _, lhs in ipairs(mousenoops) do
        ks(scrb, 'n', lhs, '', {})
        ks(scrb, 'i', lhs, '', {})
    end

    local clickfn = function()
        local mpos = vim.fn.getmousepos()
        local winfo = vim.fn.getwininfo(win)[1]
        vim.api.nvim_set_current_win(win)
        local lc = vim.api.nvim_buf_line_count(winfo.bufnr)
        local bart, barb = calc_thumb(winfo.topline, winfo.height, lc)
        if bart then
            if mpos.winrow <= bart then
                move.line_up()
            elseif mpos.winrow > barb then
                move.line_down()
            end
        end
    end

    ks(scrb, 'n', '<LeftMouse>', '', { callback = clickfn })
    ks(scrb, 'i', '<LeftMouse>', '', { callback = clickfn })
    local scrolldown = function()
        move.line_down(3)
        vim.api.nvim_set_current_win(win)
    end
    ks(scrb, 'n', '<ScrollWhellDown>', '', { callback = scrolldown })
    ks(scrb, 'i', '<ScrollWhellDown>', '', { callback = scrolldown })
    local s_scrolldown = function()
        move.page_down()
        vim.api.nvim_set_current_win(win)
    end
    ks(scrb, 'n', '<S-ScrollWhellDown>', '', { callback = s_scrolldown })
    ks(scrb, 'i', '<S-ScrollWhellDown>', '', { callback = s_scrolldown })
    local scrollup = function()
        move.line_up(3)
        vim.api.nvim_set_current_win(win)
    end
    ks(scrb, 'n', '<ScrollWhellUp>', '', { callback = scrollup })
    ks(scrb, 'i', '<ScrollWhellUp>', '', { callback = scrollup })
    local s_scrollup = function()
        move.page_up()
        vim.api.nvim_set_current_win(win)
    end
    ks(scrb, 'n', '<S-ScrollWhellUp>', '', { callback = s_scrollup })
    ks(scrb, 'i', '<S-ScrollWhellUp>', '', { callback = s_scrollup })

    local win_is_valid = vim.api.nvim_win_is_valid
    local function close_scrw()
        if not win_is_valid(win) then
            if win_is_valid(scrw) then
                vim.api.nvim_win_close(scrw, true)
            end
            return true
        end
        if not win_is_valid(scrw) then
            return true
        end
    end

    vim.api.nvim_create_autocmd({ 'WinClosed', 'WinLeave', 'WinEnter' }, {
        nested = true,
        group = ui.augid,
        callback = close_scrw,
    })

    vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
        nested = true,
        group = ui.augid,
        callback = function()
            if close_scrw() then
                return true
            end
            if vim.api.nvim_get_current_buf() == scrb then
                -- assume moved in, and by click
                clickfn()
                vim.api.nvim_set_current_win(win)
            end
        end,
    })

    local lastscroll
    vim.api.nvim_create_autocmd('WinScrolled', {
        nested = true,
        group = ui.augid,
        callback = function()
            if close_scrw() then
                return true
            end
            local winwc = vim.v.event[tostring(win)]
            local scrwc = vim.v.event[tostring(scrw)]
            if winwc and not scrwc then
                M.update_scrollbar(scrw)
                lastscroll = 'scrw'
            elseif scrwc and not winwc then
                if lastscroll ~= 'scrw' then
                    if not ui.no_scrolloff(scrw) then
                        -- this means that the scrollbar is being moved somehow
                        move.line_up(scrwc.topline)
                        lastscroll = nil
                    end
                end
            end
        end,
    })

    vim.api.nvim_create_autocmd('WinResized', {
        nested = true,
        callback = function()
            if close_scrw() then
                return true
            end
            if vim.list_contains(vim.v.event.windows, win) then
                M.update_scrollbar(scrw)
            end
        end,
    })

    local win_get_buf = vim.api.nvim_win_get_buf
    local get_curent_win = vim.api.nvim_get_current_win

    local winbuf = win_get_buf(win)

    vim.api.nvim_create_autocmd('BufWinEnter', {
        nested = true,
        group = ui.augid,
        callback = function(ev)
            if close_scrw() then
                return true
            end
            if get_curent_win() ~= win then
                return
            end

            if ev.buf ~= winbuf then
                winbuf = win_get_buf(win)
                vim.b[scrb]._fltui_scrw_topline = -1
                vim.b[scrb]._fltui_scrw_linecount = -1
                M.update_scrollbar(scrw)
            end
        end,
    })

    vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
        nested = true,
        callback = function()
            if close_scrw() then
                return true
            end
            vim.schedule(function()
                if not close_scrw() then
                    M.update_scrollbar(scrw)
                end
            end)
        end,
    })
end

---Adds a vertical scrollbar to the specified window.
---
---The scrollbar will be updated on TextChanged and WinScrolled, but not all
---times.
---@param win integer Window ID
---@return number scrw ScrollBar window ID
function M.add_vertical_scrollbar(win)
    vim.validate('win', win, vim.api.nvim_win_is_valid, 'valid window')

    if vim.w[win]._fltui_scrw then
        local scrw = vim.w[win]._fltui_scrw
        if vim.api.nvim_win_is_valid(scrw) then
            M.update_scrollbar(scrw)
            return scrw
        end
    end

    local scrb = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_option_value('bh', 'wipe', { buf = scrb })

    local wininfo = vim.fn.getwininfo(win)[1]
    local bar = {}
    for i = 1, wininfo.height do
        bar[i] = ' '
    end
    vim.api.nvim_buf_set_lines(scrb, 0, -1, true, bar)

    local topline = wininfo.topline
    local linecount = vim.api.nvim_buf_line_count(wininfo.bufnr)
    vim.b[scrb]._fltui_scrw_linecount = linecount
    vim.b[scrb]._fltui_scrw_topline = wininfo.topline
    local drawn = draw_bar(scrb, topline, wininfo.height, linecount)

    local wcfg = vim.api.nvim_win_get_config(win)
    ---@type vim.api.keyset.win_config
    local scrc = {
        relative = 'win',
        anchor = 'NW',
        row = 0,
        col = wcfg.width,
        border = 'none',
        width = 1,
        height = wcfg.height,
        zindex = wcfg.zindex + 1,
        win = win,
        style = 'minimal',
        focusable = false,
        mouse = true,
        noautocmd = true,
        hide = not drawn,
    }
    local scrw = vim.api.nvim_open_win(scrb, false, scrc)
    vim.w[win]._fltui_scrw = scrw
    vim.w[scrw]._fltui_scrw = win
    vim.api.nvim_set_option_value(
        'winhl',
        'EndOfBuffer:PmenuSbar',
        { win = scrw }
    )
    local allowed = vim.w[win]._fltui_ui_keep
    if not allowed then
        allowed = {}
    end
    allowed[#allowed + 1] = scrw
    vim.w[win]._fltui_ui_keep = allowed
    vim.api.nvim_set_option_value('so', 0, { win = scrw })
    vim.api.nvim_win_set_hl_ns(scrw, scrbns)

    set_keys_and_autocmds(scrb, scrw, win)

    return scrw
end

---Updates the specified scrollbar
---
---@param scrw integer Scrollbar id
function M.update_scrollbar(scrw)
    vim.validate('scrw', scrw, vim.api.nvim_win_is_valid, 'valid window-ID')
    local win = vim.w[scrw]._fltui_scrw
    if not vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(scrw, true)
        return
    end
    local h = vim.api.nvim_win_get_height(scrw)
    local wininfo = vim.fn.getwininfo(win)[1]
    local scrc
    local scrb = vim.api.nvim_win_get_buf(scrw)
    if wininfo.height ~= h then
        local bar = {}
        for i = 1, wininfo.height do
            bar[i] = ' '
        end
        vim.api.nvim_buf_set_lines(scrb, 0, -1, true, bar)
        scrc = {
            height = wininfo.height,
        }
    end
    local topline = vim.b[scrb]._fltui_scrw_topline
    local linecount = vim.b[scrb]._fltui_scrw_linecount
    local curlc = vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(win))
    if curlc ~= linecount or wininfo.topline ~= topline then
        vim.b[scrb]._fltui_scrw_linecount = curlc
        vim.b[scrb]._fltui_scrw_topline = wininfo.topline
        if not scrc then
            scrc = {}
        end
        scrc.hide = not draw_bar(scrb, wininfo.topline, wininfo.height, curlc)
    end
    if scrc then
        scrc = {
            relative = 'win',
            row = 0,
            col = wininfo.width,
            height = scrc.height,
            win = win,
            style = 'minimal',
            hide = scrc.hide,
        }
        vim.api.nvim_win_set_config(scrw, scrc)
    end
end

return M
