local M = {}

M.augid = vim.api.nvim_create_augroup('fltui.ui', { clear = true })

local win_get_var = vim.api.nvim_win_get_var
local win_set_var = vim.api.nvim_win_set_var
local win_del_var = vim.api.nvim_win_del_var
local win_get_config = vim.api.nvim_win_get_config
local win_set_config = vim.api.nvim_win_set_config
local win_get_height = vim.api.nvim_win_get_height
local win_get_width = vim.api.nvim_win_get_width
local win_is_valid = vim.api.nvim_win_is_valid

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

---@class fltui.wipe_buf_opts
---Specify `buftype` for the buffer
---@field bt? ''|'acwrite'|'nofile'|'nowrite'|'prompt'|'quickfix'|'terminal'
---Set to true to always create a new buffer
---@field create? boolean

local _nopts = {}

---Gets or creates an unlisted wipe bufhide buffer
---@param name string Buffer name, will be namespaced into fltui
---@param opts? fltui.wipe_buf_opts Create options
---@return integer buf
function M.create_wipe_buf(name, opts)
    vim.validate('name', name, 'string', 'buffer name')
    vim.validate('opts', opts, 'table', true)
    opts = opts or _nopts

    if not vim.startswith(name, 'fltui://') then
        name = 'fltui://' .. name
    end
    local buf = vim.fn.bufnr(name, false)
    if buf == -1 or opts.create == true then
        buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_set_option_value('bh', 'wipe', { buf = buf })
        vim.api.nvim_set_option_value('bt', opts.bt or 'nofile', { buf = buf })
        local n = 1
        local ogname = name
        while not pcall(vim.api.nvim_buf_set_name, buf, name) do
            name = ('%s_%d'):format(ogname, n)
            n = n + 1
        end
    end

    return buf
end

---@class fltui.prompt_buf_opts
---@field prompt? string Prompt to show
---@field create? boolean Force creation of buffer

---Creates an unlisted prompt buffer
---@param name string Buffer name
---@param opts? fltui.prompt_buf_opts
---@param callback? function Callback on <CR>
---@return integer buf
function M.create_prompt_buf(name, opts, callback)
    assert(type(name) == 'string', '[fltui.ui] expected prompt buf name')
    vim.validate('opts', opts, 'table', true)
    opts = opts or _nopts

    local buf = M.create_wipe_buf(name .. '_prompt', {
        bt = 'prompt',
        create = opts.create,
    })

    vim.api.nvim_buf_set_keymap(buf, 'i', '<C-W>', '<S-C-W>', {})
    vim.api.nvim_buf_set_keymap(buf, 'n', '<ESC>', '<cmd>close!<cr>', {})

    vim.api.nvim_create_autocmd('InsertLeave', {
        group = M.augid,
        buffer = buf,
        nested = true,
        command = 'set nomodified',
    })

    if opts.prompt then
        vim.fn.prompt_setprompt(buf, opts.prompt)
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
    vim.validate('win', win, win_is_valid, 'valid window-ID')
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
            if not win_is_valid(win) then
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
    -- vim.api.nvim_create_autocmd('WinNew', {
    --     nested = true,
    --     group = M.augid,
    --     once = true,
    --     callback = function()
    --         if win_is_valid(win) then
    --             vim.api.nvim_win_close(win, opts.force or false)
    --         end
    --     end,
    -- })
end

---Ignores automatic closing for the specified window
---@param win integer window-ID
---@param fun function callback function during ignore
function M.close_on_leave_ignore_call(win, fun)
    vim.validate('win', win, win_is_valid, 'valid window-ID')
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
    vim.validate('win', win, win_is_valid, 'valid window-ID')
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
    vim.validate('win', win, win_is_valid, 'valid window-ID')
    opts = opts or {}
    vim.validate('opts', opts, 'table')

    local expected_buf = vim.api.nvim_win_get_buf(win)
    vim.api.nvim_create_autocmd({ 'BufEnter', 'BufWinEnter' }, {
        nested = true,
        group = M.augid,
        callback = function(ev)
            if not win_is_valid(win) then
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

local rel_width = {
    editor = function()
        return vim.o.columns
    end,
    win = function(cfg)
        return win_get_width(cfg.win)
    end,
    laststatus = function()
        return win_get_width(0)
    end,
    tabline = function()
        return win_get_width(0)
    end,
}

local rel_height = {
    editor = M.editor_height,
    win = function(cfg)
        return win_get_height(cfg.win)
    end,
}

do
    local MW = {}
    MW.__index = function()
        return function()
            return 1
        end
    end
    setmetatable(rel_width, MW)
    setmetatable(rel_height, MW)
end

---@alias fltui.offset number|fun():number

---@param offval fltui.offset
local function _off_validate(offval)
    return type(offval) == 'number' or vim.is_callable(offval)
end

---@alias fltui.relative_value number|fun(cfg: vim.api.keyset.win_config): integer

---@param rv fltui.relative_value
---@param cfg table
local function _rel_val(rv, cfg)
    if type(rv) == 'function' then
        return rv(cfg)
    elseif type(rv) == 'number' then
        return rv
    end
end

---@param rv fltui.relative_value
local function _rel_val_validate(rv)
    return (type(rv) == 'number' and rv <= 1) or vim.is_callable(rv)
end

---@class (exact) fltui.pos_offset
---@field row? fltui.offset
---@field col? fltui.offset

---@param posoff fltui.pos_offset
local function _pos_off_validate(posoff)
    return type(posoff) == 'table'
        and (posoff.col or posoff.row)
        and (not posoff.col or _off_validate(posoff.col))
        and (not posoff.row or _off_validate(posoff.row))
end

---@class (exact) fltui.relative_pos
---@field row? fltui.relative_value
---@field col? fltui.relative_value

---@param pos fltui.relative_pos
local function _rel_pos_validate(pos)
    return type(pos) == 'table'
        and (_rel_val_validate(pos.row) or _rel_val_validate(pos.col))
end

---@class fltui.relative_size
---@field width? fltui.relative_value
---@field height? fltui.relative_value

---@param sz fltui.relative_size
local function _rel_size_validate(sz)
    return type(sz) == 'table'
        and (_rel_val_validate(sz.width) or _rel_val_validate(sz.height))
end

---@type fltui.pos_offset
local pos_offset_base = { row = 0, col = 0 }

local _Nb = ('N'):byte(1, 1)
local _Wb = ('W'):byte(1, 1)

---Sets the offset of the position the window will keep during resize events
---@param win integer window-ID
---@param offset fltui.pos_offset Position offset
function M.set_offset(win, offset)
    if win_is_valid(win) and type(offset) == 'table' then
        win_set_var(win, '_fltui_pos_offset', offset)
    end
end

---@return fltui.pos_offset
local function _get_offset(win)
    local ok, off = pcall(win_get_var, win, '_fltui_pos_offset')
    return ok and off or pos_offset_base
end

---@param offset fltui.pos_offset
---@param index 'row'|'col'
local function _get_offset_value(offset, index)
    if type(offset[index]) == 'function' then
        return offset[index]()
    elseif type(offset[index]) == 'number' then
        return offset[index]
    end
    return 0
end

---Position table to center the specified window
---@type fltui.relative_pos
local _center_pos = {}
function _center_pos.row(cfg)
    local h = rel_height[cfg.relative](cfg)
    if cfg.anchor:byte(1, 1) == _Nb then
        return (h - cfg.height) / 2
    else
        return (h + cfg.height) / 2
    end
end
function _center_pos.col(cfg)
    local w = rel_width[cfg.relative](cfg)
    if cfg.anchor:byte(2, 2) == _Wb then
        return (w - cfg.width) / 2
    else
        return (w + cfg.width) / 2
    end
end

---Centers the specified floating window.
---
---If the given window is not a floating window, this does nothing.
---@param win integer window-ID or window config
---@param offset? fltui.pos_offset 2-tuple row col offset from center for the window
function M.center(win, offset)
    vim.validate('win', win, win_is_valid, 'valid window')
    vim.validate('offset', offset, _pos_off_validate, 'position offset table')
    local wcfg = win_get_config(win)
    if wcfg.relative == '' then
        return
    end

    local cfg = {
        col = _center_pos.col(wcfg),
        row = _center_pos.row(wcfg),
    }
    if offset then
        cfg.col = cfg.col + _get_offset_value(offset, 'col')
        cfg.row = cfg.row + _get_offset_value(offset, 'row')
    end

    if cfg.col ~= wcfg.col or cfg.row ~= wcfg.row then
        cfg.relative = wcfg.relative
        win_set_config(win, cfg)
    end
end

local _kvars = {
    pos = '_fltui_kpos',
    size = '_fltui_ksize',
}

local kids = {}

local function _create_resize_autocmd()
    return vim.api.nvim_create_autocmd('WinResized', {
        nested = true,
        group = M.augid,
        callback = function()
            local todel = {}
            for i, w in ipairs(kids) do
                if win_is_valid(w) then
                    local has = 0
                    local wcfg = win_get_config(w)
                    local cfg = {}
                    local update = true
                    local hp, pos = pcall(win_get_var, w, _kvars.pos)
                    if hp then
                        has = has + 1
                        cfg.relative = wcfg.relative
                        local off

                        cfg.col = _rel_val(pos.col, wcfg)
                        if cfg.col then
                            off = off or _get_offset(w)
                            cfg.col = cfg.col + _get_offset_value(off, 'col')
                        else
                            cfg.col = wcfg.col
                        end

                        cfg.row = _rel_val(pos.row, wcfg)
                        if cfg.row then
                            off = off or _get_offset(w)
                            cfg.row = cfg.row + _get_offset_value(off, 'row')
                        else
                            cfg.row = wcfg.row
                        end

                        update = cfg.col ~= wcfg.col or cfg.row ~= wcfg.row
                    end
                    local hs, sz = pcall(win_get_var, w, _kvars.size)
                    if hs then
                        has = has + 1
                        cfg.width = _rel_val(sz.width, wcfg) or wcfg.width
                        cfg.height = _rel_val(sz.height, wcfg) or wcfg.height
                        update = update
                            or cfg.width ~= wcfg.width
                            or cfg.height ~= wcfg.height
                    end
                    if update then
                        win_set_config(w, cfg)
                    elseif has == 0 then
                        todel[#todel + 1] = i
                    end
                else
                    todel[#todel + 1] = i
                end
            end
            for i in vim.iter(todel):rev() do
                table.remove(kids, i)
            end
        end,
    })
end

local kid
local function _set_keep(win)
    if not vim.list_contains(kids, win) then
        kids[#kids + 1] = win
    end
    if kid then
        return
    end
    kid = _create_resize_autocmd()
end

---Creates an autocmd on WinResized which keeps the specified window centered
---@param win integer window-ID
---@param offset? fltui.pos_offset 2-tuple row col offset from center for the window
function M.keep_centered(win, offset)
    local wcfg = win_get_config(win)
    if wcfg.relative == '' then
        return
    end
    if offset then
        M.set_offset(win, offset)
    end
    M.keep_pos(win, _center_pos)
end

---Checks if the window is registered to be centered on resize event
---@return boolean
function M.is_keep_pos(win)
    return pcall(win_get_var, win, _kvars.pos)
end

---Unregisters the window from beign updated on resize event
function M.no_keep_pos(win)
    pcall(win_del_var, win, _kvars.pos)
end

---Registers window to be kept at a relative position during resize event
---@param win integer window-ID
---@param pos fltui.relative_pos Relative window position
function M.keep_pos(win, pos)
    vim.validate('win', win, win_is_valid, 'valid window')
    vim.validate('pos', pos, _rel_pos_validate, 'relative position table')
    local wcfg = win_get_config(win)
    if wcfg.relative == '' then
        return
    end
    local off = _get_offset(win)
    local cfg = {
        relative = wcfg.relative,
        col = _rel_val(pos.col, wcfg),
        row = _rel_val(pos.row, wcfg),
    }

    if cfg.col then
        cfg.col = cfg.col + _get_offset_value(off, 'col')
    else
        cfg.col = wcfg.col
    end

    if cfg.row then
        cfg.row = cfg.row + _get_offset_value(off, 'row')
    else
        cfg.row = wcfg.row
    end

    if cfg.col ~= wcfg.col or cfg.row ~= wcfg.row then
        win_set_config(win, cfg)
    end

    win_set_var(win, _kvars.pos, pos)
    _set_keep(win)
end

---Registers window to update its size during resize event
---@param win integer window-ID
---@param size fltui.relative_size Relative size
function M.keep_size(win, size)
    vim.validate('win', win, win_is_valid, 'valid window')
    vim.validate('size', size, _rel_size_validate, 'relative size table')
    local wcfg = win_get_config(win)
    if wcfg.relative == '' then
        return
    end

    local cfg = {
        height = _rel_val(size.height, wcfg) or wcfg.height,
        width = _rel_val(size.width, wcfg) or wcfg.width,
    }

    if cfg.width ~= wcfg.width or cfg.height ~= wcfg.height then
        win_set_config(win, cfg)
    end

    win_set_var(win, _kvars.size, size)
    _set_keep(win)
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
            if not win_is_valid(logw) then
                logw = vim.api.nvim_open_win(logb, false, logc)
            end

            vim.api.nvim_buf_set_lines(logb, c, -1, true, lines)
            vim.api.nvim_win_set_cursor(logw, { c + #lines, 0 })
        end)
        start = start + #lines
    end
end

return M
