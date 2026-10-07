local scrb = require('fltui.scrb')

local function calc_thumb(topline, viewport, total)
    local barh = math.max(1, math.floor((viewport ^ 2) / total))
    if barh >= total then
        return nil
    end

    -- bar top
    local bart = math.ceil((topline - 1) * viewport / total)
    bart = math.min(bart, viewport - barh)
    -- bar bottom
    local barb = math.min(bart + barh, viewport)

    return bart, barb
end

-- test calc_thumb
for topline = 1, 10 do
    -- window height = 10, total = 11 -> true
    assert(calc_thumb(topline, 10, 11), 'calc_thumb t1 bad on topline')
    -- window height = 10, total = 10 -> false
    assert(not calc_thumb(topline, 10, 10), 'calc_thumb t1 bad on topline')
end
assert(calc_thumb(1, 1, 10), 'calc_thumb t1 bad on topline')
assert(calc_thumb(1, 1, 10), 'calc_thumb t1 bad on topline')
assert(not calc_thumb(1, 1, 0), 'calc_thumb t1 bad on topline')
assert(not calc_thumb(1, 1, 1), 'calc_thumb t1 bad on topline')
assert(calc_thumb(1, 1, 2), 'calc_thumb t1 bad on topline')

-- automatic one
-- local b = vim.api.nvim_create_buf(false, true)
-- vim.api.nvim_set_option_value('bh', 'wipe', { buf = b })
--
-- -- add 100 lines
-- local lines = {}
-- for i = 1, 100 do
--     lines[i] = 'hola' .. tostring(i)
-- end
--
-- vim.api.nvim_buf_set_lines(b, 0, -1, true, lines)
--
-- local w1 = vim.api.nvim_open_win(b, false, {
--     width = 20,
--     height = 15,
--     relative = 'editor',
--     border = 'single',
--     row = 10,
--     col = 50,
-- })
--
-- scrb.add_vertical_scrollbar(w1)
