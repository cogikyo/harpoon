local Path = require("plenary.path")
local data_path = vim.fn.stdpath("data")
local Job = require("plenary.job")

local M = {}

M.data_path = data_path

function M.project_key()
    local cwd = vim.loop.cwd()
    return vim.fs.root(cwd, { ".git" }) or cwd
end

function M.branch_key()
    local branch

    -- use tpope's fugitive for faster branch name resolution if available
    if vim.fn.exists("*FugitiveHead") == 1 then
        branch = vim.fn["FugitiveHead"]()
        -- return "HEAD" for parity with `git rev-parse` in detached head state
        if #branch == 0 then
            branch = "HEAD"
        end
    else
        -- `git branch --show-current` requires Git v2.22.0+ so going with more
        -- widely available command
        branch = M.get_os_command_output({
            "git",
            "rev-parse",
            "--abbrev-ref",
            "HEAD",
        })[1]
    end

    if branch then
        return M.project_key() .. "-" .. branch
    else
        return M.project_key()
    end
end

function M.normalize_path(item)
    return Path:new(item):make_relative(M.project_key())
end

function M.get_os_command_output(cmd, cwd)
    if type(cmd) ~= "table" then
        print("Harpoon: [get_os_command_output]: cmd has to be a table")
        return {}
    end
    local command = table.remove(cmd, 1)
    local stderr = {}
    local stdout, ret = Job
        :new({
            command = command,
            args = cmd,
            cwd = cwd,
            on_stderr = function(_, data)
                table.insert(stderr, data)
            end,
        })
        :sync()
    return stdout, ret, stderr
end

function M.split_string(str, delimiter)
    local result = {}
    for match in (str .. delimiter):gmatch("(.-)" .. delimiter) do
        table.insert(result, match)
    end
    return result
end

function M.is_white_space(str)
    return str:gsub("%s", "") == ""
end

function M.set_border_background(border_hl, window_hl)
    local ok_border, border = pcall(vim.api.nvim_get_hl, 0, {
        name = border_hl,
        link = false,
    })
    local ok_window, window = pcall(vim.api.nvim_get_hl, 0, {
        name = window_hl,
        link = false,
    })

    if not ok_border or not ok_window or window.bg == nil then
        return border_hl
    end

    local hl = vim.tbl_extend("force", border, { bg = window.bg })
    local merged_hl = border_hl .. "WithBackground"
    vim.api.nvim_set_hl(0, merged_hl, hl)

    return merged_hl
end

return M
