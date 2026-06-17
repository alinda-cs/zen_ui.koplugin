local _ = require("gettext")

local M = {}

local function valid_plugin(plugin)
    return type(plugin) == "table"
        and type(plugin.key) == "string"
        and type(plugin.method) == "string"
end

local function valid_entry(entry, allow_folder)
    if type(entry) ~= "table" or type(entry.id) ~= "string" then
        return false
    end
    if type(entry.label) ~= "string" or entry.label == "" then
        return false
    end
    if entry.type == "action" then
        return type(entry.action) == "table"
    elseif entry.type == "plugin" then
        return valid_plugin(entry.plugin)
    elseif allow_folder and entry.type == "folder" then
        return true
    end
    return false
end

local function sanitize_list(entries, allow_folder)
    local out = {}
    local changed = false
    if type(entries) ~= "table" then
        return out, true
    end
    for _i, entry in ipairs(entries) do
        if valid_entry(entry, allow_folder) then
            if entry.type == "folder" then
                local children, child_changed = sanitize_list(entry.children, false)
                local folder = entry
                if child_changed or type(entry.children) ~= "table" then
                    folder = {}
                    for key, value in pairs(entry) do
                        folder[key] = value
                    end
                    folder.children = children
                    changed = true
                end
                out[#out + 1] = folder
            else
                out[#out + 1] = entry
            end
        else
            changed = true
        end
    end
    return out, changed
end

local function max_id(entries, current)
    for _i, entry in ipairs(entries or {}) do
        local n = type(entry.id) == "string" and tonumber(entry.id:match("^al_(%d+)$"))
        if n and n > current then current = n end
        if entry.type == "folder" then
            current = max_id(entry.children, current)
        end
    end
    return current
end

function M.ensure(config)
    if type(config.app_launcher) ~= "table" then
        config.app_launcher = {}
    end
    local cfg = config.app_launcher
    local entries, changed = sanitize_list(cfg.entries, true)
    if changed then
        cfg.entries = entries
    elseif type(cfg.entries) ~= "table" then
        cfg.entries = {}
    end
    local max_seen = max_id(cfg.entries, 0)
    if type(cfg.next_id) ~= "number" or cfg.next_id < max_seen then
        cfg.next_id = max_seen
    end
    return cfg
end

function M.next_id(cfg)
    cfg.next_id = (tonumber(cfg.next_id) or 0) + 1
    return "al_" .. cfg.next_id
end

function M.find_by_id(entries, id)
    for i, entry in ipairs(entries or {}) do
        if entry.id == id then
            return entries, i, entry, nil
        end
        if entry.type == "folder" then
            for j, child in ipairs(entry.children or {}) do
                if child.id == id then
                    return entry.children, j, child, entry
                end
            end
        end
    end
end

function M.move_by(entries, id, dir)
    local list, index = M.find_by_id(entries, id)
    if not list then return false end
    local target = index + dir
    if target < 1 or target > #list then return false end
    list[index], list[target] = list[target], list[index]
    return true
end

function M.remove_by_id(entries, id)
    local list, index = M.find_by_id(entries, id)
    if not list then return false end
    table.remove(list, index)
    return true
end

function M.move_to_folder(entries, id, folder_id)
    local _list, _index, entry = M.find_by_id(entries, id)
    local _folder_list, _folder_index, folder = M.find_by_id(entries, folder_id)
    if not entry or not folder or entry.type == "folder" or folder.type ~= "folder" then
        return false
    end
    M.remove_by_id(entries, id)
    folder.children = folder.children or {}
    folder.children[#folder.children + 1] = entry
    return true
end

function M.move_to_root(entries, id)
    local _list, _index, entry, parent = M.find_by_id(entries, id)
    if not entry or not parent then return false end
    M.remove_by_id(entries, id)
    entries[#entries + 1] = entry
    return true
end

function M.display_label(entry)
    if not entry then return _("App") end
    return entry.label or _("App")
end

return M
