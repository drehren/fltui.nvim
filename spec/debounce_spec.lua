local debounce = require('fltui.debounce')

local counter = 1
local function checkcall()
    print('called', counter)
    counter = counter + 1
end

local c2 = 0
local function checkcall2()
    print('call2', c2)
    c2 = c2 + 1
end

for _ = 1, 100 do
    debounce.debounce_fn(101, checkcall)
    debounce.debounce_fn(101, checkcall2)
    debounce.debounce_fn(101, checkcall)
    debounce.debounce_fn(101, checkcall2)
end

vim.defer_fn(function()
    assert(counter == 2, 'called more than once')
    assert(c2 == 1, 'called more than once')
    print('check good')
end, 111)
