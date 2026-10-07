local M = {}

local function cb(move, callback, win)
    return function()
        move()
        callback(vim.api.nvim_win_get_cursor(win)[1])
    end
end

local buf_set_keymap = vim.api.nvim_buf_set_keymap

function M.proxy_motions(buf, towin, on_change)
    local move = require('fltui.util.movement').proxy_to(towin)

    local line_down = {
        nowait = true,
        callback = cb(move.line_down, on_change, towin),
    }
    for lhs in ('j+'):gmatch('.') do
        buf_set_keymap(buf, 'n', lhs, '', line_down)
        buf_set_keymap(buf, 'v', lhs, '', line_down)
    end
    for lhs in ('<Down><C-n>'):gmatch('%b<>') do
        buf_set_keymap(buf, 'n', lhs, '', line_down)
        buf_set_keymap(buf, 'v', lhs, '', line_down)
        buf_set_keymap(buf, 'i', lhs, '', line_down)
    end

    local line_up = {
        nowait = true,
        callback = cb(move.line_up, on_change, towin),
    }
    for lhs in ('k-'):gmatch('.') do
        buf_set_keymap(buf, 'n', lhs, '', line_up)
        buf_set_keymap(buf, 'v', lhs, '', line_up)
    end
    for lhs in ('<Up><C-p>'):gmatch('%b<>') do
        buf_set_keymap(buf, 'n', lhs, '', line_up)
        buf_set_keymap(buf, 'v', lhs, '', line_up)
        buf_set_keymap(buf, 'i', lhs, '', line_up)
    end
end

return M
