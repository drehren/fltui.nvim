---@module 'luassert'

describe('col_word on "hola\\ a\\ todos como les va?"', function()
    ---@module 'fltui.acmp'
    local acmp
    before_each(function()
        acmp = require('fltui.acmp')
    end)
    after_each(function()
        acmp = nil
    end)

    -- test column word
    --           0            1 1  1 2 2 2 2
    --           1            4 6  9 1 3 5 7
    local ln = [[hola\ a\ todos como les va?]]

    it('index 1', function()
        assert.same('h', ln:sub(acmp.col_word(ln, 1)))
    end)
    it('index 6', function()
        assert.same('hola\\ ', ln:sub(acmp.col_word(ln, 6)))
    end)
    it('index 5', function()
        assert.same('hola\\', ln:sub(acmp.col_word(ln, 5)))
    end)
    it('index 4', function()
        assert.same('hola', ln:sub(acmp.col_word(ln, 4)))
    end)
    it('index 16', function()
        assert.same('c', ln:sub(acmp.col_word(ln, 16)))
    end)
    it('index 18', function()
        assert.same('com', ln:sub(acmp.col_word(ln, 18)))
    end)
    it('index 26', function()
        assert.same('va', ln:sub(acmp.col_word(ln, 26)))
    end)
    it('index 26 wordpat %w+', function()
        assert.same('va', ln:sub(acmp.col_word(ln, 26, '%w+')))
    end)
    it('index 27 wordpat %w+', function()
        assert.same('', ln:sub(acmp.col_word(ln, 27, '%w+')))
    end)
    it('index 28', function()
        assert.same('', ln:sub(acmp.col_word(ln, 28)))
    end)
    it('index 15', function()
        assert.same('', ln:sub(acmp.col_word(ln, 15)))
    end)
    it('index 20', function()
        assert.same('', ln:sub(acmp.col_word(ln, 20)))
    end)
    it('index 24', function()
        assert.same('', ln:sub(acmp.col_word(ln, 24)))
    end)
end)

describe('col_word', function()
    ---@module 'fltui.acmp'
    local acmp
    before_each(function()
        acmp = require('fltui.acmp')
    end)
    after_each(function()
        acmp = nil
    end)

    it('"    " 2', function()
        assert.same(3, acmp.col_word('    ', 2))
    end)
    it('" hello" 2', function()
        assert.same(2, acmp.col_word(' hello', 2))
    end)
    it('" hello" 4', function()
        assert.same(2, acmp.col_word(' hello', 4))
    end)
    it('"\\ hello" 4', function()
        assert.same(1, acmp.col_word('\\ hello', 4))
    end)
    it('"hello %&^#\\ pat" 7', function()
        local s = 'hello %&^#\\ pat'
        assert.same('', s:sub(acmp.col_word(s, 7, '%w+')))
    end)
    it('"hello %&^#\\ pat" 12', function()
        local s = 'hello %&^#\\ pat'
        assert.same('', s:sub(acmp.col_word(s, 12, '%w+')))
    end)
    it('"hello %&^#\\ pat" 15', function()
        local s = 'hello %&^#\\ pat'
        assert.same('pat', s:sub(acmp.col_word(s, 15, '%w+')))
    end)
end)

describe('col_word on Ex-like expression', function()
    ---@module 'fltui.acmp'
    local acmp
    before_each(function()
        acmp = require('fltui.acmp')
    end)
    after_each(function()
        acmp = nil
    end)
    local ln = 'e usr/'
    it('index 1', function()
        assert.same('e', ln:sub(acmp.col_word(ln, 1)))
    end)
    it('index 5', function()
        assert.same('usr', ln:sub(acmp.col_word(ln, 5)))
    end)
    it('index 6', function()
        assert.same('usr/', ln:sub(acmp.col_word(ln, 6)))
    end)
    it('index 6 wordpat %w+', function()
        assert.same('', ln:sub(acmp.col_word(ln, 6, '%w+')))
    end)
end)

describe('find_word on "hola\\ a\\ todos como les va?"', function()
    ---@module 'fltui.acmp'
    local acmp
    before_each(function()
        acmp = require('fltui.acmp')
    end)
    after_each(function()
        acmp = nil
    end)

    -- test column word
    --           0            1 1  1 2 2 2 2
    --           1            4 6  9 1 3 5 7
    local ln = [[hola\ a\ todos como les va?]]

    it('index 1', function()
        assert.same('hola\\ a\\ todos', ln:sub(acmp.find_word(ln, 1)))
    end)
    it('index 6', function()
        assert.same('hola\\ a\\ todos', ln:sub(acmp.find_word(ln, 6)))
    end)
    it('index 5', function()
        assert.same('hola\\ a\\ todos', ln:sub(acmp.find_word(ln, 5)))
    end)
    it('index 4', function()
        assert.same('hola\\ a\\ todos', ln:sub(acmp.find_word(ln, 4)))
    end)
    it('index 16', function()
        assert.same('como', ln:sub(acmp.find_word(ln, 16)))
    end)
    it('index 18', function()
        assert.same('como', ln:sub(acmp.find_word(ln, 18)))
    end)
    it('index 26', function()
        assert.same('va?', ln:sub(acmp.find_word(ln, 26)))
    end)
    it('index 28', function()
        assert.same('', ln:sub(acmp.find_word(ln, 28)))
    end)
    it('index 15', function()
        assert.same('', ln:sub(acmp.find_word(ln, 15)))
    end)
    it('index 20', function()
        assert.same('', ln:sub(acmp.find_word(ln, 20)))
    end)
    it('index 24', function()
        assert.same('', ln:sub(acmp.find_word(ln, 24)))
    end)
end)

describe('find_word "hello world \\ special\\ ?"', function()
    ---@module 'fltui.acmp'
    local acmp
    before_each(function()
        acmp = require('fltui.acmp')
    end)
    after_each(function()
        acmp = nil
    end)
    local line = [[hello world \ special\ ?]]
    it('find 3', function()
        assert.same('hello', line:sub(acmp.find_word(line, 3)))
    end)
    it('find 6', function()
        assert.same('', line:sub(acmp.find_word(line, 6)))
    end)
    it('find 7', function()
        assert.same('world', line:sub(acmp.find_word(line, 7)))
    end)
    it('find 12', function()
        assert.same('', line:sub(acmp.find_word(line, 12)))
    end)
    it('find 13', function()
        assert.same('\\ special\\ ?', line:sub(acmp.find_word(line, 13)))
    end)
    it('find 14', function()
        assert.same('\\ special\\ ?', line:sub(acmp.find_word(line, 14)))
    end)
end)

describe('find_word', function()
    ---@module 'fltui.acmp'
    local acmp
    before_each(function()
        acmp = require('fltui.acmp')
    end)
    after_each(function()
        acmp = nil
    end)

    it('"\\ hello" 2', function()
        assert.same(1, acmp.find_word('\\ hello', 2))
    end)
    it('"\\ hello" 3 %s 2', function()
        assert.same(3, acmp.find_word('\\ hello', 3, '%s', 2))
    end)
    it('"aaa bbb ccc ddd eee" -1', function()
        local str = 'aaa bbb ccc ddd eee'
        assert.same('eee', str:sub(acmp.find_word(str, -1)))
    end)
end)
