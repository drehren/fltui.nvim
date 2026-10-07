local mceil = math.ceil
local mlog10 = math.log10
local mmax = math.max

local getbufinfo = vim.fn.getbufinfo

local get_hl_id_by_name = vim.api.nvim_get_hl_id_by_name

local buf_set_extmark = vim.api.nvim_buf_set_extmark

vim.api.nvim_set_hl(0, 'FltUIBufName', { fg = 'fg' })

local wintypename = {
    loclist = '[Location List]',
    quickfix = '[Quickfix List]',
}
local buftypename = {
    quickfix = true,
    terminal = '[Terminal]',
    nofile = '[Scratch]',
    prompt = '[Prompt]',
    help = '[Help]',
}

local hlids = {
    Comment = get_hl_id_by_name('Comment'),
    FltUIBufName = get_hl_id_by_name('FltUIBufName'),
    SpecialKey = get_hl_id_by_name('SpecialKey'),
}

---@param binfo vim.fn.getbufinfo.ret.item
---@param data table
local function bufname(binfo, data)
    local _opts = { buf = binfo.bufnr }
    local bopt = function(opt)
        return vim.api.nvim_get_option_value(opt, _opts)
    end
    local name = binfo.name
    if name ~= '' then
        for _, patrepl in ipairs(data.relpaths) do
            if vim.startswith(name, patrepl[1]) then
                name = patrepl[2] .. name:sub(#patrepl[1] + 1)
            end
        end
        return name
    else
        local bt = bopt('bt')
        if bt == 'quickfix' then
            local wt = vim.fn.win_gettype(binfo.windows[1])
            local qfwname = wintypename[wt]
            if not qfwname then
                local msg =
                    '[fltui.buffer_kind] unknown window type "%s" for qf'
                vim.notify(msg:format(wt), vim.log.levels.ERROR)
                qfwname = wintypename.quickfix
            end
            return qfwname
        elseif bt ~= '' then
            return buftypename[bt]
        end
    end
    return '[No Name]'
end

---@param binfo vim.fn.getbufinfo.ret.item
---@param data table
local function bufflags(binfo, data)
    local _opts = { buf = binfo.bufnr }
    local bopt = function(opt)
        return vim.api.nvim_get_option_value(opt, _opts)
    end
    local roterm
    if bopt('bt') == 'terminal' then
        local chan = bopt('channel')
        local code = vim.fn.jobwait({ chan }, 0)[1]
        roterm = code == -1 and 'R' or chan ~= 0 and 'F' or '?'
    else
        roterm = not bopt('ma') and '-' or bopt('ro') and '=' or ' '
    end
    return table.concat({
        not bopt('buflisted') and 'u' or ' ',
        (data.curbuf == binfo.bufnr and '%')
            or (data.altbuf == binfo.bufnr and '#')
            or ' ',
        binfo.hidden == 1 and 'h' or binfo.loaded == 1 and 'a' or ' ',
        roterm,
        binfo.changed == 1 and '+' or ' ',
    })
end

---@class fltui.select.kind.buffer : fltui.select
---@field amt integer
---@field curbuf integer
---@field altbuf integer
---@field linefmt string
---@field relpaths ([string, string])[]
local M = {}
M.__index = M

---@param self fltui.select.kind.buffer
local function linehl(self, linenr, line)
    local ext = {}

    if #line < self.amt then
        vim.print(linenr, line, vim.api.nvim_buf_line_count(self.buf))
    end
    -- flags
    ext.end_col = self.amt + 6
    ext.hl_group = hlids.Comment
    buf_set_extmark(self.buf, self.ns, linenr - 1, self.amt, ext)

    -- text
    ext.end_col = vim.fn.strridx(line, ':')
    ext.hl_group = hlids.FltUIBufName
    buf_set_extmark(self.buf, self.ns, linenr - 1, self.amt + 6, ext)

    -- buffer lnum
    local col = ext.end_col
    ext.end_col = #line
    ext.hl_group = hlids.SpecialKey
    buf_set_extmark(self.buf, self.ns, linenr - 1, col, ext)
end

function M:item_highlight(linenr, line)
    linehl(self, linenr, line)
    self.super.item_highlight(self, linenr, line)
end

function M:cursorline_highlight(linenr, line)
    linehl(self, linenr, line)
    self.super.cursorline_highlight(self, linenr, line)
end

function M:format_item(item)
    local binfo = getbufinfo(item)[1]
    local bflag = bufflags(binfo, self)
    local bname = bufname(binfo, self)
    return self.linefmt:format(item, bflag, bname, binfo.lnum)
end

function M:new(items, opts, on_choice, actions)
    local sel = self.super:new(items, opts, on_choice, actions) --[[@as fltui.select.kind.buffer]]

    local nuw = vim.api.nvim_get_option_value('nuw', {})
    sel.amt = mmax(nuw - 1, mceil(mlog10(mmax(unpack(sel.items)))) + 1)
    sel.linefmt = ('%%%dd %%s %%s:%%d'):format(sel.amt)
    sel.curbuf = sel.curbuf or vim.api.nvim_get_current_buf()
    sel.altbuf = sel.altbuf or vim.fn.bufnr('#')
    sel.relpaths = {
        { vim.uv.cwd() .. '/', '' },
        { vim.uv.os_homedir(), '~' },
    }
    local realpath = vim.uv.fs_realpath(assert(vim.uv.os_homedir()))
    if type(realpath) == 'string' then
        table.insert(sel.relpaths, { realpath, '~' })
    end

    return setmetatable(sel, self)
end

return M
