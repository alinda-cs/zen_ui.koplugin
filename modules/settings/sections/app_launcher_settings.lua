local _ = require("gettext")
local T = require("ffi/util").template
local UIManager = require("ui/uimanager")
local icons = require("common/inline_icon_map")
local IconItem = require("common/ui/icon_menu_item")

local Model = require("modules/menu/app_launcher/model")
local PluginScan = require("modules/menu/app_launcher/plugin_scan")

local M = {}
local DEFAULT_ENTRY_ICON = "lightning"
local DEFAULT_FOLDER_ICON = "folder_open"

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
        Model.save(cfg)
        if ctx.apply_feature then
            ctx.apply_feature("app_launcher")
        else
            save_and_apply("app_launcher")
        end
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

    local function action_label(entry)
        if ok_disp and entry.action and next(entry.action) then
            local text = Dispatcher:menuTextFunc(entry.action)
            if text and text ~= "" and text ~= _("Nothing") then
                return text
            end
        end
        return nil
    end

    local function sync_action_label(entry)
        if entry.type ~= "action" then return end
        local current = entry.label or ""
        if entry.label_auto == true or current == "" or current == _("Action") then
            entry.label = action_label(entry) or _("Action")
            entry.label_auto = true
        end
    end

    local function prompt_label(entry, title)
        local InputDialog = require("ui/widget/inputdialog")
        local dialog
        dialog = InputDialog:new{
            title = title,
            input = entry.label or "",
            input_hint = entry.type == "action" and _("Leave empty to use action title") or nil,
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
                            entry.label_auto = false
                            save_app_launcher()
                        elseif entry.type == "action" then
                            entry.label_auto = true
                            sync_action_label(entry)
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

    local function current_list(parent)
        if parent then
            if type(parent.children) ~= "table" then
                parent.children = {}
            end
            return parent.children
        end
        if type(cfg.entries) ~= "table" then
            cfg.entries = {}
        end
        return cfg.entries
    end

    local function entry_exists_in_list(list, entry)
        if not (list and entry and entry.id) then return false end
        for _i, candidate in ipairs(list) do
            if candidate.id == entry.id then
                return true
            end
        end
        return false
    end

    local function new_action_entry(label)
        return {
            id = Model.next_id(cfg),
            type = "action",
            label = label or _("Action"),
            label_auto = true,
            icon = DEFAULT_ENTRY_ICON,
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
                            icon = DEFAULT_FOLDER_ICON,
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
        local picker_items = {}
        for _i, plugin in ipairs(found) do
            picker_items[#picker_items + 1] = {
                text = plugin.title,
                plugin = plugin,
            }
        end
        local show_menu_picker = require("common/ui/zen_menu_picker")
        show_menu_picker{
            title = _("Choose plugin menu"),
            items = picker_items,
            on_select = function(item)
                local plugin = item.plugin
                local entry = {
                    id = Model.next_id(cfg),
                    type = "plugin",
                    label = plugin.title,
                    icon = DEFAULT_ENTRY_ICON,
                    plugin = { key = plugin.key, method = plugin.method },
                }
                insert_entry(entry, folder)
                UIManager:nextTick(function()
                    open_entry_settings(touch_menu, entry, folder)
                end)
            end,
        }
    end

    local function choose_plugin_entry(entry, touch_menu)
        local found = PluginScan.scan()
        if #found == 0 then
            local InfoMessage = require("ui/widget/infomessage")
            UIManager:show(InfoMessage:new{ text = _("No launchable plugin menus found") })
            return
        end
        local picker_items = {}
        for _i, plugin in ipairs(found) do
            picker_items[#picker_items + 1] = {
                text = plugin.title,
                plugin = plugin,
            }
        end
        local show_menu_picker = require("common/ui/zen_menu_picker")
        show_menu_picker{
            title = _("Choose plugin menu"),
            items = picker_items,
            on_select = function(item)
                local plugin = item.plugin
                entry.type = "plugin"
                entry.plugin = { key = plugin.key, method = plugin.method }
                entry.label = plugin.title
                save_app_launcher()
                if touch_menu and touch_menu.updateItems then
                    touch_menu:updateItems(1)
                end
            end,
        }
    end

    local function add_items(folder)
        return {
            IconItem.decorate({
                text = _("Add action"),
                keep_menu_open = true,
                callback = function(touch_menu)
                    local entry = add_action(folder)
                    open_entry_settings(touch_menu, entry, folder)
                end,
            }, icons.action),
            IconItem.decorate({
                text = _("Add plugin"),
                keep_menu_open = true,
                callback = function(touch_menu)
                    add_plugin(folder, touch_menu)
                end,
            }, icons.plugin),
        }
    end

    local function arrange_add_items(folder)
        local items = {
            IconItem.decorate({
                text = _("Action"),
                keep_menu_open = true,
                callback = function(touch_menu)
                    local entry = add_action(folder)
                    open_entry_settings(touch_menu, entry, folder)
                end,
            }, icons.action),
            IconItem.decorate({
                text = _("Plugin"),
                keep_menu_open = true,
                callback = function(touch_menu)
                    add_plugin(folder, touch_menu)
                end,
            }, icons.plugin),
        }
        if not folder then
            items[#items + 1] = IconItem.decorate({
                text = _("Folder"),
                keep_menu_open = true,
                callback = add_folder,
            }, icons.new_folder)
        end
        return items
    end

    local function build_action_picker(entry)
        if not ok_disp then return nil end
        local dispatch_items = {}
        local caller = setmetatable({}, {
            __newindex = function(t, key, value)
                if key == "updated" and value then
                    sync_action_label(entry)
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
        return IconItem.decorate({
            text_func = function()
                if entry.action and next(entry.action) then
                    return T(_("Action: %1"), Dispatcher:menuTextFunc(entry.action))
                end
                return _("Action: (none)")
            end,
            keep_menu_open = true,
            sub_item_table = dispatch_items,
        }, icons.action)
    end

    local function build_move_items(entry, parent)
        local items = {}
        if entry.type ~= "folder" then
            local folder_choices = {}
            for _i, candidate in ipairs(cfg.entries) do
                if candidate.type == "folder" and not (parent and candidate.id == parent.id) then
                    folder_choices[#folder_choices + 1] = candidate
                end
            end
            if parent then
                items[#items + 1] = IconItem.decorate({
                    text = _("Move out of folder"),
                    callback = function(touch_menu)
                        if Model.move_to_root(cfg.entries, entry.id) then
                            save_app_launcher()
                            if touch_menu then touch_menu:backToUpperMenu() end
                        end
                    end,
                }, icons.move)
            end
            if #folder_choices > 0 then
                items[#items + 1] = IconItem.decorate({
                    text = _("Move to folder"),
                    keep_menu_open = true,
                    callback = function(touch_menu)
                        local ButtonDialog = require("ui/widget/buttondialog")
                        local dialog
                        local buttons = {}
                        for _i, folder in ipairs(folder_choices) do
                            local folder_id = folder.id
                            buttons[#buttons + 1] = {{
                                text = folder.label,
                                callback = function()
                                    UIManager:close(dialog)
                                    if Model.move_to_folder(cfg.entries, entry.id, folder_id) then
                                        save_app_launcher()
                                        if touch_menu then touch_menu:backToUpperMenu() end
                                    end
                                end,
                            }}
                        end
                        dialog = ButtonDialog:new{
                            title = _("Move to folder"),
                            title_align = "center",
                            width_factor = 0.85,
                            buttons = buttons,
                        }
                        UIManager:show(dialog)
                    end,
                }, icons.move)
            end
        end
        return items
    end

    build_entry_items = function(entry, parent)
        local items = {}
        local function add_icon_item()
            items[#items + 1] = IconItem.decorate({
                text_func = function()
                    return T(_("Icon: %1"), entry.icon or DEFAULT_ENTRY_ICON)
                end,
                keep_menu_open = true,
                callback = function(touch_menu)
                    show_icon_picker(entry, touch_menu)
                end,
            }, icons.icon)
        end
        local function add_label_item()
            items[#items + 1] = IconItem.decorate({
                text_func = function()
                    return T(_("Label: %1"), entry.label)
                end,
                keep_menu_open = true,
                callback = function()
                    prompt_label(entry, _("Launcher label"))
                end,
            }, icons.label)
        end
        if entry.type == "action" then
            local picker = build_action_picker(entry)
            if picker then items[#items + 1] = picker end
            add_icon_item()
            add_label_item()
        elseif entry.type == "folder" then
            add_label_item()
            add_icon_item()
            items[#items + 1] = IconItem.decorate({
                text = _("Folder buttons"),
                keep_menu_open = true,
                callback = function()
                    show_entries_arrange(entry)
                end,
            }, icons.folder_open)
            local add_sub = add_items(entry)
            for _i, item in ipairs(add_sub) do
                items[#items + 1] = item
            end
        else
            items[#items + 1] = IconItem.decorate({
                text_func = function()
                    return T(_("Plugin: %1"), entry.label or _("(none)"))
                end,
                keep_menu_open = true,
                callback = function(touch_menu)
                    choose_plugin_entry(entry, touch_menu)
                end,
            }, icons.plugin)
            add_label_item()
            add_icon_item()
        end
        local move_items = build_move_items(entry, parent)
        for _i, item in ipairs(move_items) do
            items[#items + 1] = item
        end
        items[#items + 1] = IconItem.decorate({
            text = _("Delete"),
            separator = true,
            callback = function(touch_menu)
                local ConfirmBox = require("ui/widget/confirmbox")
                local function remove()
                    Model.remove_by_id(cfg.entries, entry.id)
                    save_app_launcher()
                    if touch_menu then touch_menu:backToUpperMenu() end
                end
                UIManager:show(ConfirmBox:new{
                    text = entry.type == "folder" and entry.children and #entry.children > 0
                        and _("Delete this folder and its buttons?") or _("Delete this button?"),
                    ok_text = _("Delete"),
                    ok_callback = remove,
                })
            end,
        }, icons.delete)
        return items
    end

    show_entries_arrange = function(parent)
        local list = current_list(parent)
        local ZenArrangeList = require("common/ui/zen_arrange_list")
        local sort_items
        local function build_sort_items()
            local items = {}
            list = current_list(parent)
            for _i, entry in ipairs(list) do
                items[#items + 1] = {
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
            sort_items = items
            return items
        end
        sort_items = build_sort_items()
        ZenArrangeList.show{
            title = parent and parent.label or _("Buttons"),
            item_table = sort_items,
            add_title = _("Add"),
            add_item_table = arrange_add_items(parent),
            callback = function()
                list = current_list(parent)
                local reordered = {}
                local reordered_ids = {}
                for _i, item in ipairs(sort_items) do
                    if entry_exists_in_list(list, item.orig_entry) then
                        reordered[#reordered + 1] = item.orig_entry
                        reordered_ids[item.orig_entry.id] = true
                    end
                end
                for _i, entry in ipairs(list) do
                    if entry.id and not reordered_ids[entry.id] then
                        reordered[#reordered + 1] = entry
                    end
                end
                if parent then
                    parent.children = reordered
                else
                    cfg.entries = reordered
                end
                save_app_launcher()
            end,
            refresh_func = build_sort_items,
        }
    end

    local root_items = {
        {
            text = _("Enable"),
            checked_func = function()
                return config.features.app_launcher == true
            end,
            callback = function(touch_menu)
                config.features.app_launcher = config.features.app_launcher ~= true
                save_and_apply("app_launcher")
                if touch_menu and touch_menu.closeMenu then
                    touch_menu:closeMenu()
                end
            end,
        },
        {
            text = _("Buttons") .. " \u{25B8}",
            separator = true,
            keep_menu_open = true,
            callback = function()
                show_entries_arrange(nil)
            end,
        },
        {
            text = _("Show labels"),
            checked_func = function()
                return cfg.show_labels ~= false
            end,
            callback = function(touch_menu)
                cfg.show_labels = cfg.show_labels == false
                save_app_launcher()
                if touch_menu and touch_menu.updateItems then
                    touch_menu:updateItems(1)
                end
            end,
        },
        {
            text = _("Center align buttons"),
            checked_func = function()
                return cfg.center_icons == true
            end,
            callback = function(touch_menu)
                cfg.center_icons = cfg.center_icons ~= true
                save_app_launcher()
                if touch_menu and touch_menu.updateItems then
                    touch_menu:updateItems(1)
                end
            end,
        },
    }

    return {
        text = _("Launcher"),
        sub_item_table = root_items,
    }
end

return M
