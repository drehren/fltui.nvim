local M = {}

M.augid = vim.api.nvim_create_augroup('fltui.ui', { clear = true })

---Gets the editor height without statusline and cmdheight
---@return integer height
function M.editor_height()
    local ls = vim.o.laststatus
    local ch = vim.o.cmdheight
    if ls == 2 then
        return vim.o.lines - 1 - ch
    elseif ls == 1 and vim.api.nvim_tabpage_list_wins(0) >= 2 then
        return vim.o.lines - 1 - ch
    else
        return vim.o.lines - ch
    end
end

---Gets or creates an unlisted wipe bufhide buffer
---@param name string Buffer name, will be namespaced into fltui
---@param bt string? Change to `buftype`
---@return integer buf
function M.create_wipe_buf(name, bt)
    assert(name, '[fltui.ui] expected buf name')

    if not vim.startswith(name, 'fltui://') then
        name = 'fltui://' .. name
    end
    local buf = vim.fn.bufnr(name, false)
    if buf == -1 then
        buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_set_option_value('bh', 'wipe', { buf = buf })
        vim.api.nvim_set_option_value('bt', bt or 'nofile', { buf = buf })
        vim.api.nvim_buf_set_name(buf, name)
    end

    return buf
end

---Creates an unlisted prompt buffer
---@param name string Buffer name
---@param prompt? string Prompt
---@param callback? function Callback on <CR>
---@return integer buf
function M.create_prompt_buf(name, prompt, callback)
    assert(type(name) == 'string', '[fltui.ui] expected prompt buf name')

    -- prepare the filter input buffer
    local buf = M.create_wipe_buf(name .. '_prompt', 'prompt')

    vim.api.nvim_buf_set_keymap(buf, 'i', '<C-W>', '<S-C-W>', {})
    vim.api.nvim_buf_set_keymap(buf, 'n', '<ESC>', '<cmd>close!<cr>', {})

    vim.api.nvim_create_autocmd('InsertLeave', {
        group = M.augid,
        buffer = buf,
        nested = true,
        command = 'set nomodified',
    })

    if prompt then
        vim.fn.prompt_setprompt(buf, prompt)
    end
    if callback then
        vim.fn.prompt_setcallback(buf, callback)
    end

    return buf
end

local closeonleave_ignored = {}

---@class fltui.close_on_leave_opts
---@field force? boolean Force buf close (default: false)
---@field bufchange? boolean Close if window buffer changes as well

---Configures the given window to close on leave.
---@param win integer window-ID of window to close on leave
---@param opts fltui.close_on_leave_opts? Additional options
function M.close_on_leave(win, opts)
    vim.validate('win', win, vim.api.nvim_win_is_valid, 'valid window-ID')
    opts = opts or {}
    vim.validate('opts', opts, 'table')

    local wins = vim.w[win]._fltui_ui_keep
    if not wins then
        wins = { win }
    else
        wins[#wins + 1] = win
    end
    vim.w[win]._fltui_ui_keep = wins

    -- Autoclose the specified window
    local curbuf = vim.api.nvim_win_get_buf(win)
    vim.api.nvim_create_autocmd({ 'WinEnter', 'BufEnter', 'BufWinEnter' }, {
        nested = true,
        group = M.augid,
        callback = function()
            if not vim.api.nvim_win_is_valid(win) then
                return true
            end
            if closeonleave_ignored[win] then
                return
            end
            local allowed = vim.w[win]._fltui_ui_keep
            local curwin = vim.api.nvim_get_current_win()
            local winbuf = vim.api.nvim_win_get_buf(win)
            if
                not vim.list_contains(allowed, curwin)
                or (opts.bufchange and curbuf ~= winbuf)
            then
                vim.api.nvim_win_close(win, opts.force or false)
                return true
            end
        end,
    })
end

---Ignores automatic closing for the specified window
---@param win integer window-ID
---@param fun function callback function during ignore
function M.close_on_leave_ignore_call(win, fun)
    vim.validate('win', win, vim.api.nvim_win_is_valid, 'valid window-ID')
    vim.validate('fun', fun, 'callable')
    closeonleave_ignored[win] = true
    local ok, err = pcall(fun)
    closeonleave_ignored[win] = nil
    assert(ok, err)
end

---Configure allowed windows to move to without closing.
---@param win integer window-ID of auto-close window.
---@param allowed integer|[integer] allowed window-ID set.
function M.close_on_leave_allowed(win, allowed)
    vim.validate('win', win, vim.api.nvim_win_is_valid, 'valid window-ID')
    vim.validate('allowed', allowed, { 'number', 'table' })

    local wins = vim.w[win]._fltui_ui_keep or {}

    if type(allowed) == 'table' then
        for _, v in ipairs(allowed) do
            if not vim.list_contains(wins, v) then
                table.insert(wins, v)
            end
        end
    else
        if not vim.list_contains(wins, allowed) then
            table.insert(wins, allowed)
        end
    end

    vim.w[win]._fltui_ui_keep = wins
end

---Specify that the given window should be closed if its current buffer
---changes.
---@param win integer window-ID to close.
---@param opts? { force: boolean? } Additional options.
function M.close_on_buf_change(win, opts)
    vim.validate('win', win, vim.api.nvim_win_is_valid, 'valid window-ID')
    opts = opts or {}
    vim.validate('opts', opts, 'table')

    local expected_buf = vim.api.nvim_win_get_buf(win)
    vim.api.nvim_create_autocmd({ 'BufEnter', 'BufWinEnter' }, {
        nested = true,
        group = M.augid,
        callback = function(ev)
            if not vim.api.nvim_win_is_valid(win) then
                return true
            end
            if vim.api.nvim_get_current_win() ~= win then
                return
            end
            if expected_buf ~= ev.buf then
                vim.api.nvim_win_close(win, opts.force or false)
                return true
            end
        end,
    })
end

local center_w = {
    editor = function()
        return vim.o.columns
    end,
    win = function(cfg)
        return vim.api.nvim_win_get_width(cfg.win)
    end,
    laststatus = function()
        return vim.api.nvim_win_get_width(0)
    end,
    tabline = function()
        return vim.api.nvim_win_get_width(0)
    end,
}
local center_h = {
    editor = M.editor_height,
    win = function(cfg)
        return vim.api.nvim_win_get_height(cfg.win)
    end,
}

local basecenteroff = { 0, 0 }

---Centers the specified floating window.
---
---If the given window is not a floating window, this does nothing.
---@param win integer window-ID
---@param offset? fltui.ui.offsetrange 2-tuple row col offset from center for the window
function M.center(win, offset, _mark)
    local wcfg = vim.api.nvim_win_get_config(win)
    if wcfg.relative == '' then
        return
    end
    local mainw = center_w[wcfg.relative] and center_w[wcfg.relative](wcfg) or 1
    local mainh = center_h[wcfg.relative] and center_h[wcfg.relative](wcfg) or 1
    offset = offset or basecenteroff
    if _mark then
        vim.w[win]._fltui_center_offset = offset
    end

    local rowoff
    if type(offset[1]) == 'function' then
        rowoff = offset[1]()
    else
        ---@type number
        rowoff = offset[1]
    end
    local coloff
    if type(offset[2]) == 'function' then
        coloff = offset[2]()
    else
        ---@type number
        coloff = offset[2]
    end

    local cfg = {
        relative = wcfg.relative,
        win = wcfg.win,
        fixed = wcfg.fixed,
    }
    if wcfg.anchor:byte(2, 2) == ('W'):byte(1, 1) then
        cfg.col = (mainw - wcfg.width) / 2 + coloff
    else
        cfg.col = (mainw + wcfg.width) / 2 + coloff
    end
    if wcfg.anchor:byte(1, 1) == ('N'):byte(1, 1) then
        cfg.row = (mainh - wcfg.height) / 2 + rowoff
    else
        cfg.row = (mainh + wcfg.height) / 2 + rowoff
    end

    if wcfg.col ~= cfg.col or wcfg.row ~= cfg.row then
        vim.api.nvim_win_set_config(win, cfg)
    end
end

---Center multiple windows. Same caveats as `center()` apply.
---@param wdns integer[] window-IDs of floating windows
---@param offsets? [integer, integer][] List of offsets for each window-ID
function M.center_windows(wdns, offsets)
    offsets = offsets or {}
    if type(wdns) ~= 'table' then
        wdns = { wdns }
    end
    for i, win in ipairs(wdns) do
        M.center(win, offsets[i], true)
    end
end

---@alias fltui.ui.offset number|fun():number
---@alias fltui.ui.offsetrange [fltui.ui.offset, fltui.ui.offset]

---Creates an autocmd on WinResized which keeps the specified window centered
---@param win integer window-ID
---@param offset? fltui.ui.offsetrange 2-tuple row col offset from center for the window
function M.keep_centered(win, offset)
    if vim.api.nvim_win_get_config(win).relative == '' then
        return
    end
    offset = offset or { 0, 0 }
    local kcid = vim.w[win]._fltui_keep_center
    vim.w[win]._fltui_center_offset = offset
    if kcid then
        return
    end
    vim.w[win]._fltui_keep_center = vim.api.nvim_create_autocmd('WinResized', {
        nested = true,
        group = M.augid,
        callback = function()
            if not vim.api.nvim_win_is_valid(win) then
                return true
            end
            M.center(win, vim.w[win]._fltui_center_offset)
        end,
    })
end

local cny = '%d' .. vim.api.nvim_replace_termcodes('<C-U>', true, false, true)

local noso_work = vim.schedule_wrap(function(win)
    local winfo = vim.fn.getwininfo(win)[1]
    local lc = vim.api.nvim_buf_line_count(winfo.bufnr)
    local diff = winfo.height - (lc - winfo.topline + 1)
    if diff > 0 and vim.api.nvim_get_mode().mode ~= 'i' then
        vim.api.nvim_win_call(win, function()
            vim.api.nvim_feedkeys(cny:format(diff), 'L', false)
        end)
        return true
    end
    return false
end)

---Tries to scroll out the specified window filler lines.
---
---This does not work when on `insert` modes.
---@param win number window-ID
---@return boolean wasscroll Indicates if the window needed to be scrolled
function M.no_scrolloff(win)
    local wc = vim.v.event[tostring(win)]
    if not wc or wc.topline == 0 then
        return false
    end
    return noso_work(win)
end

---Creates a simple buffer-logger.
---
---Will open a vertical split window to the right with the specified width
---@param id string An identifier for the buffer
---@param width number Number indicating width. Can be a percentage of screen columns
---@return function log A `print()`-like function to use to log.
function M.logger(id, width)
    ---@type vim.api.keyset.win_config
    local logc = {
        width = width > 1 and width or math.ceil(width * vim.o.columns),
        split = 'right',
        win = 0,
        style = 'minimal',
    }
    local logb = M.create_wipe_buf('log_' .. id)
    local logw = vim.api.nvim_open_win(logb, false, logc)

    local start = 0
    local concat = table.concat
    return function(...)
        local line = concat({ ... }, ' ')
        local lines = vim.split(line, '\n', { plain = true })
        local c = start
        vim.schedule(function()
            if not vim.api.nvim_buf_is_valid(logb) then
                logb = M.create_wipe_buf('log_' .. id)
            end
            if not vim.api.nvim_win_is_valid(logw) then
                logw = vim.api.nvim_open_win(logb, false, logc)
            end

            vim.api.nvim_buf_set_lines(logb, c, -1, true, lines)
            vim.api.nvim_win_set_cursor(logw, { c + #lines, 0 })
        end)
        start = start + #lines
    end
end

return M
