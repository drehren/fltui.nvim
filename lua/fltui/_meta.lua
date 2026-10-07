---@meta

---@class fltui.config.select_search
---@field method? 'match'|'fuzzy'
---@field filter? boolean

---@type 1|0
vim.g.fltui_replace_input = vim.g.fltui_replace_input or 0

---@type 1|0
vim.g.fltui_replace_select = vim.g.fltui_replace_select or 0

---@type fltui.config.select_search?
vim.g.fltui_select_search = vim.g.fltui_select_search or nil
