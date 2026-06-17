local M = {}

M.SENTINEL = "__menu_callback"
M.SUBMENU = "__menu_submenu"

local NATIVE = {
    screenshot = true,
    menu = true,
    history = true,
    bookinfo = true,
    collections = true,
    filesearcher = true,
    folder_shortcuts = true,
    languagesupport = true,
    dictionary = true,
    wikipedia = true,
    devicestatus = true,
    devicelistener = true,
    networklistener = true,
    zen_ui = true,
}

local LAUNCH_METHODS = { "onShow", "show", "open", "launch", "onOpen" }

local function live_file_manager()
    local fm_mod = package.loaded["apps/filemanager/filemanager"]
    return fm_mod and fm_mod.instance or nil
end

local function probe_menu_entry(mod, key)
    if type(mod.addToMainMenu) ~= "function" then return nil end
    local probe = {}
    local ok = pcall(mod.addToMainMenu, mod, probe)
    if not ok then return nil end
    local entry = probe[key]
    if entry == nil and type(mod.name) == "string" then
        entry = probe[mod.name]
    end
    if entry == nil then
        local only, count = nil, 0
        for _k, value in pairs(probe) do
            if type(value) == "table" then
                count = count + 1
                only = value
            end
        end
        if count == 1 then entry = only end
    end
    return type(entry) == "table" and entry or nil
end

local function text_without_glyph(text)
    if type(text) ~= "string" then return nil end
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function find_method(mod, key)
    for _i, method in ipairs(LAUNCH_METHODS) do
        if type(mod[method]) == "function" then return method end
    end
    local camel = "on" .. key:sub(1, 1):upper() .. key:sub(2)
    if type(mod[camel]) == "function" then return camel end
    local entry = probe_menu_entry(mod, key)
    if entry then
        if type(entry.callback) == "function" then
            return M.SENTINEL
        end
        if entry.sub_item_table ~= nil or entry.sub_item_table_func ~= nil then
            return M.SUBMENU
        end
    end
end

function M.scan()
    local ok, results = pcall(function()
        local fm = live_file_manager()
        if not fm then return {} end
        local key_of = {}
        for key, value in pairs(fm) do
            if type(key) == "string" and type(value) == "table" then
                key_of[value] = key
            end
        end
        local out, seen = {}, {}
        for _i, mod in ipairs(fm) do
            local key = type(mod) == "table" and type(mod.name) == "string"
                and key_of[mod] or nil
            if key and not NATIVE[key] and not seen[key]
                    and type(mod.addToMainMenu) == "function" then
                seen[key] = true
                local method = find_method(mod, key)
                if method then
                    local entry = probe_menu_entry(mod, key)
                    local title = entry and text_without_glyph(entry.text)
                    if not title or title == "" then
                        title = key:sub(1, 1):upper() .. key:sub(2)
                    end
                    out[#out + 1] = { key = key, method = method, title = title }
                end
            end
        end
        table.sort(out, function(a, b) return a.title < b.title end)
        return out
    end)
    return ok and results or {}
end

function M.exists(key, method)
    if type(key) ~= "string" or type(method) ~= "string" then return false end
    local fm = live_file_manager()
    local mod = fm and fm[key]
    if type(mod) ~= "table" then return false end
    if method == M.SENTINEL or method == M.SUBMENU then
        return type(mod.addToMainMenu) == "function"
    end
    return type(mod[method]) == "function"
end

local TOUCHMENU_STUB = {
    closeMenu = function() end,
    updateItems = function() end,
    handleEvent = function() return false end,
}

function M.resolve(key, method)
    if type(key) ~= "string" or type(method) ~= "string" then return nil end
    local fm = live_file_manager()
    local mod = fm and fm[key]
    if type(mod) ~= "table" then return nil end
    if method == M.SENTINEL then
        local entry = probe_menu_entry(mod, key)
        local callback = entry and entry.callback
        if type(callback) ~= "function" then return nil end
        return function()
            return callback(TOUCHMENU_STUB)
        end
    end
    if method == M.SUBMENU then
        local entry = probe_menu_entry(mod, key)
        if not entry then return nil end
        local sub_items = entry.sub_item_table
        if sub_items == nil and type(entry.sub_item_table_func) == "function" then
            local ok_sub, res = pcall(entry.sub_item_table_func, TOUCHMENU_STUB)
            if ok_sub then sub_items = res end
        end
        if type(sub_items) ~= "table" then return nil end
        local title = type(entry.text) == "string" and entry.text or key
        return function()
            return require("modules/menu/app_launcher/menu_host").show{
                title = title,
                item_table = sub_items,
            }
        end
    end
    if type(mod[method]) ~= "function" then return nil end
    return function()
        return mod[method](mod)
    end
end

return M
