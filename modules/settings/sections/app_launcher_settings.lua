local _ = require("gettext")
local T = require("ffi/util").template
local UIManager = require("ui/uimanager")

local Model = require("modules/menu/app_launcher/model")
local PluginScan = require("modules/menu/app_launcher/plugin_scan")

local M = {}

local function trim(text)
    return (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

function M.build(ctx)
    local config = ctx.config
    local save_and_apply = ctx.save_and_apply
    local cfg = Model.ensure(config)
    local build_entry_items
    local show_entries_arrange

    local function save_app_launcher()
        save_and_apply("app_launcher")
    end

    local function open_entry_settings(touch_menu, entry, parent)
        if not (touch_menu and type(touch_menu.updateItems) == "function" and entry) then
            return
        end
        table.insert(touch_menu.item_table_stack, touch_menu.item_table)
        touch_menu.parent_id = nil
        touch_menu.item_table = build_entry_items(entry, parent)
        touch_menu:updateItems(1)
    end

    local ok_disp, Dispatcher = pcall(require, "dispatcher")

    local ICONS
    local function get_icons()
        if ICONS then return ICONS end
        local icon_utils = require("common/utils")
        local ok_root, root = pcall(require, "common/plugin_root")
        ICONS = icon_utils.getIconPickerList(ok_root and root or nil, {
            zen_ui_light = true,
            zen_ui_update = true,
        })
        return ICONS
    end

    local function show_icon_picker(entry, touch_menu)
        require("common/ui/zen_icon_picker")(get_icons(), entry.icon, function(name)
            entry.icon = name
            save_app_launcher()
            if touch_menu and touch_menu.updateItems then
                touch_menu:updateItems(1)
            end
        end)
    end

    local function prompt_label(entry, title)
        local InputDialog = require("ui/widget/inputdialog")
        local dialog
        dialog = InputDialog:new{
            title = title,
            input = entry.label or "",
            buttons = {{
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("Set"),
                    is_enter_default = true,
                    callback = function()
                        local label = trim(dialog:getInputText())
                        if label ~= "" then
                            entry.label = label
                            save_app_launcher()
                        end
                        UIManager:close(dialog)
                    end,
                },
            }},
        }
        UIManager:show(dialog)
        dialog:onShowKeyboard()
    end

    local function insert_entry(entry, folder)
        if folder then
            folder.children = folder.children or {}
            folder.children[#folder.children + 1] = entry
        else
            cfg.entries[#cfg.entries + 1] = entry
        end
        save_app_launcher()
    end

    local function new_action_entry(label)
        return {
            id = Model.next_id(cfg),
            type = "action",
            label = label or _("Action"),
            icon = "app_launcher",
            action = {},
        }
    end

    local function add_action(folder)
        local entry = new_action_entry()
        insert_entry(entry, folder)
        return entry
    end

    local function add_folder(touch_menu)
        local InputDialog = require("ui/widget/inputdialog")
        local dialog
        dialog = InputDialog:new{
            title = _("New folder"),
            input = "",
            buttons = {{
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("Add"),
                    is_enter_default = true,
                    callback = function()
                        local label = trim(dialog:getInputText())
                        UIManager:close(dialog)
                        if label == "" then return end
                        local entry = {
                            id = Model.next_id(cfg),
                            type = "folder",
                            label = label,
                            icon = "app_menu",
                            children = {},
                        }
                        insert_entry(entry)
                        UIManager:nextTick(function()
                            open_entry_settings(touch_menu, entry, nil)
                        end)
                    end,
                },
            }},
        }
        UIManager:show(dialog)
        dialog:onShowKeyboard()
    end

    local function add_plugin(folder, touch_menu)
        local found = PluginScan.scan()
        if #found == 0 then
            local InfoMessage = require("ui/widget/infomessage")
            UIManager:show(InfoMessage:new{ text = _("No launchable plugin menus found") })
            return
        end
        local ButtonDialog = require("ui/widget/buttondialog")
        local dialog
        local buttons = {}
        for _i, plugin in ipairs(found) do
            buttons[#buttons + 1] = {{
                text = plugin.title,
                callback = function()
                    UIManager:close(dialog)
                    local entry = {
                        id = Model.next_id(cfg),
                        type = "plugin",
                        label = plugin.title,
                        icon = "app_launcher",
                        plugin = { key = plugin.key, method = plugin.method },
                    }
                    insert_entry(entry, folder)
                    UIManager:nextTick(function()
                        open_entry_settings(touch_menu, entry, folder)
                    end)
                end,
            }}
        end
        dialog = ButtonDialog:new{
            title = _("Choose plugin menu"),
            title_align = "center",
            width_factor = 0.85,
            buttons = buttons,
        }
        UIManager:show(dialog)
    end

    local function add_items(folder)
        return {
            {
                text = _("Add dispatcher action"),
                keep_menu_open = true,
                callback = function(touch_menu)
                    local entry = add_action(folder)
                    open_entry_settings(touch_menu, entry, folder)
                end,
            },
            {
                text = _("Add plugin menu"),
                keep_menu_open = true,
                callback = function(touch_menu)
                    add_plugin(folder, touch_menu)
                end,
            },
        }
    end

    local function build_action_picker(entry)
        if not ok_disp then return nil end
        local dispatch_items = {}
        local caller = setmetatable({}, {
            __newindex = function(t, key, value)
                if key == "updated" and value then
                    save_app_launcher()
                else
                    rawset(t, key, value)
                end
            end,
            __index = function()
                return nil
            end,
        })
        Dispatcher:addSubMenu(caller, dispatch_items, entry, "action")
        return {
            text_func = function()
                if entry.action and next(entry.action) then
                    return T(_("Action: %1"), Dispatcher:menuTextFunc(entry.action))
                end
                return _("Action: (none)")
            end,
            keep_menu_open = true,
            sub_item_table = dispatch_items,
        }
    end

    local function build_move_items(entry, parent)
        local items = {}
        if entry.type ~= "folder" then
            if parent then
                items[#items + 1] = {
                    text = _("Move out of folder"),
                    callback = function(touch_menu)
                        if Model.move_to_root(cfg.entries, entry.id) then
                            save_app_launcher()
                            if touch_menu then touch_menu:backToUpperMenu() end
                        end
                    end,
                }
            else
                for _i, candidate in ipairs(cfg.entries) do
                    if candidate.type == "folder" then
                        local folder_id = candidate.id
                        items[#items + 1] = {
                            text = T(_("Move to folder: %1"), candidate.label),
                            callback = function(touch_menu)
                                if Model.move_to_folder(cfg.entries, entry.id, folder_id) then
                                    save_app_launcher()
                                    if touch_menu then touch_menu:backToUpperMenu() end
                                end
                            end,
                        }
                    end
                end
            end
        end
        return items
    end

    build_entry_items = function(entry, parent)
        local items = {
            {
                text_func = function()
                    return T(_("Label: %1"), entry.label)
                end,
                keep_menu_open = true,
                callback = function()
                    prompt_label(entry, _("Launcher label"))
                end,
            },
            {
                text_func = function()
                    return T(_("Icon: %1"), entry.icon or "app_launcher")
                end,
                keep_menu_open = true,
                callback = function(touch_menu)
                    show_icon_picker(entry, touch_menu)
                end,
            },
        }
        if entry.type == "action" then
            local picker = build_action_picker(entry)
            if picker then items[#items + 1] = picker end
        elseif entry.type == "folder" then
            items[#items + 1] = {
                text = _("Folder entries"),
                keep_menu_open = true,
                callback = function()
                    show_entries_arrange(entry)
                end,
            }
            local add_sub = add_items(entry)
            for _i, item in ipairs(add_sub) do
                items[#items + 1] = item
            end
        end
        local move_items = build_move_items(entry, parent)
        for _i, item in ipairs(move_items) do
            items[#items + 1] = item
        end
        items[#items + 1] = {
            text = _("Delete"),
            separator = true,
            callback = function(touch_menu)
                local function remove()
                    Model.remove_by_id(cfg.entries, entry.id)
                    save_app_launcher()
                    if touch_menu then touch_menu:backToUpperMenu() end
                end
                if entry.type == "folder" and entry.children and #entry.children > 0 then
                    UIManager:show(require("ui/widget/confirmbox"):new{
                        text = _("Delete this folder and its entries?"),
                        ok_text = _("Delete"),
                        ok_callback = remove,
                    })
                else
                    remove()
                end
            end,
        }
        return items
    end

    show_entries_arrange = function(parent)
        local list = parent and parent.children or cfg.entries
        if type(list) ~= "table" then
            if parent then
                parent.children = {}
                list = parent.children
            else
                cfg.entries = {}
                list = cfg.entries
            end
        end
        local ZenArrangeList = require("common/ui/zen_arrange_list")
        local sort_items = {}
        for _i, entry in ipairs(list) do
            sort_items[#sort_items + 1] = {
                text_func = function()
                    return Model.display_label(entry)
                end,
                orig_entry = entry,
                sub_title = Model.display_label(entry),
                sub_item_table_func = function()
                    return build_entry_items(entry, parent)
                end,
            }
        end
        if #sort_items == 0 then
            local InfoMessage = require("ui/widget/infomessage")
            UIManager:show(InfoMessage:new{ text = _("No entries") })
            return
        end
        ZenArrangeList.show{
            title = parent and parent.label or _("Entries"),
            item_table = sort_items,
            callback = function()
                local reordered = {}
                for _i, item in ipairs(sort_items) do
                    if item.orig_entry then
                        reordered[#reordered + 1] = item.orig_entry
                    end
                end
                if parent then
                    parent.children = reordered
                else
                    cfg.entries = reordered
                end
                save_app_launcher()
            end,
        }
    end

    local root_items = add_items(nil)
    root_items[#root_items + 1] = {
        text = _("Add folder"),
        keep_menu_open = true,
        callback = add_folder,
    }
    root_items[#root_items + 1] = {
        text = _("Entries"),
        separator = true,
        keep_menu_open = true,
        callback = function()
            show_entries_arrange(nil)
        end,
    }

    return {
        text = _("App Launcher"),
        sub_item_table = root_items,
    }
end

return M
