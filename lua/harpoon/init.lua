local utils = require("harpoon.utils")
local Dev = require("harpoon.dev")
local log = Dev.log

local config_path = vim.fn.stdpath("config")
local pins_path = string.format("%s/harpoon.json", config_path)
local state_path = string.format("%s/harpoon.json", vim.fn.stdpath("state"))
local old_data_config = string.format("%s/harpoon.json", vim.fn.stdpath("data"))
local active_slots = 20
local visit_interval = 120

local M = {}
local save_timer = nil
local seen_visits = {}
local term_configs = {}

local the_primeagen_harpoon = vim.api.nvim_create_augroup(
    "THE_PRIMEAGEN_HARPOON",
    { clear = true }
)

vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = function()
        M.save_state()
    end,
    group = the_primeagen_harpoon,
})

vim.api.nvim_create_autocmd("BufEnter", {
    callback = function(args)
        M.track_visit(args.buf)
    end,
    group = the_primeagen_harpoon,
})

vim.api.nvim_create_autocmd("FileType", {
    pattern = "harpoon",
    group = the_primeagen_harpoon,

    callback = function()
        -- Open harpoon file choice in useful ways
        --
        -- vertical split (control+v)
        vim.keymap.set("n", "<C-V>", function()
            local curline = vim.api.nvim_get_current_line()
            if curline == "(empty)" then
                return
            end
            vim.cmd("vs")
            vim.cmd("e " .. vim.fn.fnameescape(curline))
        end, { buffer = true, noremap = true, silent = true })

        -- horizontal split (control+x)
        vim.keymap.set("n", "<C-x>", function()
            local curline = vim.api.nvim_get_current_line()
            if curline == "(empty)" then
                return
            end
            vim.cmd("sp")
            vim.cmd("e " .. vim.fn.fnameescape(curline))
        end, { buffer = true, noremap = true, silent = true })

        -- new tab (control+t)
        vim.keymap.set("n", "<C-t>", function()
            local curline = vim.api.nvim_get_current_line()
            if curline == "(empty)" then
                return
            end
            vim.cmd("tabnew")
            vim.cmd("e " .. vim.fn.fnameescape(curline))
        end, { buffer = true, noremap = true, silent = true })
    end,
})
HarpoonConfig = HarpoonConfig or {}

local function is_sequence(tbl)
    if type(tbl) ~= "table" then
        return false
    end
    for key in pairs(tbl) do
        if type(key) ~= "number" then
            return false
        end
    end
    return true
end

-- tbl_deep_extend does not work the way you would think
local function merge_table_impl(t1, t2)
    for k, v in pairs(t2) do
        if type(v) == "table" then
            if is_sequence(v) then
                t1[k] = vim.deepcopy(v)
            elseif type(t1[k]) == "table" then
                merge_table_impl(t1[k], v)
            else
                t1[k] = v
            end
        else
            t1[k] = v
        end
    end
end

local function mark_config_key(global_settings)
    global_settings = global_settings or M.get_global_settings()
    if global_settings.mark_branch then
        return utils.branch_key()
    else
        return utils.project_key()
    end
end

local function sorted_keys(tbl)
    local keys = {}
    for key in pairs(tbl or {}) do
        table.insert(keys, key)
    end
    table.sort(keys, function(a, b)
        return tostring(a) < tostring(b)
    end)
    return keys
end

local function is_array(tbl)
    local max = 0
    local count = 0
    for key in pairs(tbl) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
            return false
        end
        max = math.max(max, key)
        count = count + 1
    end
    return max == count
end

local function encode_json(value, indent)
    indent = indent or 0
    local value_type = type(value)
    if value_type ~= "table" then
        return vim.json.encode(value)
    end

    local next_indent = indent + 2
    local pad = string.rep(" ", indent)
    local child_pad = string.rep(" ", next_indent)

    if vim.tbl_isempty(value) then
        return "{}"
    end

    local parts = {}
    if is_array(value) then
        for idx = 1, #value do
            table.insert(parts, child_pad .. encode_json(value[idx], next_indent))
        end
        return "[\n" .. table.concat(parts, ",\n") .. "\n" .. pad .. "]"
    end

    for _, key in ipairs(sorted_keys(value)) do
        table.insert(
            parts,
            child_pad
                .. vim.json.encode(tostring(key))
                .. ": "
                .. encode_json(value[key], next_indent)
        )
    end
    return "{\n" .. table.concat(parts, ",\n") .. "\n" .. pad .. "}"
end

local function encode_array(value, indent)
    if #value == 0 then
        return "[]"
    end
    return encode_json(value, indent)
end

local function encode_clean_config(config, mode)
    local project_lines = {}
    for _, key in ipairs(sorted_keys(config.projects)) do
        local project = config.projects[key]
        local fields = {}

        if mode == "pins" or mode == "all" then
            if #project.pins > 0 then
                table.insert(fields, "      \"pins\": " .. encode_array(project.pins, 6))
            end
        end

        if mode == "state" or mode == "all" then
            local visit_lines = {}
            for _, filename in ipairs(sorted_keys(project.visits)) do
                table.insert(
                    visit_lines,
                    "        "
                        .. vim.json.encode(filename)
                        .. ": "
                        .. encode_json(project.visits[filename], 8)
                )
            end
            if #visit_lines > 0 then
                table.insert(fields, "      \"visits\": {\n" .. table.concat(visit_lines, ",\n") .. "\n      }")
            end
        end

        if #fields == 0 then
            goto continue
        end

        table.insert(
            project_lines,
            "    "
                .. vim.json.encode(key)
                .. ": {\n"
                .. table.concat(fields, ",\n")
                .. "\n"
                .. "    }"
        )
        ::continue::
    end

    local projects = "{}"
    if #project_lines > 0 then
        projects = "{\n" .. table.concat(project_lines, ",\n") .. "\n  }"
    end

    return "{\n  \"version\": 1,\n  \"projects\": " .. projects .. "\n}"
end

local function clean_filename(filename, project_key)
    if type(filename) ~= "string" or filename == "" or filename == "(empty)" then
        return nil
    end
    if project_key and vim.fn.fnamemodify(filename, ":p") == filename then
        local prefix = project_key:gsub("/$", "") .. "/"
        if filename:sub(1, #prefix) == prefix then
            return filename:sub(#prefix + 1)
        end
    end
    return utils.normalize_path(filename)
end

local function unique_pins(list, project_key)
    local pins = {}
    local seen = {}
    for _, item in ipairs(list or {}) do
        local filename = item
        if type(item) == "table" then
            filename = item.filename
        end
        filename = clean_filename(filename, project_key)
        if filename and not seen[filename] then
            seen[filename] = true
            table.insert(pins, filename)
            if #pins >= active_slots then
                break
            end
        end
    end
    return pins
end

local function clean_visits(visits, project_key)
    local clean = {}
    for filename, visit in pairs(visits or {}) do
        local clean_name = clean_filename(filename, project_key)
        if clean_name and type(visit) == "table" then
            local count = tonumber(visit.count) or 0
            local last = tonumber(visit.last) or 0
            if count > 0 then
                clean[clean_name] = { count = count, last = last }
            end
        end
    end
    return clean
end

local function migrate_project(project, key)
    local migrated = {}

    if type(project) == "table" then
        if type(project.pins) == "table" then
            migrated.pins = unique_pins(project.pins, key)
        elseif type(project.mark) == "table" and type(project.mark.marks) == "table" then
            migrated.pins = unique_pins(project.mark.marks, key)
        end

        if type(project.visits) == "table" then
            migrated.visits = clean_visits(project.visits, key)
        end
    end

    if (not migrated.pins or #migrated.pins == 0)
        and (not migrated.visits or vim.tbl_isempty(migrated.visits))
    then
        return nil
    end

    return migrated
end

local function migrate_config(config)
    local migrated = { version = 1, projects = {} }
    for key, project in pairs((config or {}).projects or {}) do
        local clean_project = migrate_project(project, key)
        if clean_project then
            migrated.projects[key] = clean_project
        end
    end
    return migrated
end

local function ensure_project(config, key)
    config.projects = config.projects or {}
    if config.projects[key] == nil then
        config.projects[key] = { pins = {}, visits = {} }
    end
    config.projects[key].pins = unique_pins(config.projects[key].pins, key)
    config.projects[key].visits = clean_visits(config.projects[key].visits, key)
    return config.projects[key]
end

local function merge_tables(...)
    log.trace("_merge_tables()")
    local out = {}
    for i = 1, select("#", ...) do
        merge_table_impl(out, select(i, ...))
    end
    return out
end

local function ensure_correct_config(config)
    log.trace("_ensure_correct_config()")
    config.version = 1
    config.projects = config.projects or {}
    for key in pairs(config.projects) do
        ensure_project(config, key)
    end
    ensure_project(config, mark_config_key(config.global_settings))
    return config
end

local function expand_dir(config)
    log.trace("_expand_dir(): Config pre-expansion:", config)

    local projects = config.projects or {}
    for k in pairs(projects) do
        local expanded_path = k:gsub("^~", vim.fn.expand("~"))
        projects[expanded_path] = projects[k]
        if expanded_path ~= k then
            projects[k] = nil
        end
    end

    log.trace("_expand_dir(): Config post-expansion:", config)
    return config
end

function M.save()
    log.trace("save(): Saving pins to", pins_path)
    local config = migrate_config(HarpoonConfig)
    vim.fn.mkdir(vim.fn.fnamemodify(pins_path, ":h"), "p")
    vim.fn.writefile(vim.split(encode_clean_config(config, "pins"), "\n", { plain = true }), pins_path)
    M.save_state()
end

function M.save_state()
    log.trace("save_state(): Saving visits to", state_path)
    local config = migrate_config(HarpoonConfig)
    vim.fn.mkdir(vim.fn.fnamemodify(state_path, ":h"), "p")
    vim.fn.writefile(vim.split(encode_clean_config(config, "state"), "\n", { plain = true }), state_path)
end

local function read_config(local_config)
    log.trace("_read_config():", local_config)
    return vim.json.decode(table.concat(vim.fn.readfile(local_config), "\n"))
end

-- 1. saved.  Where do we save?
function M.setup(config)
    log.trace("setup(): Setting up...")

    if not config then
        config = {}
    end

    pins_path = vim.fn.expand(config.pins_path or config.storage_path or pins_path)
    state_path = vim.fn.expand(config.state_path or state_path)
    config.pins_path = nil
    config.storage_path = nil
    config.state_path = nil

    local ok, u_config = pcall(read_config, pins_path)

    if not ok then
        log.debug("setup(): No pins config present at", pins_path)
        u_config = {}
    end

    local ok_state, state_config = pcall(read_config, state_path)

    if not ok_state then
        log.debug("setup(): No local state config present at", state_path)
        state_config = {}
    end

    local ok_data, data_config = pcall(read_config, old_data_config)

    if not ok_data then
        log.debug("setup(): No old data config present at", old_data_config)
        data_config = {}
    end

    local complete_config = merge_tables({
        version = 1,
        projects = {},
        global_settings = {
            ["save_on_toggle"] = false,
            ["save_on_change"] = true,
            ["enter_on_sendcmd"] = false,
            ["tmux_autoclose_windows"] = false,
            ["excluded_filetypes"] = { "harpoon" },
            ["mark_branch"] = false,
            ["tabline"] = false,
            ["tabline_suffix"] = "   ",
            ["tabline_prefix"] = "   ",
        },
    }, expand_dir(migrate_config(data_config)), expand_dir(migrate_config(state_config)), expand_dir(migrate_config(u_config)), expand_dir(config))

    -- There was this issue where the vim.loop.cwd() didn't have marks or term, but had
    -- an object for vim.loop.cwd()
    ensure_correct_config(complete_config)

    if complete_config.tabline then
        require("harpoon.tabline").setup(complete_config)
    end

    HarpoonConfig = complete_config

    log.debug("setup(): Complete config", HarpoonConfig)
    log.trace("setup(): log_key", Dev.get_log_key())
end

function M.get_global_settings()
    log.trace("get_global_settings()")
    return HarpoonConfig.global_settings
end

function M.get_project_config(key)
    return ensure_project(ensure_correct_config(HarpoonConfig), key or mark_config_key())
end

function M.get_active_list(key)
    local project = M.get_project_config(key)
    local active = vim.deepcopy(project.pins)
    local pinned = {}
    for _, filename in ipairs(active) do
        pinned[filename] = true
    end

    local candidates = {}
    for filename, visit in pairs(project.visits) do
        if not pinned[filename] and visit.count >= 5 then
            table.insert(candidates, {
                filename = filename,
                count = visit.count,
                last = visit.last,
            })
        end
    end
    table.sort(candidates, function(a, b)
        if a.count ~= b.count then
            return a.count > b.count
        end
        if a.last ~= b.last then
            return a.last > b.last
        end
        return a.filename < b.filename
    end)

    for _, item in ipairs(candidates) do
        if #active >= active_slots then
            break
        end
        table.insert(active, item.filename)
    end

    return active
end

function M.save_deferred()
    if save_timer then
        save_timer:stop()
    else
        save_timer = vim.loop.new_timer()
    end

    save_timer:start(300, 0, vim.schedule_wrap(function()
        M.save_state()
    end))
end

local function is_normal_file(bufnr)
    if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
        return false
    end
    if vim.api.nvim_buf_get_option(bufnr, "buftype") ~= "" then
        return false
    end
    return vim.api.nvim_buf_get_name(bufnr) ~= ""
end

function M.track_visit(bufnr)
    if not is_normal_file(bufnr) then
        return
    end

    local key = mark_config_key()
    local filename = clean_filename(vim.api.nvim_buf_get_name(bufnr))
    if not filename then
        return
    end

    local now = os.time()
    seen_visits[key] = seen_visits[key] or {}
    if seen_visits[key][filename] and now - seen_visits[key][filename] < visit_interval then
        return
    end
    seen_visits[key][filename] = now

    local visits = M.get_project_config(key).visits
    visits[filename] = visits[filename] or { count = 0, last = 0 }
    visits[filename].count = visits[filename].count + 1
    visits[filename].last = now
    M.save_deferred()
end

-- refresh all projects from disk, except our current one
function M.refresh_projects_b4update()
    log.trace("refresh_projects_b4update(): no-op for clean forked schema")
    ensure_correct_config(HarpoonConfig)
end

function M.get_term_config()
    log.trace("get_term_config()")
    local key = utils.project_key()
    term_configs[key] = term_configs[key] or { cmds = {} }
    return term_configs[key]
end

function M.get_mark_config()
    log.trace("get_mark_config()")
    local marks = {}
    for idx, filename in ipairs(M.get_active_list(mark_config_key())) do
        marks[idx] = { filename = filename }
    end
    return { marks = marks }
end

function M.get_menu_config()
    log.trace("get_menu_config()")
    return HarpoonConfig.menu or {}
end

-- should only be called for debug purposes
function M.print_config()
    print(vim.inspect(HarpoonConfig))
end

-- Sets a default config with no values
M.setup()

return M
