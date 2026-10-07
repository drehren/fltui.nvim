---@type fun(n:number, s:integer):number
local brshift = require('bit').rshift

local M = {}

local function _cmp_min(a, b)
    return a < b
end

local function _cmp_max(a, b)
    return a > b
end

local function heap_push(heap, item, values, value, lastidx, cmp)
    cmp = cmp or _cmp_min
    lastidx = lastidx or #heap
    local idx = lastidx + 1
    heap[idx] = item
    values[idx] = value
    if idx == 1 then
        return
    end
    local pidx = brshift(idx, 1)
    while pidx > 0 and cmp(values[pidx], values[idx]) do
        heap[pidx], heap[idx] = heap[idx], heap[pidx]
        values[pidx], values[idx] = values[idx], values[pidx]
        idx = pidx
        pidx = brshift(idx, 1)
    end
end

local function heap_replace(heap, item, values, value, i, cmp)
    cmp = cmp or _cmp_min
    i = i or 0
    assert(#heap - i > 0, 'list is empty')
    local it = heap[i + 1]
    local va = values[i + 1]
    heap[i + 1] = item
    values[i + 1] = value
    local idx = 1
    while heap[i + idx] do
        local lidx = idx * 2 + i
        local ridx = idx * 2 + 1 + i
        local cidx
        if heap[ridx] and heap[lidx] then
            if not cmp(values[ridx], values[lidx]) then
                cidx = ridx
            else
                cidx = lidx
            end
        else
            if heap[lidx] then
                cidx = lidx
            else
                break
            end
        end
        local qidx = i + idx
        if cmp(values[qidx], values[cidx]) then
            heap[qidx], heap[cidx] = heap[cidx], heap[qidx]
            values[qidx], values[cidx] = values[cidx], values[qidx]
            idx = cidx - i
        else
            break
        end
    end
    return it, va
end

---@generic T
---@param heap T[]
---@param item `T`
---@param values number[]
---@param value number
---@param cmp? fun(a:integer, b:integer):boolean
function M.push(heap, item, values, value, cmp)
    heap_push(heap, item, values, value, #heap, cmp or _cmp_min)
end

---@generic T
---@param heap T[]
---@param item `T`
---@param values number[]
---@param value number
---@param cmp? fun(a:integer, b:integer):boolean
---@return T
---@return number
function M.replace(heap, item, values, value, cmp)
    return heap_replace(heap, item, values, value, 0, cmp or _cmp_min)
end

local trem = table.remove

---@generic T
---@param heap `T`[]
---@param values number[]
---@param cmp? fun(a:number, b:number):boolean
---@return T?
---@return number?
function M.pop(heap, values, cmp)
    if #heap == 0 then
        return
    end
    if #heap == 1 then
        return trem(heap), trem(values)
    end
    cmp = cmp or _cmp_min
    return heap_replace(heap, trem(heap), values, trem(values), 0, cmp)
end

---@generic T
---@param list `T`[]
---@param values number[]
---@param cmp? fun(a:integer, b:integer):boolean
function M.make_heap(list, values, cmp)
    cmp = cmp or _cmp_min
    for i = 1, #list do
        heap_push(list, list[i], values, values[i], i - 1, cmp)
    end
end

---@generic T
---@param list `T`[]
---@param values number[]
---@param cmp? fun(a:integer, b:integer):boolean
function M.sort(list, values, cmp)
    cmp = cmp or _cmp_min
    M.make_heap(list, values, cmp)
    for i = 2, #list do
        heap_replace(list, list[i], values, values[i], i - 1, cmp)
    end
end

---@class fltui.simple_heap<T> : { [integer]: T }
---@field private _cmp fun(lhs: T, rhs: T): boolean
local H = {}
H.__index = H

---Pushes a value into the heap
---@param value T Value to add
function H:push(value)
    local i = #self + 1
    self[i] = value
    if i == 1 then
        return
    end
    local nexti = brshift(i, 1)
    while nexti > 0 and not self._cmp(self[nexti], self[i]) do
        self[nexti], self[i] = self[i], self[nexti]
        i = nexti
        nexti = brshift(i, 1)
    end
end

---Pops the first value from the heap
---@return T? value The first value, nil if empty
function H:pop()
    if #self == 0 then
        return
    end
    if #self == 1 then
        return trem(self)
    end
    return self:replace(trem(self))
end

---Pops the first value and pushes the specified value
---The heap must have at least one value
---@param value T Value to add
---@return T value The first value
function H:replace(value)
    local i = 0
    local oldval = self[i + 1]
    self[i + 1] = value
    local idx = 1
    while self[i + idx] do
        local lidx = idx * 2 + i
        local ridx = idx * 2 + 1 + i
        local cidx
        if self[ridx] and self[lidx] then
            if self._cmp(self[ridx], self[lidx]) then
                cidx = ridx
            else
                cidx = lidx
            end
        else
            if self[lidx] then
                cidx = lidx
            else
                break
            end
        end
        local qidx = i + idx
        if not self._cmp(self[qidx], self[cidx]) then
            self[qidx], self[cidx] = self[cidx], self[qidx]
            idx = cidx - i
        else
            break
        end
    end
    return oldval
end

---Re-heaps the list
function H:reheap()
    for i = 2, #self do
        local pidx = brshift(i, 1)
        while pidx > 0 and not self._cmp(self[pidx], self[i]) do
            self[pidx], self[i] = self[i], self[pidx]
            i = pidx
            pidx = brshift(i, 1)
        end
    end
end

---First value according to comparer
---@return T?
function H:front()
    return self[1]
end

---Creates a new list-table with heap methods.
---
---If no comparer function is provided, it creates a max-heap
---@generic T
---@param cmp? fun(lhs: T, rhs: T): boolean
---@return fltui.simple_heap<T>
function M.new(cmp)
    return setmetatable({ _cmp = cmp or _cmp_max }, H)
end

return M
