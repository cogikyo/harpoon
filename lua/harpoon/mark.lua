local harpoon = require("harpoon")
local utils = require("harpoon.utils")
local log = require("harpoon.dev").log

local M = {}
local callbacks = {}
local active_slots = 20

local function emit_changed()
    log.trace("_emit_changed()")

    local global_settings = harpoon.get_global_settings()

    if global_settings.save_on_change then
        harpoon.save()
    end

    if global_settings.tabline then
        vim.cmd("redrawt")
    end

    if not callbacks.changed then
        log.trace("_emit_changed(): no callbacks for 'changed', returning")
        return
    end

    for idx, cb in pairs(callbacks.changed) do
        log.trace(string.format("_emit_changed(): Running callback #%d for 'changed'", idx))
        cb()
    end
end

local function active_filenames(marks)
    if marks then
        local list = {}
        for _, mark in ipairs(marks) do
            if type(mark) == "table" then
                table.insert(list, mark.filename)
            elseif type(mark) == "string" then
                table.insert(list, mark)
            end
        end
        return list
    end
    return harpoon.get_active_list()
end

local function get_buf_name(id)
    log.trace("_get_buf_name():", id)
    if id == nil then
        return utils.normalize_path(vim.api.nvim_buf_get_name(0))
    elseif type(id) == "string" then
        return utils.normalize_path(id)
    end

    local idx = M.get_index_of(id)
    if M.valid_index(idx) then
        return M.get_marked_file_name(idx)
    end

    return ""
end

local function remove_filename(list, filename)
    for idx = #list, 1, -1 do
        if list[idx] == filename then
            table.remove(list, idx)
        end
    end
end

local function is_pinned(filename)
    for _, pin in ipairs(harpoon.get_project_config().pins) do
        if pin == filename then
            return true
        end
    end
    return false
end

local function mark_exists(buf_name)
    log.trace("_mark_exists()")
    return M.valid_index(M.get_index_of(buf_name))
end

local function valid_buf_name(buf_name)
    log.trace("_validate_buf_name():", buf_name)
    if buf_name == "" or buf_name == nil then
        log.warn("_validate_buf_name(): Not a valid name for a mark,", buf_name)
        return false
    end
    return true
end

local function valid_filetype()
    if vim.bo.buftype ~= "" then
        log.warn("filter_filetype(): Only normal file buffers can be added")
        return false
    end

    if vim.bo.filetype == "harpoon" then
        log.warn("filter_filetype(): You can't add harpoon to the harpoon")
        return false
    end
    return true
end

function M.get_index_of(item, marks)
    log.trace("get_index_of():", item)
    if item == nil then
        log.error("get_index_of(): Function has been supplied with a nil value.")
        error("You have provided a nil value to Harpoon, please provide a string rep of the file or the file idx.")
    end

    if type(item) == "string" then
        local relative_item = utils.normalize_path(item)
        for idx, filename in ipairs(active_filenames(marks)) do
            if filename == relative_item then
                return idx
            end
        end
        return nil
    end

    if vim.g.manage_a_mark_zero_index then
        item = item + 1
    end

    if item <= active_slots and item >= 1 then
        return item
    end

    log.debug("get_index_of(): No item found,", item)
    return nil
end

function M.status(bufnr)
    log.trace("status()")
    local buf_name
    if bufnr then
        buf_name = vim.api.nvim_buf_get_name(bufnr)
    else
        buf_name = vim.api.nvim_buf_get_name(0)
    end

    local idx = M.get_index_of(utils.normalize_path(buf_name))
    if M.valid_index(idx) then
        return "M" .. idx
    end
    return ""
end

function M.valid_index(idx, marks)
    log.trace("valid_index():", idx)
    if idx == nil then
        return false
    end

    local file_name = M.get_marked_file_name(idx, marks)
    return file_name ~= nil and file_name ~= ""
end

function M.add_file(file_name_or_buf_id)
    if not valid_filetype() then
        return
    end
    local buf_name = get_buf_name(file_name_or_buf_id)
    log.trace("add_file():", buf_name)

    if is_pinned(buf_name) then
        return
    end

    if not valid_buf_name(buf_name) then
        return
    end

    local pins = harpoon.get_project_config().pins
    if #pins >= active_slots then
        table.remove(pins, active_slots)
    end
    table.insert(pins, buf_name)
    emit_changed()
end

function M.remove_empty_tail(_emit_on_changed)
    log.trace("remove_empty_tail()")
    if _emit_on_changed == nil or _emit_on_changed then
        emit_changed()
    end
end

function M.store_offset()
    log.trace("store_offset()")
end

function M.rm_file(file_name_or_buf_id)
    local buf_name = get_buf_name(file_name_or_buf_id)
    local idx = M.get_index_of(buf_name)
    log.trace("rm_file(): Removing mark at id", idx)

    if not M.valid_index(idx) then
        log.debug("rm_file(): No mark exists for id", file_name_or_buf_id)
        return
    end

    local project = harpoon.get_project_config()
    remove_filename(project.pins, buf_name)
    project.visits[buf_name] = nil
    emit_changed()
end

function M.clear_all()
    local project = harpoon.get_project_config()
    project.pins = {}
    project.visits = {}
    log.trace("clear_all(): Clearing all marks.")
    emit_changed()
end

function M.get_marked_file(idxOrName)
    log.trace("get_marked_file():", idxOrName)
    if type(idxOrName) == "string" then
        idxOrName = M.get_index_of(idxOrName)
    end
    local filename = active_filenames()[idxOrName]
    if filename then
        return { filename = filename }
    end
    return nil
end

function M.get_marked_file_name(idx, marks)
    local filename = active_filenames(marks)[idx]
    log.trace("get_marked_file_name():", filename)
    return filename
end

function M.get_length(marks)
    log.trace("get_length()")
    return #active_filenames(marks)
end

function M.get_capacity()
    return active_slots
end

function M.set_current_at(idx)
    if not valid_filetype() then
        return
    end
    local buf_name = get_buf_name()
    log.trace("set_current_at(): Setting id", idx, buf_name)
    if not valid_buf_name(buf_name) then
        return
    end
    if type(idx) ~= "number" or idx < 1 or idx > active_slots or idx % 1 ~= 0 then
        return
    end

    local pins = harpoon.get_project_config().pins
    remove_filename(pins, buf_name)

    -- Dense curated list: replace in-range, append past the tail, never open gaps.
    if idx <= #pins then
        pins[idx] = buf_name
    elseif #pins < active_slots then
        table.insert(pins, buf_name)
    end

    emit_changed()
end

function M.to_quickfix_list()
    log.trace("to_quickfix_list(): Sending marks to quickfix list.")
    local qf_list = {}
    for idx, filename in ipairs(active_filenames()) do
        qf_list[idx] = {
            text = string.format("%d: %s", idx, filename),
            filename = filename,
        }
    end
    log.debug("to_quickfix_list(): qf_list:", qf_list)
    vim.fn.setqflist(qf_list)
end

function M.set_mark_list(new_list)
    log.trace("set_mark_list(): New list:", new_list)
    local pins = {}
    local seen = {}

    for _, item in ipairs(new_list) do
        local filename = item
        if type(item) == "table" then
            filename = item.filename
        end
        if type(filename) == "string" then
            filename = utils.normalize_path(filename)
            if filename ~= "" and filename ~= "(empty)" and not seen[filename] then
                seen[filename] = true
                table.insert(pins, filename)
                if #pins >= active_slots then
                    break
                end
            end
        end
    end

    local project = harpoon.get_project_config()
    project.pins = pins
    project.visits = {}
    emit_changed()
end

function M.toggle_file(file_name_or_buf_id)
    local buf_name = get_buf_name(file_name_or_buf_id)
    log.trace("toggle_file():", buf_name)

    if not valid_buf_name(buf_name) then
        return
    end

    if mark_exists(buf_name) then
        M.rm_file(buf_name)
        print("Mark removed")
        log.debug("toggle_file(): Mark removed")
    else
        M.add_file(buf_name)
        print("Mark added")
        log.debug("toggle_file(): Mark added")
    end
end

function M.get_current_index()
    log.trace("get_current_index()")
    return M.get_index_of(vim.api.nvim_buf_get_name(0))
end

function M.on(event, cb)
    log.trace("on():", event)
    callbacks[event] = callbacks[event] or {}
    table.insert(callbacks[event], cb)
    log.debug("on(): All callbacks:", callbacks)
end

return M
