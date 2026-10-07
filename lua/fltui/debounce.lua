local M = {}

local heap = require('fltui.heap')

---@class fltui.debounce.item
---@field cb function
---@field args any[]
---@field ts number
local TI = {}
TI.__index = TI
function TI:__eq(tbl)
    if self.cb == tbl.cb and #self.args == #tbl.args then
        for i = 1, #self.args do
            if self.args[i] ~= tbl.args[i] then
                return false
            end
        end
        return true
    else
        return false
    end
end
function TI:__tostring()
    return tostring(self.cb)
        .. ' args: ['
        .. table.concat(self.args, ', ')
        .. ']'
end

---@type fltui.debounce.item[]
local items = {}
---@type number[]
local timeouts = {}
local timer = assert(vim.uv.new_timer(), '[debounce] could not create timer')

local function timerfn()
    local it, tm = heap.pop(items, timeouts)
    ---@cast it -?
    local usedcb = { it }
    it.cb(unpack(it.args))
    -- update times
    for i = 1, #timeouts do
        timeouts[i] = timeouts[i] - tm
    end
    -- callback
    while #timeouts > 0 and timeouts[1] <= 0 do
        it = heap.pop(items, timeouts)
        ---@cast it -?
        if not vim.list_contains(usedcb, it) then
            it.cb(unpack(it.args))
            usedcb[#usedcb + 1] = it
        end
    end
    if timeouts[1] then
        timer:start(timeouts[1], 0, timerfn)
    end
end

---Debounces callback until the specified time has passed.
---
---If the same callback with same arguments is passed then the function
---will be called the first time only.
---
---NOTE: return value(s) are lost.
---@param time number Debounce timeout
---@param callback function Callback
---@param ... any Callback arguments
function M.debounce_fn(time, callback, ...)
    local it = setmetatable(
        { cb = callback, args = { ... }, ts = vim.uv.hrtime() },
        TI
    )
    if items[1] and items[1] == it and timeouts[1] == time then
        return
    end
    if timer:is_active() then
        -- update existing times
        local delta = timeouts[1] - timer:get_due_in()
        timer:stop()
        for i = 1, #timeouts do
            timeouts[i] = timeouts[i] - delta
        end
    end
    if items[1] and items[1] == it then
        heap.replace(items, it, timeouts, time)
    else
        heap.push(items, it, timeouts, time)
    end
    timer:start(timeouts[1], 0, timerfn)
end

---Debounces specified function until SafeState.
---
---Callback can return false to wait until next safe state.
---@param callback function function to be called in SafeState
---@param state string? string to check `state()`
function M.to_safestate(callback, state)
    vim.api.nvim_create_autocmd('SafeState', {
        nested = true,
        callback = function()
            if not state or vim.fn.state(state) == '' then
                local ret = callback()
                return ret == nil and true or ret
            end
        end,
    })
end

return M
