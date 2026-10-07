-- Lua fuzzy match using fzf_lib

local M = {}

local mabs = math.abs
local heap_sort = require('fltui.heap').sort

local ok, fzf = pcall(require, 'fzf_lib')
if not ok then
    vim.api.nvim_echo({
        {
            '[fltui] "fuzzy" search unavailable: "fzf_lib" missing',
            'WarningMsg',
        },
    }, true, {})
    return {
        match = function(items)
            local indexes = {}
            for i = 1, #items do
                indexes[i] = i
            end
            return indexes, {}
        end,
        match3 = function(list, _, _, result)
            result = result or {}
            for i = 1, #list do
                result[i] = { i, #list - i + 1, nil }
            end
            return result, 0
        end,
    }
end
local fzf_defaults = {
    case = 0,
    fuzzy = true,
    hl_char = vim.api.nvim_get_hl_id_by_name('CurSearch'),
}

---@class fltui.fuzzy.opts
---@field case? integer fzf_lua case option: 1 for case sensitive match
---@field fuzzy? boolean fzf_lua fuzzy: `true` to use fuzzy match
---`match`: use specified highlight name or id hl table.
---@field hl_char? string|integer

---Result object - 3-tuple of item index, item score, char positions
---@alias fltui.fuzzy.result3 [integer, integer, integer[]]

---@param list string[]
---@param pattern string
---@param opts fltui.fuzzy.opts Options. hl_char is not used here
---@param result? fltui.fuzzy.result3[]
function M.match3(list, pattern, opts, result)
    result = result or {}
    vim.validate('result', result, 'table')

    local slab = fzf.allocate_slab()
    local pat = fzf.parse_pattern(pattern, opts.case, opts.fuzzy)

    for i = #result, #list do
        result[i] = { i, #list - i + 1, nil }
    end

    local noscore = 0
    for i, item in ipairs(list) do
        local score = fzf.get_score(item, pat, slab)
        result[i][1] = i
        result[i][2] = result[i][2] + score
        if score > 0 then
            result[i][3] = fzf.get_pos(item, pat, slab)
            if result[i][3] then
                table.sort(result[i][3])
            end
        else
            noscore = noscore + 1
        end
    end

    for i = #list + 1, #result do
        result[i] = nil
    end

    fzf.free_pattern(pat)
    fzf.free_slab(slab)

    return result, noscore
end

---Fuzzy matches items with the given pattern
---@param items string[] The items to match
---@param pattern string The pattern to match against
---@param opts? fltui.fuzzy.opts Match options.
---@return integer[] indexes The new indexes sorted by score for items
---@return table[] hl_chars Highlight table. 3-tuple (start, end, hl_char) list
function M.match(items, pattern, opts)
    opts = opts or {}
    opts = vim.tbl_extend('force', fzf_defaults, opts)

    local slab = fzf.allocate_slab()
    local pat = fzf.parse_pattern(pattern, 0, true)

    local scores = {}
    local indexes = {}
    local chars = {}
    for i, item in ipairs(items) do
        local score = fzf.get_score(item, pat, slab)
        if score > 0 then
            scores[#scores + 1] = score + #items - i
            indexes[#indexes + 1] = i
        end
    end

    heap_sort(indexes, scores)

    for i, idx in ipairs(indexes) do
        chars[i] = fzf.get_pos(items[idx], pat, slab) or {}
    end

    fzf.free_pattern(pat)
    fzf.free_slab(slab)

    -- process positions
    for i = 1, #chars do
        local pos = chars[i][1]
        if pos then
            chars[i][1] = { pos, pos, opts.hl_char }
            local k = 1
            for j = 2, #chars[i] do
                local diff = chars[i][j] - pos
                pos = chars[i][j]
                if mabs(diff) == 1 then
                    if diff < 0 then
                        chars[i][k][1] = pos
                    else
                        chars[i][k][2] = pos
                    end
                else
                    k = k + 1
                    chars[i][k] = { pos, pos, opts.hl_char }
                end
            end
            for j = k + 1, #chars[i] do
                chars[i][j] = nil
            end
        end
    end

    return indexes, chars
end

return M
