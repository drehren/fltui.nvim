---@class fltui.select.kind.tags : fltui.select
---@field linefmt string
local M = {}

---@class fltui.select.kind.tags.item
---@field bufnr integer
---@field from [integer, integer, integer, integer]
---@field matchnr integer
---@field tagname string

---@param item fltui.select.kind.tags.item
function M:format_item(item)
    local txt
    if vim.api.nvim_get_current_buf() == item.bufnr then
        txt = vim.api.nvim_buf_get_lines(
            item.bufnr,
            item.from[2] - 1,
            item.from[2],
            true
        )[1]
    else
        txt = vim.fs.basename(vim.api.nvim_buf_get_name(item.bufnr))
    end
    local line = self.linefmt:format(item._nr, item.tagname, item.from[2], txt)
    return line, 1, #line
end

local mceil = math.ceil
local mlog10 = math.log10

local function mcl10(v)
    return mceil(mlog10(v))
end

---@param items fltui.select.kind.tags.item[]
function M:new(items, opts, on_choice, actions)
    local sel = self.super:new(items, opts, on_choice, actions) --[[@as fltui.select.kind.tags]]

    local to = 1
    local tle = 1
    local ln = 1

    for n, i in ipairs(items) do
        i._nr = n
        to = math.max(to, i.matchnr)
        tle = math.max(tle, vim.fn.strwidth(i.tagname))
        ln = math.max(ln, i.from[2])
    end

    sel.linefmt = ('%%%dd %%-%ds %%%dd  %%s'):format(
        mcl10(#items),
        tle,
        mcl10(ln)
    )

    return setmetatable(sel, self)
end

return M
