if vim.g.loaded_fltui then
    return
end

vim.g.loaded_fltui = true

vim.api.nvim_create_autocmd('VimEnter', {
    once = true,
    nested = true,
    callback = function()
        if vim.g.fltui_replace_input == 1 then
            vim.ui.input = require('fltui').input
        end

        if vim.g.fltui_replace_select == 1 then
            vim.ui.select = require('fltui').select
        end
    end,
})
