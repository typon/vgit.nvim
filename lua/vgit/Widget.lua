local buffer = require('vgit.buffer')

local vim = vim

local Widget = {}
Widget.__index = Widget

local function global_width()
    return vim.o.columns
end

local function global_height()
    return vim.o.lines
end

local function new(views)
    assert(type(views) == 'table', 'Invalid options provided for Widget')
    return setmetatable({
        views = views,
        internals = { rendered = false }
    }, Widget)
end

function Widget:views()
    return self.views
end

function Widget:render()
    if self.internals.rendered then
        return
    end
    for _, v in pairs(self.views) do
        v:render()
    end
    local win_ids = {}
    for _, v in pairs(self.views) do
        table.insert(win_ids, v:get_win_id())
        table.insert(win_ids, v:get_border_win_id())
    end
    for _, v in pairs(self.views) do
        v:add_autocmd(
            'BufWinLeave', string.format('_run_submodule_command("ui", "close_windows", %s)', vim.inspect(win_ids))
        )
    end
    local bufs = vim.api.nvim_list_bufs()
    for _, buf in ipairs(bufs) do
        local is_buf_listed = vim.api.nvim_buf_get_option(buf, 'buflisted') == true
        local buf_name = vim.api.nvim_buf_get_name(buf)
        local buf_has_name = buf_name and buf_name ~= ''
        if is_buf_listed and buf_has_name and buffer.is_valid(buf) then
            buffer.add_autocmd(
                buf,
                'BufEnter',
                string.format('_run_submodule_command("ui", "close_windows", %s)', vim.inspect(win_ids))
            )
        end
    end
    self.internals.rendered = true
end

return {
    new = new,
    global_height = global_height,
    global_width = global_width,
    __object = Widget,
}