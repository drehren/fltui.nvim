local ui = require('fltui.util')
local col_word = require('fltui.acmp').col_word
local fnameescape = vim.fn.fnameescape
local strridx = vim.fn.strridx
local mceil = math.ceil
local mmax = math.max
local mmin = math.min

local fltuiinputns = vim.api.nvim_create_namespace('fltui.input')

local debounce = require('fltui.debounce').to_safestate

local M = {}

-- special settings for some getcompletion args
local getcompsp = {
    -- we want file to complete like in cmdline :e
    file = {
        opts = {},
        getword = function(opts)
            return function(line, col)
                local ws, we = col_word(line, col)
                if ws == 1 then
                    ws = #opts.prompt + 1
                end
                ws = mmax(strridx(line, '/', we) + 2, ws)
                return ws, we
            end
        end,
        getpattern = function(_, line, col)
            return line:sub(col_word(line, col))
        end,
        fmt = function(w)
            local idx = strridx(w, '/')
            if idx + 1 == #w then
                idx = strridx(w, '/', idx - 1)
            end
            if idx >= 0 then
                w = w:sub(idx + 2)
            end
            return fnameescape(w)
        end,
    },
    cmdline = {
        opts = {},
        getword = function(opts)
            return function(line, col)
                local ws, we = col_word(line, col)
                if ws == 1 then
                    ws = #opts.prompt + 1
                end
                return ws, we
            end
        end,
        getpattern = function(_, line)
            return line
        end,
    },
}
getcompsp.file_in_path = getcompsp.file
getcompsp.dir = getcompsp.file
getcompsp.dir_in_path = getcompsp.dir
getcompsp.breakpoint = getcompsp.cmdline
getcompsp.history = getcompsp.cmdline
getcompsp.messages = getcompsp.cmdline
getcompsp.option = getcompsp.cmdline
getcompsp.runtime = getcompsp.cmdline
getcompsp.sign = getcompsp.cmdline
getcompsp.syntime = getcompsp.cmdline

local function multiline_height_update(_, buf, _, _, from, to)
    if (to - from) ~= 0 then
        local promptwin = vim.fn.win_findbuf(buf)[1]
        local h = vim.api.nvim_win_get_height(promptwin)
        vim.api.nvim_win_set_height(promptwin, h + to - from)
    end
end

local history = require('fltui.input.history')
---@class fltui.input._hmapst
---@field text string?
---@field state fltui.input.history_state
---@field tick boolean
---@field cp [integer, integer]
---@field prev fun():string
---@field next fun():string

---@param st fltui.input._hmapst
---@param prompt string
local function hist_get_prefix(st, prompt)
    st.cp = vim.api.nvim_win_get_cursor(0)
    local bt =
        vim.api.nvim_buf_get_text(0, 0, 0, st.cp[1] - 1, st.cp[2] + 1, {})
    if #bt > 0 and prompt and #prompt > 0 then
        bt[1] = bt[1]:sub(#prompt + 1)
    end
    return table.concat(bt, '\n')
end

---@param txt string
local function hist_set_text(st, txt)
    local buf = vim.api.nvim_get_current_buf()
    vim.schedule(function()
        vim.api.nvim_buf_set_text(buf, st.cp[1] - 1, st.cp[2], -1, -1, {})
        vim.api.nvim_put(
            vim.split(txt, '\n', { plain = true }),
            'c',
            true,
            true
        )
    end)
    return '<Ignore>'
end

---@param st fltui.input._hmapst
---@param prompt string
---@param key string
local hist_map_builder = function(st, prompt, key)
    local pos = key == '<Up>' and -1 or 1
    local function endtick()
        st.tick = false
    end
    return function()
        if not st.text then
            st.text = hist_get_prefix(st, prompt)
        end
        local txt = history.get(st.state, pos, st.text)
        if txt then
            st.tick = true
            debounce(endtick)
            return hist_set_text(st, txt:sub(#st.text + 1))
        end
        return key
    end
end
---@param hstate fltui.input.history_state
---@param prompt string
local function hist_move_maps(hstate, prompt)
    ---@type fltui.input._hmapst
    ---@diagnostic disable-next-line: missing-fields
    local st = {
        cp = { #prompt + 1, 0 },
        tick = false,
        state = hstate,
    }
    st.prev = hist_map_builder(st, prompt, '<Up>')
    st.next = hist_map_builder(st, prompt, '<Down>')
    return st
end

---A [vim.ui.input()](lua://vim.ui.input()) replacement.
---@param opts vim.ui.input.Opts
---@param on_confirm fun(input: string?)
function M.input(opts, on_confirm)
    vim.validate('opts', opts, 'table')
    vim.validate('on_confirm', on_confirm, 'callable')
    opts.prompt = opts.prompt or ''

    local hstate = history.new_state(opts.scope or 'editor')
    local hist = hist_move_maps(hstate, opts.prompt)

    local promptwin
    local auwinenterid
    local promptbuf = ui.create_prompt_buf('input', opts.prompt, function(text)
        vim.api.nvim_del_autocmd(auwinenterid)
        debounce(function()
            if not vim.startswith(vim.api.nvim_get_mode().mode, 'n') then
                vim.cmd.stopinsert()
            end
            vim.api.nvim_win_close(promptwin, true)
            vim.schedule(function()
                if text and text ~= '' then
                    hstate:add(text)
                end
                on_confirm(text)
            end)
        end)
    end)
    local promptcells = vim.fn.strwidth(opts.prompt)

    vim.api.nvim_create_autocmd('TextChangedI', {
        group = ui.augid,
        buffer = promptbuf,
        callback = function()
            if hist.text and not hist.tick then
                hist.text = nil
            end
        end,
    })

    -- history keymaps
    vim.keymap.set('i', '<Up>', hist.prev, {
        desc = 'history prev',
        expr = true,
    })
    vim.keymap.set('i', '<Down>', hist.next, {
        desc = 'history next',
        expr = true,
    })

    -- expand for multiline
    vim.api.nvim_buf_attach(promptbuf, false, {
        on_lines = multiline_height_update,
    })

    if opts.highlight then
        local buf_get_lines = vim.api.nvim_buf_get_lines
        local buf_clear_namespace = vim.api.nvim_buf_clear_namespace
        local buf_set_extmark = vim.api.nvim_buf_set_extmark
        vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
            group = ui.augid,
            buffer = promptbuf,
            callback = function()
                local lines = buf_get_lines(promptbuf, 0, -1, true)
                lines[1] = lines[1]:sub(#opts.prompt + 1)
                buf_clear_namespace(promptbuf, fltuiinputns, 0, -1)
                for i, cinput in ipairs(lines) do
                    local hs = opts.highlight(cinput)
                    for _, h in ipairs(hs or {}) do
                        local row = h[1] - 1
                        buf_set_extmark(promptbuf, fltuiinputns, i - 1, row, {
                            end_col = h[2],
                            hl_group = h[3],
                        })
                    end
                end
            end,
        })
    end

    -- reg completion keymaps

    local curwin = vim.api.nvim_get_current_win()

    local regs = {
        ['<C-L>'] = { vim.api.nvim_get_current_line },
        ['<C-F>'] = { vim.fn.expand, '<cfile>' },
        ['<C-P>'] = { vim.fn.expand, '<cfile>' },
        ['<C-W>'] = { vim.fn.expand, '<cword>' },
        ['<C-A>'] = { vim.fn.expand, '<cWORD>' },
    }
    for lhs, data in pairs(regs) do
        ---@type vim.api.keyset.keymap
        local mapopts = {
            noremap = true,
            expr = true,
            callback = function()
                return vim.api.nvim_win_call(curwin, function()
                    ---@diagnostic disable-next-line: param-type-mismatch
                    return data[1](unpack(data, 2))
                end)
            end,
            nowait = true,
            unique = true,
        }
        vim.api.nvim_buf_set_keymap(promptbuf, 'i', '<C-R>' .. lhs, '', mapopts)
    end

    if not opts.scope then
        opts.scope = 'editor'
    end

    ---@type vim.api.keyset.win_config
    local config = {
        height = 1,
        style = 'minimal',
        zindex = 99,
        border = 'rounded',
    }
    if opts.scope == 'cursor' or opts.scope == 'line' then
        config.relative = 'cursor'
        local cpos = vim.api.nvim_win_get_cursor(curwin)
        local cwinfo = vim.fn.getwininfo(curwin)[1]
        local lbot = cwinfo.botline - cpos[1]
        local ltop = cpos[1] - cwinfo.topline
        if ltop > lbot then
            config.row = -1
        else
            config.row = 1
        end
        config.border = { '', '', '', '▐', '', '', '', '▌' }
        local winw = vim.api.nvim_win_get_width(0)
        if opts.scope == 'cursor' then
            local pos, pose = require('fltui.acmp').find_word(
                vim.api.nvim_get_current_line(),
                cpos[2] + 1,
                '[%s%.]+'
            )
            config.width = (pose - pos + 1) * 2
                + vim.fn.strwidth(opts.prompt)
                + 1
            config.col = -(cpos[2] - pos) - 1
            config.width = mmax(config.width, 30, mceil(winw * 0.2))
        else
            config.col = 0
            config.width = mceil(mmax(vim.o.columns * 0.5, winw))
        end
    elseif opts.scope == 'buffer' or opts.scope == 'window' then
        config.relative = 'win'
        local cwcfg = vim.api.nvim_win_get_config(curwin)
        config.width =
            mmin(cwcfg.width, mmax(mceil(cwcfg.width / 2), 20 + promptcells))
        config.row = cwcfg.height / 2 - 2
        config.col = (cwcfg.width - config.width) / 2
    else
        config.relative = 'editor'
        config.width = mceil(vim.o.columns * 0.47)
        config.row = ui.editor_height() / 2 - 2
        config.col = (vim.o.columns - config.width) / 2
    end

    promptwin = vim.api.nvim_open_win(promptbuf, true, config)

    ui.close_on_leave(promptwin, { force = true, bufchange = true })

    if config.relative == 'editor' then
        ui.keep_centered(promptwin, { -2, 0 })
    end

    auwinenterid = vim.api.nvim_create_autocmd('WinEnter', {
        group = ui.augid,
        nested = true,
        once = true,
        callback = function()
            vim.on_key(nil, fltuiinputns, {})
            on_confirm(nil)
        end,
    })

    if opts.default then
        vim.api.nvim_create_autocmd('InsertEnter', {
            group = ui.augid,
            buffer = promptbuf,
            once = true,
            nested = true,
            callback = function()
                vim.schedule(function()
                    vim.api.nvim_put({ opts.default }, '', false, true)
                end)
            end,
        })
    end

    vim.cmd.startinsert()

    if opts.completion then
        local getcompletion = vim.fn.getcompletion
        local completion
        ---@type fltui.acmp.opts
        local compopts = {}
        ---@type string|function
        local comptype = opts.completion
        if
            type(comptype) ~= 'string'
            or vim.fn.exists('*' .. comptype) == 1
        then
            completion = function(word, line, col)
                if col <= #word and vim.startswith(word, opts.prompt) then
                    word = word:sub(#opts.prompt + 1)
                end
                line = line:sub(#opts.prompt + 1)
                col = col - #opts.prompt
                if type(completion) == 'string' then
                    return vim.fn[comptype](word, line, col)
                else
                    return comptype(word, line, col)
                end
            end
        elseif getcompsp[opts.completion] then
            local sp = getcompsp[opts.completion]
            if sp.opts then
                compopts = vim.tbl_extend('force', compopts, sp.opts)
            end
            if sp.getword then
                compopts.getword = sp.getword(opts)
            end
            completion = function(word, line, col)
                if #opts.prompt > 0 then
                    if col <= #word and vim.startswith(word, opts.prompt) then
                        word = word:sub(#opts.prompt + 1)
                    end
                    line = line:sub(#opts.prompt + 1, col)
                    col = col - #opts.prompt
                end
                local pat = sp.getpattern(word, line, col)
                local items = getcompletion(pat, comptype)
                if sp.fmt then
                    return vim.tbl_map(function(v)
                        return sp.fmt(v, word, line, col)
                    end, items)
                else
                    return items
                end
            end
        else
            completion = function(word, _, col)
                if col <= #word and vim.startswith(word, opts.prompt) then
                    word = word:sub(#opts.prompt + 1)
                end
                return getcompletion(word, comptype)
            end
        end
        compopts.triggerkey = string.char(vim.o.wildchar)
        debounce(function()
            if vim.api.nvim_get_mode().mode == 'i' then
                require('fltui.acmp').install(promptbuf, completion, compopts)
                return true
            end
        end)
    end
end

return M
