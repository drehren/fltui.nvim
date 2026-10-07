---1-based index range, end-inclusive
---@alias fltui.range [integer, integer]

---Specifies options for ui.select
---@class fltui.select.options: vim.ui.select.Opts
---Adds a search box to sort elements.
---@field search? fltui.select.search_type
---Filters non-matching elements.
---@field filter? boolean

---Expected return value from an action handler
---@alias fltui.select.action_result
---| fltui.select.action_result.reload
---| fltui.select.action_result.update
---| fltui.select.action_result.close
---| fltui.select.action_result.replace

---Reloads the selection
---@class fltui.select.action_result.reload
---@field type "reload"
---Move selection to the specified index
---@field preselect? integer

---Replace the selection and reload
---@class fltui.select.action_result.replace
---@field type "replace"
---Items to replace the current ones
---@field items any[]
---Replace options
---@field opts? fltui.select.options
---Replace on_choice
---@field on_choice? fun(item?: any, index?: integer)
---Replace actions
---@field actions? fltui.select.action_map

---Updates the items that had been selected
---@class fltui.select.action_result.update
---@field type "update"
---Move selection to the specified index
---@field preselect? integer

---Closes the selection window
---@class fltui.select.action_result.close
---@field type "close"

---Defines an action function
---@alias fltui.select.action fun(items: any[], indexes: integer[])

---Maps key in normal and visual modes to action function
---@alias fltui.select.action_map
---| table<string, fun(items: any[], indexes: integer[]): fltui.select.action_result?>

---A highlight group, can be its name, id or a table of any of those
---@alias fltui.highlight_group integer | string | (integer | string)[]
---A 3-tuple, 1-indexed inclusive range (start, end) and highlight group
---@alias fltui.highlight_range [integer, integer, fltui.highlight_group]
---A line highlight is a list of character ranges and their highlight groups
---@alias fltui.line_highlights fltui.highlight_range[]
---If search is enabled, how items will be searched
---@alias fltui.select.search_type 'fuzzy'|'match'

local ui = require('fltui.util')

local fltuins = vim.api.nvim_create_namespace('fltui.select')
vim.api.nvim_set_hl(fltuins, 'Visual', {})
vim.api.nvim_set_hl(fltuins, 'VisualNOS', {})

local maxlinewidth = 124
local minlinewfact = 0.2

local mfloor = math.floor
local mmin, mmax = math.min, math.max
local strwidth = vim.fn.strwidth

local get_option_value = vim.api.nvim_get_option_value
local set_option_value = vim.api.nvim_set_option_value

local win_set_buf = vim.api.nvim_win_set_buf
local win_get_buf = vim.api.nvim_win_get_buf
local win_set_config = vim.api.nvim_win_set_config
local win_get_config = vim.api.nvim_win_get_config
local win_set_cursor = vim.api.nvim_win_set_cursor
local win_get_cursor = vim.api.nvim_win_get_cursor
local win_get_width = vim.api.nvim_win_get_width
local win_is_valid = vim.api.nvim_win_is_valid

local buf_get_lines = vim.api.nvim_buf_get_lines
local buf_set_keymap = vim.api.nvim_buf_set_keymap
local buf_set_extmark = vim.api.nvim_buf_set_extmark

---Performs min and max at the same time for the same arguments
---@param ... number The numbers to min max
---@return number min The minimum
---@return number max The maximum
local function minmax(...)
    return mmin(...), mmax(...)
end

local function list_end(last, ...)
    for _, list in ipairs({ ... }) do
        for i = last + 1, #list do
            list[i] = nil
        end
    end
end

local hlids = {}
do
    local get_hl_id_by_name = vim.api.nvim_get_hl_id_by_name
    hlids.Bold = get_hl_id_by_name('Bold')
    hlids.CursorLine = get_hl_id_by_name('CursorLine')
    hlids.LineNr = get_hl_id_by_name('LineNr')
    hlids.CursorLineNr = get_hl_id_by_name('CursorLineNr')
end

---@class fltui.select
---@field items any[]
---@field opts fltui.select.options select user options
---@field on_choice fun(item: any?, index: integer?) on_choice callback
---@field actions fltui.select.action_map select user actions
---@field buf integer selection buffer
---@field win integer selection window
---@field pwin integer selection preview window
---@field custom_index string? pattern to find index on item line
---@field package culrange [integer, integer?] range in item window
---@field private linewidth fltui.simple_heap<[integer, integer]> line widths
---@field private _sfmt string?
local S = {
    ---selection namespace
    ns = fltuins,
    ---@type fltui.select
    super = nil,
}
S.__index = S

---Gets the amount of cells the line width exceeds
---@protected
---@param linew integer Line width in cells to check
---@return integer excess
function S:linewidth_excess(linew)
    return mmax(linew - maxlinewidth + 1, 0)
end

---Custom item highlight.
---@protected
---@param linenr integer Line number to highlight
---@param line string Line text
---@diagnostic disable-next-line: unused-local
function S:item_highlight(linenr, line) end

---Item highlight on item selection.
---
---Highlights the custom index if exists.
---Highlights the line selection.
---@protected
---@param linenr integer
---@param line string
---@diagnostic disable-next-line: unused-local
function S:cursorline_highlight(linenr, line) end

---Gets the current maximum item line width
---@protected
---@return integer width
function S:get_width()
    return self.linewidth:front()[1]
end

---Calculates the height of the selection window
---@protected
---@return number height
function S:calc_height()
    return mmax(1, mmin(#self.items, mfloor(ui.editor_height() * 0.8)))
end

---Updates windows to current width
---@protected
---@param wins? integer[]
function S:update_win_width(wins)
    local width = self:get_width()
    local windows = { self.win }
    if wins then
        vim.list_extend(windows, wins)
    end
    local cfg = { relative = 'editor', width = width }
    for _, w in ipairs(windows) do
        local curcfg = win_get_config(w)
        cfg.row = curcfg.row
        cfg.col = mfloor((vim.o.columns - width) / 2)
        win_set_config(w, cfg)
    end
end

---@param self fltui.select
---@param linenr integer
---@param line string
---@param hlid integer
---@return integer
local function index_hl(self, linenr, line, hlid)
    ---@type vim.api.keyset.set_extmark
    local ext = {}
    local _, e = line:find(self.custom_index)
    ext.end_col = assert(e, 'could not find index in item line') - 1
    ext.hl_group = hlid
    ext.virt_text = { { line:sub(1, e), hlid } }
    ext.virt_text_pos = 'overlay'

    buf_set_extmark(self.buf, self.ns, linenr - 1, 0, ext)
    return ext.end_col + 1
end

---@param self fltui.select
---@param linenr integer
---@param line string
local function cul_hl(self, linenr, line)
    -- set index
    local e = index_hl(self, linenr, line, hlids.CursorLineNr)

    ---@type vim.api.keyset.set_extmark
    local ext = {}
    ext.end_col = #line
    ext.hl_group = hlids.Bold
    -- current item is bold
    buf_set_extmark(self.buf, self.ns, linenr - 1, 0, ext)

    -- cursor line highlight
    ext.hl_group = hlids.CursorLine
    if not self.culrange[2] then
        ext.end_col = nil
        ext.end_row = linenr
        ext.hl_eol = true
    else
        ext.end_col = #line
    end
    buf_set_extmark(self.buf, self.ns, linenr - 1, e, ext)
end

---Sets selection buffer highlights
---@protected
---@param start? integer 0-index
---@param end_? integer 0-index, exclusive
function S:buf_set_hl(start, end_)
    start = start or 0
    end_ = end_ or -1

    local buf = self.buf
    vim.api.nvim_buf_clear_namespace(buf, self.ns, start, end_)

    local lines = buf_get_lines(buf, start, end_, true)
    if start < 0 then
        start = vim.api.nvim_buf_line_count(buf) + start
    end
    if start == 0 and lines[1] == '' then
        return
    end

    local culmin, culmax = minmax(unpack(self.culrange))
    culmin = culmin - start
    culmax = culmax - start

    for i = 1, culmin - 1 do
        local linenr = i + start
        self:item_highlight(linenr, lines[i])
        index_hl(self, linenr, lines[i], hlids.LineNr)
    end
    for i = culmin, culmax do
        local linenr = i + start
        self:cursorline_highlight(linenr, lines[i])
        cul_hl(self, linenr, lines[i])
    end
    for i = culmax + 1, #lines do
        local linenr = i + start
        self:item_highlight(linenr, lines[i])
        index_hl(self, linenr, lines[i], hlids.LineNr)
    end
end

---@private
---@param linenr integer
function S:buf_cul(linenr)
    if not self.culrange[2] then
        if self.culrange[1] ~= linenr then
            self.culrange[1] = linenr
            if win_is_valid(self.win) and self.opts.preview_item then
                self:preview_item(linenr)
            end
        end
    else
        self.culrange[2] = linenr
    end
end

---Generates an item preview, if corresponds
---@protected
---@param linenr integer
function S:preview_item(linenr)
    if not self.opts.preview_item or not win_is_valid(self.win) then
        return
    end

    -- ignore close during preview ... we might get spurious BufEnter/BufLeave
    -- events
    local prv
    ui.close_on_leave_ignore_call(self.win, function()
        prv = self.opts.preview_item(self.items[self:item_index(linenr)])
    end)
    if not prv.buf then
        if win_is_valid(self.pwin) then
            vim.api.nvim_win_close(self.pwin, true)
        end
        return
    end

    prv.pos = prv.pos or { 1, 0 }
    local h
    local w
    if not prv.pos_end then
        local ln = buf_get_lines(prv.buf, prv.pos[1] - 1, prv.pos[1], true)[1]
        h = 1
        w = strwidth(ln) + 1
    else
        local lns = buf_get_lines(prv.buf, prv.pos[1] - 1, prv.pos_end[1], true)
        h = #lns
        w = 0
        for _, ln in ipairs(lns) do
            w = mmax(w, strwidth(ln)) + 1
        end
    end

    if not win_is_valid(self.pwin) then
        self.pwin = vim.api.nvim_open_win(prv.buf, false, {
            relative = 'win',
            win = self.win,
            row = -1,
            col = self:get_width() + 1,
            height = h,
            width = w,
            style = 'minimal',
            focusable = false,
            fixed = true,
            border = 'single',
            zindex = 98,
            noautocmd = true,
        })
        ui.close_on_leave_allowed(self.win, self.pwin)
        vim.api.nvim_create_autocmd('WinClosed', {
            once = true,
            nested = true,
            pattern = tostring(self.win),
            callback = function()
                if vim.api.nvim_win_is_valid(self.pwin) then
                    vim.api.nvim_win_close(self.pwin, true)
                end
            end,
        })
    else
        if win_get_buf(self.pwin) ~= prv.buf then
            win_set_buf(self.pwin, prv.buf)
        end
        win_set_config(self.pwin, { width = w, height = h })
    end
    win_set_cursor(self.pwin, prv.pos)
end

---Sets or changes selection buffer lines
---@protected
---@param lines string[]
---@param start integer? 0-index
---@param end_ integer? 0-index, exclusive
function S:buf_set_lines(lines, start, end_)
    local opts = { buf = self.buf }
    start = start or 0
    end_ = end_ or -1
    set_option_value('ma', true, opts)
    vim.api.nvim_buf_set_lines(self.buf, start, end_, true, lines)
    set_option_value('ma', false, opts)
    set_option_value('mod', false, opts)

    if #lines > 0 then
        local linenr = 1
        if win_is_valid(self.win) then
            linenr = win_get_cursor(self.win)[1]
        end
        self:buf_cul(linenr)
        self:buf_set_hl(start, end_)

        if not self.culrange[2] and self.opts.preview_item then
            self:preview_item(self.culrange[1])
        end
    elseif start == 0 and end_ == -1 then
        vim.api.nvim_buf_clear_namespace(self.buf, self.ns, 0, -1)
        local w = self:get_width()
        local msg = ('%s-- No items --'):format((' '):rep(w / 2 - 8))
        buf_set_extmark(self.buf, self.ns, 0, 0, {
            virt_text = { { msg } },
        })
        if vim.api.nvim_win_is_valid(self.pwin) then
            vim.api.nvim_win_close(self.pwin, true)
        end
    end
end

---@return fltui.select? kind_sel
local function load_kindmt(kind)
    local modname = 'fltui.select.kind.' .. kind
    local exists = false

    if package.loaded[modname] then
        exists = true
    else
        for _, l in ipairs(package.loaders) do
            local loader = l(modname)
            if type(loader) == 'function' or vim.is_callable(loader) then
                package.preload[modname] = loader
                exists = true
            end
        end
    end

    if exists then
        return require(modname)
    end
end

---Formats the specified item
---@protected
---@param item any
---@return string line
function S:format_item(item, index)
    return self._sfmt:format(index, self.opts.format_item(item))
end

---Process the formatting of the item at the specified index.
---@protected
---@param index integer Item index
---@return string line
function S:process_format(index)
    return self:format_item(self.items[index], index)
end

---Updates the selection window
---@param line_count integer
---@protected
function S:update_window(line_count)
    local height = self:calc_height()
    self.culrange[2] = nil

    vim.api.nvim_win_set_height(self.win, height)
    if self.culrange[1] > 0 then
        self.culrange[1] = mmin(self.culrange[1], line_count)
        if line_count > 0 then
            win_set_cursor(self.win, { self.culrange[1], 0 })
        end
    end

    if win_get_width(self.win) ~= self:get_width() then
        self:update_win_width()
    end
end

local esckey = vim.api.nvim_replace_termcodes('<esc>', true, true, true)

---@class (exact) fltui.select.action_handler.data
---@field linenr integer
---@field lastlinenr integer
---@field idxs integer[]
---@field items any[]

---@protected
---@param result? fltui.select.action_result
function S:action_result(result)
    if result then
        local action_result = 'action_' .. result.type
        if not self[action_result] then
            error(('[fltui.select] Unknown result type %q'):format(result.type))
        end
        self[action_result](self, result)
    end
    if vim.api.nvim_get_mode().mode ~= 'n' then
        vim.api.nvim_win_call(self.win, function()
            vim.api.nvim_feedkeys(esckey, 'L', false)
        end)
    end
end

---Called when a user action returns a "replace" result
---@protected
---@param result fltui.select.action_result.replace
function S:action_replace(result)
    self.items = result.items or self.items
    self.opts = result.opts or self.opts
    self.on_choice = result.on_choice or self.on_choice

    if result.actions then
        self:remove_actions()
        self.actions = result.actions
        self:install_actions()
    end

    list_end(0, self.linewidth)

    local lines = self:process_items()
    self:buf_set_lines(lines)
    if win_is_valid(self.win) then
        self:update_window(#lines)
    end
end

---Called when a user action returns an "update" result
---@protected
---@param result fltui.select.action_result.update
function S:action_update(result)
    -- current width
    local curw = self:get_width()

    -- view indexes
    local start = self.culrange[1]
    local end_ = self.culrange[2] or start

    -- get item indexes
    local first = self:item_index(start)
    local last = self:item_index(end_)
    local lines = self:process_items(first, last)

    -- was width updated ?
    if curw ~= self:get_width() then
        self:update_win_width()
    end

    if end_ == vim.api.nvim_buf_line_count(self.buf) then
        end_ = -1
    end
    self:buf_set_lines(lines, start - 1, end_)

    if result.preselect then
        local cul = win_get_cursor(self.win)
        cul[1] = self:item_linenr(result.preselect)
        if cul[1] > 0 then
            win_set_cursor(self.win, cul)
        end
    end
end

---Called when a user action returns a "reload" result
---@protected
---@param result fltui.select.action_result.reload
function S:action_reload(result)
    local lines = self:process_items()
    self:buf_set_lines(lines)
    self:update_window(#lines)
    if result.preselect then
        local cul = win_get_cursor(self.win)
        cul[1] = self:item_linenr(result.preselect)
        if cul[1] > 0 then
            win_set_cursor(self.win, cul)
        end
    end
end

---Called when a user action returns a "close" result
---@protected
function S:action_close()
    local w = self.win
    vim.schedule(function()
        if win_is_valid(w) then
            vim.api.nvim_win_close(w, true)
        end
    end)
end

local function is_positive(v)
    return v >= 0
end

---Processes all items in the specified range.
---
---Returns the formated lines in a table.
---@protected
---@param first integer? 1-index start range
---@param last integer? 1-index end range
---@return string[] lines The item lines in the specified range
function S:process_items(first, last)
    first = first or 1
    last = last or #self.items
    vim.validate('first', first, is_positive, 'positive index')
    vim.validate('last', last, is_positive, 'positive index')

    local minw = strwidth(self.opts.prompt)
    minw = mmax(minw, mfloor(vim.o.columns * minlinewfact))
    minw = mmin(maxlinewidth, vim.o.columns, minw)

    if #self.linewidth == 0 then
        self.linewidth:push({ minw, -1 })
    end

    local lines = {}
    for i = first, last do
        local line = self:process_format(i)
        -- add margin to the left
        local linew = strwidth(line) + 1
        local id = first + i
        if self.linewidth:front()[2] == id then
            self.linewidth:replace({ linew, id })
        else
            self.linewidth:push({ linew, id })
        end
        lines[#lines + 1] = line
    end
    return lines
end

---Gets the item index for the specified line number.
---@protected
---@param linenr integer Line number.
---@return integer index
function S:item_index(linenr)
    return linenr
end

---Gets the line number for the specified item index.
---@protected
---@param index integer Item index.
---@return integer linenr
function S:item_linenr(index)
    return index
end

---Creates the selection buffer
---@protected
function S:create_buf()
    buf_set_keymap(self.buf, 'n', '<CR>', '', {
        callback = function()
            self:select()
        end,
    })

    -- Mouse interaction .. because why not?
    buf_set_keymap(self.buf, 'n', '<2-LeftMouse>', '<CR>', {})

    -- Make the following noopf to avoid 'no modifiable' errors
    local noopkeys = 'dDiIoOpPsScC'
    for rhs in noopkeys:gmatch('.') do
        buf_set_keymap(self.buf, 'n', rhs, '', {})
    end

    -- Buffer close without selection
    buf_set_keymap(self.buf, 'n', '<ESC>', '<cmd>q!<cr>', {})
    buf_set_keymap(self.buf, 'n', 'q', '<ESC>', {})
    buf_set_keymap(self.buf, 'n', '<C-C>', '<ESC>', {})
end

---Performs the selection of the selected item
---@protected
function S:select()
    local selected_index
    local nr = vim.v.count
    if nr > 0 and nr <= vim.api.nvim_buf_line_count(self.buf) then
        selected_index = nr
    else
        local row = win_get_cursor(self.win)[1]
        selected_index = self:item_index(row)
    end
    ---On close
    vim.api.nvim_create_autocmd('BufWipeout', {
        group = ui.augid,
        buffer = self.buf,
        nested = true,
        callback = function()
            require('fltui.debounce').to_safestate(function()
                if selected_index then
                    self.on_choice(self.items[selected_index], selected_index)
                else
                    self.on_choice(nil, nil)
                end
            end)
        end,
    })
    vim.schedule(vim.cmd.close)
end

---Shows the selection window
---@param enter boolean to enter selection window
function S:show(enter)
    self:create_buf()

    local lines = self:process_items()
    self:buf_set_lines(lines)

    self:open_win(enter)
    self:install_actions()
end

---Opens the selection window.
---
---It is expected that create_buf had been previously called.
---@protected
---@param enter boolean
function S:open_win(enter)
    ---@type vim.api.keyset.win_config
    local config = {
        width = self:get_width(),
        height = self:calc_height(),
        relative = 'editor',
        style = 'minimal',
        zindex = 99,
        border = 'rounded',
        title = self.opts.prompt,
    }
    config.col = mfloor((vim.o.columns - config.width) / 2)
    config.row = mfloor((ui.editor_height() - config.height) / 2)

    self.win = vim.api.nvim_open_win(self.buf, enter, config)

    local winopts = { win = self.win }
    set_option_value('scrolloff', 0, winopts)

    -- open before as user may use bufload or bufnr which trigger BufEnter
    -- which will close our window
    if self.opts.preview_item then
        self:preview_item(self.culrange[1])
    end

    vim.api.nvim_create_autocmd('WinScrolled', {
        nested = true,
        group = ui.augid,
        callback = function()
            if not win_is_valid(self.win) then
                return true
            end
            ui.no_scrolloff(self.win)
        end,
    })

    ui.close_on_leave(self.win)
    ui.keep_centered(self.win)

    vim.api.nvim_win_set_hl_ns(self.win, self.ns)

    vim.api.nvim_create_autocmd('ModeChanged', {
        group = ui.augid,
        pattern = '[vV]:*',
        callback = function()
            if not win_is_valid(self.win) then
                return true
            end
            self.culrange[1] = win_get_cursor(self.win)[1]
            self.culrange[2] = nil
            self:buf_set_hl()
        end,
    })

    vim.api.nvim_create_autocmd('ModeChanged', {
        group = ui.augid,
        pattern = '*:[vV]',
        callback = function()
            if not win_is_valid(self.win) then
                return true
            end
            self.culrange[2] = self.culrange[1]
            self:buf_set_hl()
        end,
    })

    vim.api.nvim_create_autocmd('CursorMoved', {
        group = ui.augid,
        buffer = self.buf,
        callback = function()
            if not win_is_valid(self.win) then
                return true
            end
            self:buf_cul(win_get_cursor(self.win)[1])
            self:buf_set_hl()
        end,
    })
end

---Gets the buffer to which the actions should be mapped to
---@protected
---@return integer buffer
function S:get_action_buffer()
    return self.buf
end

---Removes the user action mappings to the action buffer
---@protected
function S:remove_actions()
    local opts = { buffer = self:get_action_buffer() }
    for key in pairs(self.actions) do
        vim.keymap.del({ 'n', 'v' }, key, opts)
    end
end

---Adds the user action mappings to the action buffer
---@protected
function S:install_actions()
    local opts = { buffer = self:get_action_buffer() }
    for key, action in pairs(self.actions) do
        vim.keymap.set({ 'n', 'v' }, key, function()
            local first, last =
                minmax(self.culrange[1], self.culrange[2] or self.culrange[1])
            local items = {}
            local indices = {}
            for i = first, last do
                local item_i = self:item_index(i)
                table.insert(items, self.items[item_i])
                table.insert(indices, item_i)
            end

            self:action_result(action(items, indices))
        end, opts)
    end
end

---Creates a new selection object
---@param items any[]
---@param opts vim.ui.select.Opts
---@param on_choice fun(item: any?, index: integer?)
---@param actions? fltui.select.action_map
---@return fltui.select selection
function S:new(items, opts, on_choice, actions)
    vim.validate('items', items, 'table')
    vim.validate('opts', opts, 'table')
    vim.validate('on_choice', on_choice, 'function')
    vim.validate('actions', actions, 'table', true)

    opts.prompt = opts.prompt or 'Select one of:'
    opts.kind = opts.kind or 'default'
    opts.format_item = opts.format_item or tostring

    local nuw = get_option_value('nuw', {})

    ---@type fltui.select
    local sel = {
        win = -1,
        buf = ui.create_wipe_buf('selection'),
        linewidth = require('fltui.heap').new(function(lhs, rhs)
            return lhs[1] > rhs[1]
        end),
        culrange = { 0 },
        items = items,
        opts = opts --[[@as fltui.select.options]],
        on_choice = on_choice,
        actions = actions or {},
        custom_index = '^%s*%d+ ',
        pwin = -1,
        _sfmt = ('%%%dd %%s'):format(nuw),
    }
    return setmetatable(sel, self)
end

local M = {}

---Opens a selection window
---@param items any[] Arbitrary items
---@param opts fltui.select.options|vim.ui.select.Opts Additional options
---@param on_choice fun(item: any?, index: integer?)
---@param actions? fltui.select.action_map User actions map
function M.select(items, opts, on_choice, actions)
    vim.validate('items', items, 'table')
    vim.validate('opts', opts, 'table')
    vim.validate('opts.search', opts.search, { 'boolean', 'string' }, true)
    vim.validate('opts.filter', opts.filter, 'boolean', true)
    vim.validate('on_choice', on_choice, 'function')
    vim.validate('actions', actions, 'table', true)

    opts = vim.deepcopy(opts)

    ---@type fltui.config.select_search?
    local cfg = vim.g.fltui_select_search
    if opts.search ~= false and type(cfg) == 'table' then
        opts.search = opts.search or cfg.method
        opts.filter = opts.filter or cfg.filter
    else
        opts.search = nil
        opts.filter = nil
    end

    -- select base selector
    local selector = S
    if opts.search then
        selector = require('fltui.select.search')
    end

    -- apply selector overrides by kind
    if opts.kind then
        local kmt = load_kindmt(opts.kind)
        if kmt then
            selector = M.extend(selector, kmt)
        end
    end

    -- init and show
    local sel = selector:new(items, opts, on_choice, actions)
    sel:show(true)
end

---Overrides the specified selector class with overrides one.
---Returns a new class-object.
---@generic T
---@param selector fltui.select Selector to override.
---@param override `T` Override-class for selector.
---@return T
function M.extend(selector, override)
    local mtp = {}
    for k, v in pairs(override) do
        mtp[k] = v
    end
    mtp.__index = mtp
    mtp.super = selector
    return setmetatable(mtp, selector)
end

---Base class for selection window
M.Select = S

return M
