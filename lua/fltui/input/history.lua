local statefile = vim.fs.joinpath(vim.fn.stdpath('state'), 'fltui', 'inputhist')

local M = {}

---@class fltui.input._hist_db
local HDB = {}
HDB.__index = HDB
function HDB:new()
    return setmetatable({}, self)
end
function HDB:nr()
    return #self
end
function HDB:get(index)
    return self[index]
end
function HDB:add(item)
    -- find existing item to push
    for i = 1, #self do
        if self[i] == item then
            table.remove(self, i)
            break
        end
    end
    table.insert(self, item)
end
function HDB:del(index)
    table.remove(self, index)
end

---@type table<string, fltui.input._hist_db>
local histdb
local function read_histdb()
    if not vim.uv.fs_stat(vim.fs.dirname(statefile)) then
        vim.uv.fs_mkdir(vim.fs.dirname(statefile), 493)
    end
    local f = io.open(statefile, 'rb')
    if f then
        local blob = f:read('*a')
        histdb = vim.mpack.decode(blob)
        for _, v in pairs(histdb) do
            v = setmetatable(v, HDB)
        end
        f:close()
    else
        histdb = {}
    end
    histdb.editor = {
        nr = function()
            return vim.fn.histnr('@')
        end,
        add = function(_, item)
            vim.fn.histadd('@', item)
        end,
        get = function(_, index)
            return vim.fn.histget('@', index)
        end,
        del = function(_, index)
            vim.fn.histdel('@', index)
        end,
    }
    setmetatable(histdb, {
        __index = function(tbl, key)
            rawset(tbl, key, HDB:new())
            return tbl[key]
        end,
    })
end

vim.api.nvim_create_autocmd('VimLeave', {
    group = vim.api.nvim_create_augroup(
        'fltui.input.history',
        { clear = true }
    ),
    callback = function()
        if vim.v.dying == 0 then
            setmetatable(histdb, nil)
            histdb.editor = nil
            for _, v in pairs(histdb) do
                setmetatable(v, nil)
            end
            local f = io.open(statefile, 'wb')
            if f then
                f:write(vim.mpack.encode(histdb))
                f:close()
            end
        end
    end,
})

---@class fltui.input.history_state
---@field nr integer
---@field private _db fltui.input._hist_db
local H = {}
H.__index = H
---@param scope fltui.input.scope
function H:new(scope)
    if not histdb then
        read_histdb()
    end
    local db = histdb[scope]

    ---@type fltui.input.history_state
    local s = { _db = db, nr = db:nr() + 1 }
    return setmetatable(s, H)
end

---@param prefix string?
function H:next(prefix)
    local hadprefix = not not prefix
    prefix = prefix or ''
    for i = self.nr + 1, self._db:nr() do
        local text = self._db:get(i)
        if vim.startswith(text, prefix) then
            self.nr = i
            return text
        end
    end
    if hadprefix then
        return nil
    end
    self.nr = self._db:nr() + 1
    return ''
end

---@param prefix string?
function H:prev(prefix)
    local hadprefix = not not prefix
    prefix = prefix or ''
    for i = self.nr - 1, 1, -1 do
        local text = self._db:get(i)
        if vim.startswith(text, prefix) then
            self.nr = i
            return text
        end
    end
    if hadprefix then
        return nil
    end
    self.nr = 1
    return self._db:get(1)
end

---@param item string
function H:add(item)
    self._db:add(item)
end

---@enum (key) fltui.input.scope
M.hist_scope = {
    cursor = 'c',
    line = 'l',
    buffer = 'b',
    window = 'w',
    tabpage = 't',
    editor = '@',
    project = 'p',
}

---@param scope fltui.input.scope
---@return fltui.input.history_state
function M.new_state(scope)
    return H:new(scope)
end

---@param state fltui.input.history_state
---@param pos number
---@param prefix string?
function M.get(state, pos, prefix)
    if pos > 0 then
        return state:next(prefix)
    else
        return state:prev(prefix)
    end
end

return M
