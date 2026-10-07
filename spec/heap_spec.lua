---@module 'luassert'

describe('basic', function()
    local mod = require('fltui.heap')

    it('test', function()
        ---@type fltui.simple_heap<integer>
        local heap = mod.new(function(a, b)
            return a < b
        end)

        local min = math.huge

        -- add 10 random numbers
        local ogvalues = {}
        local total = 10
        for _ = 1, total do
            local n = math.random(1, 50)
            min = math.min(n, min)
            heap:push(n)
            table.insert(ogvalues, n)
        end
        assert.equal(total, #heap)
        assert.equal(min, heap[1])
        assert.equal(min, heap:front())

        local values = {}
        for _ = 1, total do
            values[#values + 1] = heap:front()
            assert.equal(values[#values], heap:pop())
        end

        table.sort(ogvalues)
        assert.same(ogvalues, values)
    end)
end)

describe('int_heap', function()
    local heap = require('fltui.heap')
    ---@type fltui.simple_heap<integer>
    local h
    before_each(function()
        h = heap.new()
        local n = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 }
        while #n > 0 do
            local p = math.random(#n)
            h:push(table.remove(n, p))
        end
    end)

    after_each(function()
        ---@diagnostic disable-next-line: cast-local-type
        h = nil
    end)

    it('push', function()
        for i, v in ipairs(h) do
            local cl = i * 2
            local cr = cl + 1
            if h[cl] then
                assert.is_true(v >= h[cl])
            end
            if h[cr] then
                assert.is_true(v >= h[cr])
            end
        end
    end)

    it('pop', function()
        local after = {}
        while #h > 0 do
            after[#after + 1] = h:pop()
        end

        assert.same({ 10, 9, 8, 7, 6, 5, 4, 3, 2, 1 }, after)
    end)

    it('replace', function() end)

    it('reheap', function() end)
end)
