local M = {}

M.namespace = vim.api.nvim_create_namespace("headlines")
M.augroup = vim.api.nvim_create_augroup("headlines", {})

local parse_query_save = function(language, query)
    -- vim.treesitter.query.parse_query() is deprecated, use vim.treesitter.query.parse() instead
    local ok, parsed_query =
        pcall(vim.treesitter.query.parse or vim.treesitter.query.parse_query, language, query)
    if not ok then
        return nil
    end
    return parsed_query
end

M.config = {
    markdown = {
        query = parse_query_save(
            "markdown",
            [[
                (atx_heading) @headline

                (thematic_break) @dash

                (fenced_code_block) @codeblock

                (list
                    (list_item) @listitem
                ) @list

                (block_quote_marker) @quote
                (block_quote (paragraph (inline (block_continuation) @quote)))
            ]]
        ),
        headline_highlights = { "Headline" },
        captures = {
            headline = {
                highlights = { "Headline" },
                min_width = 80,
                capture_name = 'headline',
                border_size = { 1, 1, 1, 1 },
                border = { "▃", "x", "▍", "x", "🬂", "x", "🮈", "x" },
                invert_border_hl = true,
                dynamic_border = true,
            },
            codeblock = {
                highlight = "CodeBlock",
                min_width = 80,
                capture_name = 'codeblock',
                dynamic_border = true,
            },
            list = {
                highlight = "CodeBlock",
                min_width = 80,
                capture_name = 'list',
                dynamic_border = true,
            },
        },
        dash_highlight = "Dash",
        dash_string = "-",
        quote_highlight = "Quote",
        quote_string = "┃",
    },
    rmd = {
        query = parse_query_save(
            "markdown",
            [[
                (atx_heading) @headline

                (thematic_break) @dash

                (fenced_code_block) @codeblock

                (block_quote_marker) @quote
                (block_quote (paragraph (inline (block_continuation) @quote)))
            ]]
        ),
        treesitter_language = "markdown",
        headline_highlights = { "Headline" },
        codeblock_highlight = "CodeBlock",
        dash_highlight = "Dash",
        dash_string = "-",
        quote_highlight = "Quote",
        quote_string = "┃",
        fat_headlines = true,
        fat_headline_upper_string = "▃",
        fat_headline_lower_string = "🬂",
    },
    norg = {
        query = parse_query_save(
            "norg",
            [[
                [
                    (heading1_prefix)
                    (heading2_prefix)
                    (heading3_prefix)
                    (heading4_prefix)
                    (heading5_prefix)
                    (heading6_prefix)
                ] @headline

                (weak_paragraph_delimiter) @dash
                (strong_paragraph_delimiter) @doubledash

                ((ranged_tag
                    name: (tag_name) @_name
                    (#eq? @_name "code")
                ) @codeblock (#offset! @codeblock 0 0 1 0))

                (quote1_prefix) @quote
            ]]
        ),
        headline_highlights = { "Headline" },
        codeblock_highlight = "CodeBlock",
        dash_highlight = "Dash",
        dash_string = "-",
        doubledash_highlight = "DoubleDash",
        doubledash_string = "=",
        quote_highlight = "Quote",
        quote_string = "┃",
        fat_headlines = true,
        fat_headline_upper_string = "▃",
        fat_headline_lower_string = "🬂",
    },
    org = {
        query = parse_query_save(
            "org",
            [[
                (headline (stars) @headline)

                (
                    (expr) @dash
                    (#match? @dash "^-----+$")
                )

                (block
                    name: (expr) @_name
                    (#match? @_name "(SRC|src)")
                ) @codeblock

                (paragraph . (expr) @quote
                    (#eq? @quote ">")
                )
            ]]
        ),
        headline_highlights = { "Headline" },
        codeblock_highlight = "CodeBlock",
        dash_highlight = "Dash",
        dash_string = "-",
        quote_highlight = "Quote",
        quote_string = "┃",
        fat_headlines = true,
        fat_headline_upper_string = "▃",
        fat_headline_lower_string = "🬂",
    },
}

M.make_reverse_highlight = function(name)
    local reverse_name = name .. "Reverse"

    if vim.fn.synIDattr(reverse_name, "fg") ~= "" then
        return reverse_name
    end

    local highlight = vim.fn.synIDtrans(vim.fn.hlID(name))
    local gui_bg = vim.fn.synIDattr(highlight, "bg", "gui")
    local cterm_bg = vim.fn.synIDattr(highlight, "bg", "cterm")

    if gui_bg == "" then
        gui_bg = "None"
    end
    if cterm_bg == "" then
        cterm_bg = "None"
    end

    vim.cmd(string.format("highlight %s guifg=%s ctermfg=%s", reverse_name, gui_bg or "None", cterm_bg or "None"))
    return reverse_name
end

M.setup = function(config)
    config = config or {}
    M.config = vim.tbl_deep_extend("force", M.config, config)

    -- tbl_deep_extend does not handle metatables
    for filetype, conf in pairs(config) do
        if conf.query then
            M.config[filetype].query = conf.query
        end
    end

    vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
        group = M.augroup,
        callback = function(ev)
            M.refresh(ev.buf)
        end
    })
    vim.api.nvim_set_decoration_provider(M.namespace, {
        on_buf = function(_, bufnr)
            M.refresh(bufnr)
        end
    })
end

local nvim_buf_set_extmark = function(...)
    pcall(vim.api.nvim_buf_set_extmark, ...)
end

M.refresh = function(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    local c = M.config[vim.bo.filetype]
    vim.api.nvim_buf_clear_namespace(bufnr, M.namespace, 0, -1)

    if not c or not c.query then
        return
    end

    local language = c.treesitter_language or vim.bo.filetype
    local language_tree = vim.treesitter.get_parser(bufnr, language)
    local syntax_tree = language_tree:parse()
    local root = syntax_tree[1]:root()
    local win_view = vim.fn.winsaveview()
    local left_offset = win_view.leftcol
    local width = vim.api.nvim_win_get_width(0)

    for _, match, metadata in c.query:iter_matches(root, bufnr) do
        for id, node in pairs(match) do
            local capture = c.query.captures[id]
            local start_row, start_column, end_row, _ =
                unpack(vim.tbl_extend("force", { node:range() }, (metadata[id] or {}).range or {}))

            --            if capture == "dash" and c.dash_highlight and c.dash_string then
            --                nvim_buf_set_extmark(bufnr, M.namespace, start_row, 0, {
            --                    virt_text = { { c.dash_string:rep(width), c.dash_highlight } },
            --                    virt_text_pos = "overlay",
            --                    hl_mode = "combine",
            --                })
            if capture == "doubledash" and c.doubledash_highlight and c.doubledash_string then
                nvim_buf_set_extmark(bufnr, M.namespace, start_row, 0, {
                    virt_text = { { c.doubledash_string:rep(width), c.doubledash_highlight } },
                    virt_text_pos = "overlay",
                    hl_mode = "combine",
                })
            else
                for _, opts in pairs(c.captures) do
                    if opts.capture_name == capture then
                        -- use single highlight or select relevant level
                        local hl_group =
                            (opts.get_block_hl and opts:get_block_hl(node))
                            or (type(opts.highlights) == 'table' and opts.highlights[1])
                            or opts.highlights
                        if type(hl_group) == 'string' and vim.fn.hlexists(hl_group) == 0 then
                            error('highlight group not found')
                        elseif type(hl_group) == 'table' then
                            local hlg_name, hlg_cfg = hl_group[1], hl_group[2]
                            if vim.fn.hlexists(hlg_name) == 0 then
                                vim.api.nvim_set_hl(0, hlg_name, hlg_cfg)
                            end
                            hl_group = hlg_name
                        end
                        if hl_group then
                            local trim_bot = opts.trim_bot_count and opts:trim_bot_count(node, bufnr) or 0
                            -- init border highlight group
                            local border_hl_group = opts.invert_border_hl and M.make_reverse_highlight(hl_group) or
                                hl_group
                            -- get lines
                            local lines = vim.api.nvim_buf_get_lines(bufnr, start_row, end_row, false)
                            -- get indent on first line
                            local _, l_padding = lines[1]:find "^ +"
                            l_padding = math.max((l_padding or 0) - left_offset, 0)
                            -- apply highlight to ext
                            nvim_buf_set_extmark(bufnr, M.namespace, start_row, l_padding, {
                                strict = false,
                                end_row = end_row-trim_bot,
                                hl_group = hl_group,
                                hl_mode = "combine",
                            })

                            -- calculate block width
                            local highlight_cols = opts.min_width
                            -- get longest line (if longer than min width)
                            for _, line in pairs(lines) do
                                local r_pad = opts.r_pad or 0
                                if #line + r_pad > highlight_cols then highlight_cols = #line + r_pad end
                            end
                            if opts.min_width ~= -1 then
                                -- pad lines with virt_text
                                for i, line in pairs(lines) do
                                    if i + trim_bot <= #lines then
                                        local virt_text = { { string.rep(" ", highlight_cols - #line), hl_group } }
                                        if opts.border and opts.border[3] then
                                            virt_text[#virt_text + 1] = { opts.border[3], border_hl_group }
                                        end
                                        nvim_buf_set_extmark(bufnr, M.namespace, start_row + i - 1, #line, {
                                            strict = false,
                                            virt_text = virt_text,
                                            virt_text_win_col = #line
                                        })
                                    end
                                end
                            end
                            if opts.border then
                                -- set top border
                                local top_border = { {
                                    opts.border[1]:rep(
                                        highlight_cols + vim.str_utfindex(opts.border[3]) - 1
                                    ), border_hl_group
                                } }
                                -- set top right corner border
                                if opts.border[2] then
                                    top_border[#top_border + 1] = {
                                        opts.border[2],
                                        border_hl_group
                                    }
                                end
                                -- FIX: doesn't account for columns
                                local existing_marks = vim.api.nvim_buf_get_extmarks(
                                    bufnr, M.namespace,
                                    { start_row - 1, 0 }, { start_row - 1, -1 },
                                    { details = true }
                                )
                                local above_marked = false
                                for _, mark in pairs(existing_marks) do
                                    if mark[4].virt_text or mark[4].virt_lines then
                                        above_marked = true
                                    end
                                end
                                local line_above = vim.api.nvim_buf_get_lines(bufnr, start_row - 1, start_row, false)[1]
                                if line_above ~= "" or above_marked or (not opts.dynamic_border) then
                                    nvim_buf_set_extmark(bufnr, M.namespace, start_row, 0, {
                                        virt_lines_above = true,
                                        virt_lines = { top_border },
                                    })
                                else
                                    nvim_buf_set_extmark(bufnr, M.namespace, start_row - 1, 0, {
                                        virt_text_pos = 'overlay',
                                        strict = false,
                                        virt_text = top_border,
                                        hl_mode = "combine",
                                    })
                                end

                                -- set bottom border
                                local bot_border = { {
                                    opts.border[5]:rep(
                                        highlight_cols + vim.str_utfindex(opts.border[3]) - 1
                                    ), border_hl_group
                                } }
                                -- set bottom right corner border
                                if #opts.border[3] >= 1 then
                                    bot_border[#bot_border + 1] = {
                                        opts.border[4],
                                        border_hl_group
                                    }
                                end

                                local bot_mark_opts = {}
                                local mark_row = end_row - trim_bot
                                local line_below = vim.api.nvim_buf_get_lines(bufnr, end_row, end_row + 1, false)[1]
                                if line_below ~= "" or (not opts.dynamic_border) or trim_bot == 0 then
                                    mark_row = mark_row - 1
                                    bot_mark_opts.virt_lines = { bot_border }
                                else
                                    bot_mark_opts = {
                                        virt_text_pos = 'overlay',
                                        strict = false,
                                        virt_text = bot_border,
                                        hl_mode = "combine",
                                    }
                                end
                                vim.api.nvim_buf_set_extmark(bufnr, M.namespace, mark_row, 0, bot_mark_opts)
                            end
                            _ = opts.misc_fmt and opts:misc_fmt(
                                node, bufnr, M.namespace,
                                highlight_cols, hl_group, border_hl_group
                            )
                            break
                        end
                    end
                end
            end

            if capture == "quote" and c.quote_highlight and c.quote_string then
                nvim_buf_set_extmark(bufnr, M.namespace, start_row, start_column, {
                    virt_text = { { c.quote_string, c.quote_highlight } },
                    virt_text_pos = "overlay",
                    hl_mode = "combine",
                })
            end
        end
    end
end

return M
