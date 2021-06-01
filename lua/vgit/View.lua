local buffer = require('vgit.buffer')
local State = require('vgit.State')

local vim = vim

local View = {}
View.__index = View

local function highlight_with_ts(buf, ft)
    local has_ts = false
    local ts_highlight = nil
    local ts_parsers = nil
    if not has_ts then
        has_ts, _ = pcall(require, 'nvim-treesitter')
        if has_ts then
            _, ts_highlight = pcall(require, 'nvim-treesitter.highlight')
            _, ts_parsers = pcall(require, 'nvim-treesitter.parsers')
        end
    end
    if has_ts and ft and ft ~= '' then
        local lang = ts_parsers.ft_to_lang(ft);
        if ts_parsers.has_parser(lang) then
            ts_highlight.attach(buf, lang)
            return true
        end
    end
    return false
end

local function create_border_lines(title, content_win_options, border)
    local border_lines = {}
    local topline = nil
    if content_win_options.row > 0 then
        if title ~= '' then
            title = string.format(" %s ", title)
        end
        local title_len = string.len(title)
        local midpoint = math.floor(content_win_options.width / 2)
        local left_start = midpoint - math.floor(title_len / 2)
        topline = string.format(
            "%s%s%s%s%s",
            border[1],
            string.rep(border[2], left_start),
            title,
            string.rep(border[2], content_win_options.width - title_len - left_start),
            border[3]
        )
    end
    if topline then
        table.insert(border_lines, topline)
    end
    local middle_line = string.format(
        "%s%s%s",
        border[4] or '',
        string.rep(' ', content_win_options.width),
        border[8] or ''
    )
    for _ = 1, content_win_options.height do
        table.insert(border_lines, middle_line)
    end
    table.insert(border_lines, string.format(
        "%s%s%s",
        border[7] or '',
        string.rep(border[6], content_win_options.width),
        border[5] or ''
    ))
    return border_lines
end

local function create_border(content_buf, title, window_props, border, border_hl)
    local thickness = { top = 1, right = 1, bot = 1, left = 1 }
    local buf = vim.api.nvim_create_buf(true, true)
    buffer.set_lines(buf, create_border_lines(title, window_props, border))
    buffer.assign_options(buf, {
        ['modifiable'] = false,
        ['bufhidden'] = 'wipe',
        ['buflisted'] = false,
    })
    local win_id = vim.api.nvim_open_win(buf, false, {
        relative = 'editor',
        style = 'minimal',
        focusable = false,
        row = window_props.row - thickness.top,
        col = window_props.col - thickness.left,
        width = window_props.width + thickness.left + thickness.right,
        height = window_props.height + thickness.top + thickness.bot,
    })
    vim.api.nvim_win_set_option(win_id, 'cursorbind', false)
    vim.api.nvim_win_set_option(win_id, 'scrollbind', false)
    vim.api.nvim_win_set_option(win_id, 'winhl', string.format('Normal:%s', border_hl))
    buffer.add_autocmd(
        content_buf,
        'WinClosed',
        string.format('_run_submodule_command("ui", "close_windows", { %s })', win_id)
    )
    return buf, win_id
end

local function state_getter(state)
    return function(key)
        return state:get(key)
    end
end

local function global_width()
    return vim.o.columns
end

local function global_height()
    return vim.o.lines
end

local function new(options)
    assert(options == nil or type(options) == 'table', 'Invalid options provided for View')
    options = options or {}
    local height = 10
    local width = 70
    local config = State.new({
        filetype = '',
        title = '',
        border = { '╭', '─', '╮', '│', '╯', '─', '╰', '│' },
        border_hl = 'FloatBorder',
        buf_options = {
            ['modifiable'] = false,
            ['buflisted'] = false,
            ['bufhidden'] = 'wipe',
        },
        win_options = {
            ['wrap'] = false,
            ['winhl'] = 'Normal:',
            ['cursorline'] = false,
            ['cursorbind'] = false,
            ['scrollbind'] = false,
            ['signcolumn'] = 'auto',
        },
        window_props = {
            style = 'minimal',
            relative = 'editor',
            height = height,
            width = width,
            row = math.ceil((global_height() - height) / 2 - 1),
            col = math.ceil((global_width() - width) / 2),
        },
    })
    config:assign(options)
    return setmetatable({
        internals = {
            buf = nil,
            win_id = nil,
            border = {
                buf = nil,
                win_id = nil,
            },
            loading = false,
            rendered = false,
            lines = options.lines,
        },
        config = config
    }, View)
end

function View:get_win_id()
    return self.internals.win_id
end

function View:get_buf()
    return self.internals.buf
end

function View:get_border_buf()
    return self.internals.border.buf
end

function View:get_border_win_id()
    return self.internals.border.win_id
end

function View:set_buf_option(option)
    return vim.api.nvim_buf_set_option(self.internals.buf, option)
end

function View:set_win_option(option)
    return vim.api.nvim_win_set_option(self.internals.win_id, option)
end

function View:get_buf_option(key)
    return vim.api.nvim_buf_get_option(self.internals.buf, key)
end

function View:get_win_option(key)
    return vim.api.nvim_win_get_option(self.internals.win_id, key)
end

function View:set_loading(value)
    assert(type(value) == 'boolean', 'Invalid type')
    if value == self.internals.loading then
        return
    end
    if value then
        self.internals.loading = value
        self.internals.cache = buffer.get_lines(self.internals.buf)
        local loading_lines = {}
        local height = vim.api.nvim_win_get_height(self.internals.win_id)
        local width = vim.api.nvim_win_get_width(self.internals.win_id)
        for _ = 1, height do
            table.insert(loading_lines, '')
        end
        local loading_text = 'Loading...'
        local rep = math.ceil((width / 2) - #loading_text + 2)
        if rep < 0 then
            rep = 0
        end
        loading_lines[math.floor(height / 2)] = string.rep(' ',  rep) .. loading_text
        buffer.set_lines(self.internals.buf, loading_lines)
    else
        self.internals.loading = value
        buffer.set_lines(self.internals.buf, self.internals.cache)
        self.internals.cache = nil
    end
end

function View:add_autocmd(cmd, action, options)
    local buf = self:get_buf()
    local persist = (options and options.persist) or false
    local override = (options and options.override) or false
    local nested = (options and options.nested) or false
    vim.cmd(
        string.format(
            'au%s %s <buffer=%s> %s %s :lua require("vgit").%s',
            override and '!' or '',
            cmd,
            buf,
            nested and '++nested' or '',
            persist and '' or '++once',
            action
        )
    )
end

function View:add_keymap(key, action)
    buffer.add_keymap(self:get_buf(), key, action)
end

function View:render()
    if self.internals.rendered then
        return
    end
    local get_state = state_getter(self.config)
    local buf = vim.api.nvim_create_buf(true, true)
    local filetype, buf_options = get_state('filetype'), get_state('buf_options')
    local title, border, border_hl = get_state('title'), get_state('border'), get_state('border_hl')
    local window_props, win_options = get_state('window_props'), get_state('win_options')
    buffer.set_lines(buf, self.internals.lines)
    if filetype ~= '' then
        highlight_with_ts(buf, filetype)
    end
    buffer.assign_options(buf, buf_options)
    if title == '' then
        if border_hl then
            local new_border = {}
            for _, value in pairs(border) do
                if type(value) == 'table' then
                    value[2] = border_hl
                    table.insert(new_border, value)
                else
                    table.insert(new_border, { value, border_hl })
                end
            end
            window_props.border = new_border
        else
            window_props.border = border
        end
    end
    local win_id = vim.api.nvim_open_win(buf, true, window_props)
    for key, value in pairs(win_options) do
        vim.api.nvim_win_set_option(win_id, key, value)
    end
    self.internals.buf = buf
    self.internals.win_id = win_id
    if border and title ~= '' then
        local border_buf, border_win_id = create_border(buf, title, window_props, border, border_hl)
        self.internals.border.buf = border_buf
        self.internals.border.win_id = border_win_id
    end
    self:add_autocmd('BufWinLeave', string.format('_run_submodule_command("ui", "close_windows", { %s })', win_id))
    self.internals.rendered = true
end

return {
    new = new,
    global_height = global_height,
    global_width = global_width,
    __object = View,
}