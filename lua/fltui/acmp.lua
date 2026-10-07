-- globals

local get_option_value = vim.api.nvim_get_option_value
local get_current_buf = vim.api.nvim_get_current_buf
local set_option_value = vim.api.nvim_set_option_value
local buf_is_valid = vim.api.nvim_buf_is_valid
local buf_set_extmark = vim.api.nvim_buf_set_extmark
local buf_set_text = vim.api.nvim_buf_set_text
local buf_get_lines = vim.api.nvim_buf_get_lines
local win_close = vim.api.nvim_win_close
local win_get_cursor = vim.api.nvim_win_get_cursor
local win_get_config = vim.api.nvim_win_get_config
local win_set_config = vim.api.nvim_win_set_config
local win_is_valid = vim.api.nvim_win_is_valid
local win_set_cursor = vim.api.nvim_win_set_cursor

local mmax = math.max
local mmin = math.min

local strwidth = vim.fn.strwidth

-- constants

local floatns = vim.api.nvim_create_namespace('fltui.acmp')

-- variables

---Autocomplete window
---@type integer
local floatw = -1
---Autocomplete window scrollbar window
---@type integer
local scrollw = -1
---Autocomplete buffer
---@type integer
local floatb = -1
---Movement functions for autocomplete window
---@type fltui.ui.proxy_movements
local move
---@type string|false
local filter
---@type string?
local line
---@type string
local word = ''
---@type number?,number?
local word_start, word_end
---@type string[]?
local items
---@type string[]
local acmpitems
---@type fltui.line_highlights[]
local hls = {}
local previtem

local internal_cursormove = false
local completing = false
local replacing = false

-- functions

local function is_open()
    return win_is_valid(floatw)
end

---@return boolean
local function is_cul()
    return get_option_value('cul', { win = floatw })
end

---@param value boolean
local function set_cul(value)
    set_option_value('cul', value, { win = floatw })
end

local function close_float()
    if is_open() then
        win_close(floatw, true)
        if buf_is_valid(floatb) then
            vim.api.nvim_buf_delete(floatb, { force = true })
        end
    end
    if win_is_valid(scrollw) then
        win_close(scrollw, true)
    end

    floatw = -1
    scrollw = -1
    floatb = -1
    line = nil
    word = ''
    word_start = nil
    word_end = nil
    items = nil
    acmpitems = {}
    hls = {}
    previtem = nil
    completing = false
    internal_cursormove = false
    replacing = false

    -- to remove autocmds
    return true
end

local function cur_item(cul, row)
    if not row and (cul or is_cul()) then
        row = win_get_cursor(floatw)[1] - 1
    end
    if row then
        return acmpitems[row + 1]
    end
end

local function replace(buf, item, row, col, setcursor)
    replacing = true
    buf_set_text(buf, row, word_start - 1, row, col, { item })
    if setcursor then
        internal_cursormove = true
        win_set_cursor(0, { row + 1, word_start + strwidth(item) - 1 })
    end
end

local function preview(buf, cul, row, col)
    local item = cur_item(cul)
    if previtem == item then
        return ''
    end
    previtem = item
    if item and is_cul() then
        return replace(buf, item, row, col, true)
    else
        return replace(buf, word, row, col, true)
    end
end

local function set_mappings(buf)
    vim.keymap.set('i', '<C-N>', function()
        if not is_open() then
            return '<C-N>'
        end
        local cw = vim.api.nvim_get_current_win()
        vim.schedule(function()
            local row, col = unpack(win_get_cursor(cw))
            row = row - 1
            local cul = true
            if is_cul() then
                if move.line_down_wrap() then
                    set_cul(false)
                    cul = false
                end
            else
                set_cul(true)
            end
            preview(buf, cul, row, col)
        end)
        return '<Ignore>'
    end, { expr = true, buffer = buf, silent = true })

    vim.keymap.set('i', '<C-P>', function()
        if not is_open() then
            return '<C-P>'
        end
        local cw = vim.api.nvim_get_current_win()
        vim.schedule(function()
            local row, col = unpack(win_get_cursor(cw))
            row = row - 1
            local cul = true
            if is_cul() then
                if move.line_up_wrap() then
                    move.to_top()
                    set_cul(false)
                    cul = false
                end
            else
                move.line_up_wrap()
                set_cul(true)
            end
            preview(buf, cul, row, col)
        end)
        return '<Ignore>'
    end, { expr = true, buffer = buf, silent = true })

    vim.keymap.set('i', '<C-Y>', function()
        if not is_open() then
            return '<C-Y>'
        end
        completing = true
        return cur_item(true)
    end, { expr = true, buffer = buf })
end

local movement = require('fltui.util.movement')
local ui = require('fltui.util')

local function open_floatw(win, buf, row, width, height)
    local scrb = require('fltui.scrb')
    floatw = vim.api.nvim_open_win(floatb, false, {
        relative = 'win',
        col = -1,
        bufpos = { row, word_start - 1 },
        win = win,
        height = height,
        width = width,
        focusable = false,
        mouse = true,
        style = 'minimal',
        noautocmd = true,
        border = 'none',
        zindex = 100,
    })
    set_option_value('scrolloff', 0, { win = floatw })
    set_option_value(
        'winhl',
        'Normal:Pmenu,CursorLine:PmenuSel',
        { win = floatw }
    )

    local close_auopts = {
        nested = true,
        group = ui.augid,
        buffer = buf,
        callback = close_float,
    }
    vim.api.nvim_create_autocmd('ModeChanged', close_auopts)
    vim.api.nvim_create_autocmd('WinLeave', close_auopts)

    vim.api.nvim_create_autocmd('WinEnter', {
        nested = true,
        group = ui.augid,
        buffer = buf,
        callback = function()
            if not win_is_valid(floatw) then
                return true
            end
            vim.api.nvim_set_current_win(win)
        end,
    })
    vim.api.nvim_create_autocmd('WinScrolled', {
        nested = true,
        group = ui.augid,
        callback = function()
            if not win_is_valid(floatw) then
                return true
            end
            if vim.v.event[tostring(floatw)] then
                if is_cul() then
                    local r, c = unpack(win_get_cursor(win))
                    r = r - 1
                    preview(buf, true, r, c)
                end
                ui.no_scrolloff(floatw)
            end
        end,
    })
    move = movement.proxy_to(floatw)
    set_mappings(buf)
    scrollw = scrb.add_vertical_scrollbar(floatw)
    local allowed = vim.w[win]._fltui_ui_keep
    if allowed then
        allowed[#allowed + 1] = floatw
        allowed[#allowed + 1] = scrollw
        vim.w[win]._fltui_ui_keep = allowed
    end
end

local function update_floatw(win, row, width, height)
    local floatc = win_get_config(floatw)
    if
        floatc.width ~= width
        or floatc.height ~= height
        or floatc.bufpos[1] ~= row
        or floatc.bufpos[2] ~= word_start - 1
    then
        set_cul(false)
        win_set_config(floatw, {
            relative = 'win',
            win = win,
            col = -1,
            bufpos = { row, word_start - 1 },
            width = width,
            height = height,
        })
    end
end

local function get_word(buf, fn, row, col)
    word = ''
    line = buf_get_lines(buf, row, row + 1, true)[1]
    word_start, word_end = fn(line, col)
    word = line:sub(word_start, word_end)
    if word == '' and items then
        items = nil
        acmpitems = {}
    end
    return word ~= ''
end

local hlids = {
    PmenuMatch = vim.api.nvim_get_hl_id_by_name('PmenuMatch'),
    PmenuMatchSel = vim.api.nvim_get_hl_id_by_name('PmenuMatchSel'),
    Normal = vim.api.nvim_get_hl_id_by_name('Normal'),
}

local fuzzy

---@param completer fun(word:string, line:string, col:number):string[]
local function generate_matches(completer, col)
    ---@cast word -nil
    ---@cast line -nil
    ---@cast word_start -nil

    if filter then
        -- when filtering item, we just get all possible values
        if not items then
            items = completer('', line, word_start)
        end
        if not fuzzy then
            fuzzy = require('fltui.fuzzy')
        end
        local indexes
        indexes, hls = fuzzy.match(items, word, {
            fuzzy = filter == 'fuzzy',
            hl_char = hlids.PmenuMatchSel,
        })
        acmpitems = vim.tbl_map(function(i)
            return items[i]
        end, indexes)
    else
        items = completer(word, line, col)
        acmpitems = items
        for i = 1, #items do
            hls[i] = { { 1, #word, hlids.PmenuMatchSel } }
        end
        for i = #items + 1, #hls do
            hls[i] = nil
        end
    end
end

local floatbsep = {
    end_col = 1,
    virt_text = { { ' ' } },
    virt_text_pos = 'inline',
}
local function update_floatb()
    if not buf_is_valid(floatb) then
        floatb = ui.create_wipe_buf('acmp')
    end
    vim.api.nvim_buf_clear_namespace(floatb, floatns, 0, -1)
    vim.api.nvim_buf_set_lines(floatb, 0, -1, false, acmpitems)

    local idx = 0
    if is_open() then
        if is_cul() then
            idx = win_get_cursor(floatw)[1]
        end
    end

    for i = 1, #acmpitems do
        buf_set_extmark(floatb, floatns, i - 1, 0, floatbsep)
        if i ~= idx then
            for _, hl in ipairs(hls[i]) do
                buf_set_extmark(floatb, floatns, i - 1, hl[1] - 1, {
                    end_col = hl[2],
                    hl_group = hl[3],
                })
            end
        end
    end
end

local M = {}

local bslash = string.byte('\\')

---Finds a complete word from a string at a specified location.
---
---A word is a range of characters separated by a non backslash-escaped
---pattern (default: "%s").
---@param str string The string to extract the word from
---@param pos integer The byte index of the word position
---@param pattern string? The pattern which separates words (default: "%s")
---@param init integer? Byte to start search from (default: 1)
---@return integer start
---@return integer end
function M.find_word(str, pos, pattern, init)
    if pos > #str then
        return 1, 0
    end
    if pos < 0 then
        pos = mmax(pos, -#str)
        pos = #str + pos + 1
    end
    init = init or 1
    if init < 0 then
        init = mmax(init, -#str)
        init = #str + init + 1
    end
    if pos < init then
        return 1, 0
    end
    pattern = pattern or '%s'
    local l = init
    local s, e = str:find(pattern, init)
    while s do
        if str:byte(s - 1) == bslash then
            s = e + 1
        end
        if s <= e then
            if pos < s then
                break
            end
            ---@cast e -?
            l = e
            if pos <= e then
                break
            end
        end
        init = e + 1
        s, e = str:find(pattern, init)
    end
    if str:find(pattern, l) == l then
        l = l + 1
    end
    s = mmin(s and s - 1 or #str, #str)
    return l, s
end

---Finds (part of) a word from a string at the specified location.
---
---A word is first defined as a non-escaped whitespace separated chars.
---If wordpat is given, then this word is processed to comply with the given
---pattern.
---@param str string The string to find the word from
---@param pos number The byte index of the word position
---@param wordpat string? Word pattern
---@return integer start
---@return integer end
function M.col_word(str, pos, wordpat)
    ---@type integer?, integer?
    local s, e = M.find_word(str, pos)
    if wordpat then
        s, e = str:find(wordpat, s)
        if not s or e < pos then
            s, e = 1, 0
        end
    end
    ---@cast s -?
    ---@cast e -?
    e = mmin(e, pos)
    return s, e
end

---Autocomplete options
---@class fltui.acmp.opts
---How will entries be filtered
---@field filter? 'fuzzy'|'match'|boolean
---Key to force trigger autocomplete
---@field triggerkey? string
---Change how the word is calculated from given line, at col position
---@field getword? fun(line:string, col:number):number?,number?

---Installs autocomplete to the specified buffer, using the given completer.
---@param buf integer buffer-ID
---@param completer fun(word: string, line:string, col:integer):string[]
---@param opts? fltui.acmp.opts Completer options
function M.install(buf, completer, opts)
    vim.validate('buf', buf, buf_is_valid, 'invalid buffer')
    vim.validate('completer', completer, 'callable')

    opts = opts or {}
    vim.validate('opts.filter', opts.filter, { 'string', 'boolean' }, true)
    if type(opts.filter) == 'string' then
        filter = opts.filter
        vim.validate('opts.filter', opts.filter, function(v)
            return v == 'fuzzy' or v == 'match'
        end, '"fuzzy" or "match"')
    else
        filter = false
    end
    vim.validate('opts.triggerkey', opts.triggerkey, 'string', true)

    local triggered = false

    local first_word = opts.getword or M.col_word

    local function acmp()
        local ev = { buf = get_current_buf() }
        local row, col = unpack(win_get_cursor(0))
        row = row - 1
        -- get word
        get_word(ev.buf, first_word, row, col)

        -- generate matches
        if triggered or word ~= '' then
            triggered = false
            generate_matches(completer, col)
        end

        -- check
        if #acmpitems == 0 or (#acmpitems == 1 and acmpitems[1] == word) then
            return close_float()
        end

        update_floatb()

        local width = vim.iter(acmpitems):map(strwidth):fold(0, mmax)
        width = width + 2
        local height = mmin(#acmpitems, 10)

        if not is_open() then
            open_floatw(0, ev.buf, row, width, height)
        elseif is_open() then
            update_floatw(0, ev.buf, width, height)
        end
    end

    vim.api.nvim_create_autocmd('TextChangedI', {
        buffer = buf,
        callback = function(ev)
            if not replacing and not completing then
                acmp()
            elseif replacing and not completing then
                replacing = false
            elseif completing and not replacing then
                local row = unpack(win_get_cursor(0)) - 1
                local col = word_start + #cur_item(true) - 1
                internal_cursormove = true
                buf_set_text(ev.buf, row, word_start - 1, row, col, {})
                vim.schedule(close_float)
            end
        end,
    })

    vim.api.nvim_create_autocmd('CursorMovedI', {
        buffer = buf,
        callback = function()
            if not internal_cursormove and not completing and not replacing then
                -- calculate again to properly complete
                triggered = true
                acmp()
            elseif internal_cursormove then
                internal_cursormove = false
            end
        end,
    })

    if opts.triggerkey then
        vim.validate('opts.triggerkey', opts.triggerkey, 'string')
        local tk = vim.fn.keytrans(opts.triggerkey)
        vim.keymap.set('i', tk, function()
            if not is_open() then
                triggered = true
                vim.schedule(acmp)
                return ''
            end
            if #acmpitems == 1 and is_cul() then
                return '<C-Y>'
            else
                return '<C-N>'
            end
        end, { buffer = buf, expr = true, remap = true })

        local stk = '<S-%s>'
        if tk:find('<') then
            stk = stk:format(tk:match('%b<>'):sub(2, -2))
        else
            stk = stk:format(tk)
        end
        vim.keymap.set('i', stk, function()
            if not is_open() then
                triggered = true
                vim.schedule(acmp)
                return ''
            end
            if #acmpitems == 1 and is_cul() then
                return '<C-Y>'
            else
                return '<C-P>'
            end
        end, { buffer = buf, expr = true, remap = true })
    end
end

return M
