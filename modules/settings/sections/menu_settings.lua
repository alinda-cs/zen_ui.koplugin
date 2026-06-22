-- settings/sections/menu.lua
-- Touch menu settings items for Zen UI (Quick Settings panel).
-- Receives ctx: { plugin, config, save_and_apply }

local _ = require("gettext")
local T = require("ffi/util").template
local UIManager = require("ui/uimanager")
local defaults = require("config/defaults")

local M = {}

function M.build(ctx)
    local config = ctx.config
    local save_and_apply = ctx.save_and_apply

    local function save_and_apply_quick_settings() save_and_apply("quick_settings") end

    -- Resolve UI instance once for plugin-availability checks (fail-open if nil).
    local _ui
    do
        local ok_f, FM = pcall(require, "apps/filemanager/filemanager")
        local ok_r, RU = pcall(require, "apps/reader/readerui")
        _ui = (ok_f and FM.instance) or (ok_r and RU.instance)
    end
    -- Returns true when the plugin slot exists on the UI, or when the UI is
    -- unavailable (fail-open so we never silently hide a reachable button).
    local function hasPlugin(slot)
        return _ui == nil or _ui[slot] ~= nil
    end

    local quick_button_items = {
        { key = "wifi",    text = _("Wi-Fi")       },
        { key = "night",   text = _("Night mode")  },
        { key = "zen",     text = _("Zen mode")    },
        { key = "lockdown",text = _("Lockdown")    },
        { key = "rotate",  text = _("Rotate")      },
        { key = "usb",     text = _("USB")         },
        { key = "search",  text = _("File search") },
        { key = "restart", text = _("Restart")     },
        { key = "exit",    text = _("Exit")        },
        { key = "sleep",   text = _("Sleep")       },
        -- Optional: only shown when the plugin/feature is detected.
        { key = "quickrss",       text = _("QuickRSS"),        detect = function() local ok = pcall(require, "modules/ui/feed_view"); return ok end },
        { key = "cloud",          text = _("Cloud storage") },
        { key = "zlibrary",       text = _("Z-Library"),       detect = function() return hasPlugin("zlibrary") end },
        { key = "calibre",        text = _("Calibre"),         detect = function() return hasPlugin("calibre") end },
        { key = "calibre_search", text = _("Calibre Search"),  detect = function() return hasPlugin("calibre") end },
        { key = "notion",         text = _("Notion"),          detect = function() return hasPlugin("NotionSync") end },
        { key = "streak",         text = _("Streak"),          detect = function() return hasPlugin("readingstreak") end },
        { key = "opds",           text = _("OPDS"),            detect = function() return hasPlugin("opds") end },
        { key = "localsend",      text = _("LocalSend"),       detect = function() return hasPlugin("localsend") end },
        { key = "filebrowser",    text = _("Filebrowser"),     detect = function() return hasPlugin("filebrowser") end },
        { key = "puzzle",         text = _("Slide Puzzle"),    detect = function() return hasPlugin("slidepuzzle") end },
        { key = "crossword",      text = _("Crossword"),       detect = function() return hasPlugin("crossword") end },
        { key = "connections",    text = _("Connections"),      detect = function() return hasPlugin("nytconnections") end },
        { key = "chess",          text = _("Chess"),            detect = function() return hasPlugin("kochess") end },
        { key = "casualchess",    text = _("Casual Chess"),     detect = function() return hasPlugin("casualkochess") end },
        { key = "stats_progress", text = _("Stats: Progress"), detect = function() return hasPlugin("statistics") end },
        { key = "stats_calendar", text = _("Stats: Calendar"), detect = function() return hasPlugin("statistics") end },
        { key = "battery_stats",  text = _("Battery Stats"),   detect = function() return hasPlugin("batterystat") end },
        { key = "kosync",         text = _("Sync") },
        { key = "screenshot",     text = _("Screenshot") },
    }

    -- Remove any button whose plugin/feature is not detected.
    do
        local filtered = {}
        for _i, item in ipairs(quick_button_items) do
            if not item.detect or item.detect() then
                filtered[#filtered + 1] = item
            end
        end
        quick_button_items = filtered
    end

    table.sort(quick_button_items, function(a, b) return a.text < b.text end)

    local quick_button_label_by_id = {}
    for _i, quick_item in ipairs(quick_button_items) do
        quick_button_label_by_id[quick_item.key] = quick_item.text
    end

    local quick_buttons_max = 9

    local rotate_action_options = {
        { key = "cycle", text = _("Cycle") },
        { key = "90",    text = _("90°")   },
        { key = "180",   text = _("180°")  },
        { key = "270",   text = _("270°")  },
    }

    local rotate_action_labels = {}
    for _i, item in ipairs(rotate_action_options) do
        rotate_action_labels[item.key] = item.text
    end

    local function getRotateAction()
        local action = config.quick_settings.rotate_action
        return rotate_action_labels[action] and action or "cycle"
    end

    local function getRotateActionLabel()
        return rotate_action_labels[getRotateAction()]
    end

    -- only count buttons that are actually toggleable in the UI
    local quick_button_key_set = {}
    for _i, item in ipairs(quick_button_items) do
        quick_button_key_set[item.key] = true
    end

    -- Register custom buttons so they appear in arrange widget and count toward limit
    local ok_disp, Dispatcher = pcall(require, "dispatcher")
    if type(config.quick_settings.custom_buttons) == "table" then
        for _i, cb in ipairs(config.quick_settings.custom_buttons) do
            if type(cb.id) == "string" then
                local lbl
                if cb.label and cb.label ~= "" then
                    lbl = cb.label
                elseif ok_disp and cb.action and next(cb.action) then
                    lbl = Dispatcher:menuTextFunc(cb.action)
                end
                quick_button_label_by_id[cb.id] = lbl or _("Custom")
                quick_button_key_set[cb.id] = true
            end
        end
    end

    local function countEnabledButtons()
        local count = 0
        for key, v in pairs(config.quick_settings.show_buttons) do
            if v == true and quick_button_key_set[key] then count = count + 1 end
        end
        return count
    end

    local function buildRotateButtonSubItems()
        local items = {}
        for _i, item in ipairs(rotate_action_options) do
            local key = item.key
            table.insert(items, {
                text = item.text,
                radio = true,
                checked_func = function()
                    return getRotateAction() == key
                end,
                callback = function()
                    config.quick_settings.rotate_action = key
                    save_and_apply_quick_settings()
                end,
            })
        end
        return items
    end

    local function toggleQuickButton(id)
        if config.quick_settings.show_buttons[id] == true then
            config.quick_settings.show_buttons[id] = false
        else
            if countEnabledButtons() >= quick_buttons_max then
                local InfoMessage = require("ui/widget/infomessage")
                UIManager:show(InfoMessage:new{
                    text = _("Maximum 9 buttons allowed"),
                })
                return false
            end
            config.quick_settings.show_buttons[id] = true
        end
        save_and_apply_quick_settings()
        return true
    end

    local function showButtonsArrange()
        local ZenArrangeList = require("common/ui/zen_arrange_list")
        local sort_items = {}
        local function shouldDimButton(id)
            return config.quick_settings.show_buttons[id] ~= true
                and countEnabledButtons() >= quick_buttons_max
        end
        local function updateDimStates()
            for _i, sort_item in ipairs(sort_items) do
                sort_item.dim = shouldDimButton(sort_item.orig_item)
            end
        end
        for _i, id in ipairs(config.quick_settings.button_order) do
            local label = quick_button_label_by_id[id]
            if label then
                local item = {
                    text = label,
                    orig_item = id,
                    dim = shouldDimButton(id),
                    checked_func = function()
                        return config.quick_settings.show_buttons[id] == true
                    end,
                    callback = function()
                        if toggleQuickButton(id) then
                            updateDimStates()
                        end
                    end,
                }
                if id == "rotate" then
                    item.text_func = function()
                        return T(_("Rotate: %1"), getRotateActionLabel()) .. " \u{25B8}"
                    end
                    item.sub_title = _("Rotate")
                    item.sub_item_table_func = buildRotateButtonSubItems
                end
                table.insert(sort_items, item)
            end
        end
        ZenArrangeList.show{
            title = _("Buttons"),
            item_table = sort_items,
            callback = function()
                -- Replace the table to avoid leaving stale trailing entries
                local new_order = {}
                local in_sort = {}
                for _i, item in ipairs(sort_items) do
                    table.insert(new_order, item.orig_item)
                    in_sort[item.orig_item] = true
                end
                -- Preserve any orphaned entries not shown in the sort widget
                for _i, id in ipairs(config.quick_settings.button_order) do
                    if not in_sort[id] then
                        table.insert(new_order, id)
                    end
                end
                config.quick_settings.button_order = new_order
                save_and_apply_quick_settings()
            end,
        }
    end

    -- Icon list: plugin icons + KOReader user/built-in icons.
    local CUSTOM_BUTTON_ICONS
    local function getCustomButtonIcons()
        if CUSTOM_BUTTON_ICONS then return CUSTOM_BUTTON_ICONS end
        local icon_utils = require("common/utils")
        local ok_root, root = pcall(require, "common/plugin_root")
        local excluded = { zen_ui_light = true, zen_ui_update = true }
        CUSTOM_BUTTON_ICONS = icon_utils.getIconPickerList(ok_root and root or nil, excluded)
        return CUSTOM_BUTTON_ICONS
    end

    local _icon_picker = require("common/ui/zen_icon_picker")
    local function showIconPickerDialog(cb, on_select)
        _icon_picker(getCustomButtonIcons(), cb.icon, on_select)
    end

    local function get_cb_label(cb)
        if cb.label and cb.label ~= "" then return cb.label end
        if ok_disp and cb.action and next(cb.action) then
            local t = Dispatcher:menuTextFunc(cb.action)
            if t ~= _("Nothing") then return t end
        end
        return _("Custom")
    end

    local function build_cb_sub_items(cb)
        local items = {}

        -- Enable/disable toggle
        table.insert(items, {
            text = _("Show in quick settings"),
            separator = true,
            checked_func = function()
                return config.quick_settings.show_buttons[cb.id] ~= false
            end,
            enabled_func = function()
                return config.quick_settings.show_buttons[cb.id] ~= false
                    or countEnabledButtons() < quick_buttons_max
            end,
            callback = function()
                local cur = config.quick_settings.show_buttons[cb.id]
                config.quick_settings.show_buttons[cb.id] = (cur == false)
                save_and_apply_quick_settings()
            end,
        })

        -- Action picker via Dispatcher submenu
        if ok_disp then
            local dispatch_items = {}
            -- Proxy caller: triggers save whenever Dispatcher writes caller.updated = true
            local caller = setmetatable({}, {
                __newindex = function(t, k, v)
                    if k == "updated" and v then
                        save_and_apply_quick_settings()
                    else
                        rawset(t, k, v)
                    end
                end,
                __index = function() return nil end,
            })
            Dispatcher:addSubMenu(caller, dispatch_items, cb, "action")
            table.insert(items, {
                text_func = function()
                    if cb.action and next(cb.action) then
                        return T(_("Action: %1"), Dispatcher:menuTextFunc(cb.action))
                    end
                    return _("Action: (none)")
                end,
                keep_menu_open = true,
                sub_item_table = dispatch_items,
            })
        end

        -- Icon picker
        table.insert(items, {
            text_func = function()
                return T(_("Icon: %1"), cb.icon or "zen_ui")
            end,
            keep_menu_open = true,
            callback = function(tm)
                showIconPickerDialog(cb, function(name)
                    cb.icon = name
                    save_and_apply_quick_settings()
                    -- Refresh the submenu so text_func re-reads cb.icon.
                    if tm and tm.updateItems then tm:updateItems(1) end
                end)
            end,
        })

        -- Optional label override
        table.insert(items, {
            text_func = function()
                local lbl = (cb.label and cb.label ~= "") and cb.label or _("(auto)")
                return T(_("Label: %1"), lbl)
            end,
            keep_menu_open = true,
            callback = function()
                local InputDialog = require("ui/widget/inputdialog")
                local dialog
                dialog = InputDialog:new{
                    title = _("Custom button label"),
                    input = cb.label or "",
                    input_hint = _("Leave empty to use action title"),
                    buttons = {{
                        { text = _("Cancel"), callback = function() UIManager:close(dialog) end },
                        {
                            text = _("Set"),
                            is_enter_default = true,
                            callback = function()
                                local txt = dialog:getInputText()
                                cb.label = (txt and txt ~= "") and txt or nil
                                UIManager:close(dialog)
                                save_and_apply_quick_settings()
                            end,
                        },
                    }},
                }
                UIManager:show(dialog)
            end,
        })

        -- Delete button
        table.insert(items, {
            text = _("Remove this button"),
            separator = true,
            keep_menu_open = true,
            callback = function(touch_menu)
                local cbs = config.quick_settings.custom_buttons
                for i, item in ipairs(cbs) do
                    if item.id == cb.id then
                        table.remove(cbs, i)
                        break
                    end
                end
                config.quick_settings.show_buttons[cb.id] = nil
                local new_order = {}
                for _i, id in ipairs(config.quick_settings.button_order) do
                    if id ~= cb.id then table.insert(new_order, id) end
                end
                config.quick_settings.button_order = new_order
                save_and_apply_quick_settings()
                if touch_menu then touch_menu:backToUpperMenu() end
            end,
        })

        return items
    end

    -- Reset only the enable/disable state of built-in options to defaults.
    -- Custom buttons and their enabled states are preserved.
    local function resetQuickSettings()
        local def = defaults.quick_settings
        -- Rebuild show_buttons from defaults so only default buttons remain enabled.
        local new_show = {}
        for key, val in pairs(def.show_buttons) do
            new_show[key] = val
        end
        -- Keep custom buttons saved but disabled (not part of defaults).
        if type(config.quick_settings.custom_buttons) == "table" then
            for _i, cb in ipairs(config.quick_settings.custom_buttons) do
                new_show[cb.id] = false
            end
        end
        config.quick_settings.show_buttons = new_show
        config.quick_settings.show_frontlight = def.show_frontlight
        config.quick_settings.show_warmth = def.show_warmth
        config.quick_settings.flip_lh_rh_icon = def.flip_lh_rh_icon
        save_and_apply_quick_settings()
    end

    local custom_buttons_item = {
        text = _("Custom buttons"),
        separator = true,
        keep_menu_open = true,
        sub_item_table_func = function()
            local function build()
                local items = {}
                -- Add new custom button
                table.insert(items, {
                    text = _("Add custom button"),
                    keep_menu_open = true,
                    callback = function(touch_menu)
                        local cbs = config.quick_settings.custom_buttons
                        if type(cbs) ~= "table" then
                            config.quick_settings.custom_buttons = {}
                            cbs = config.quick_settings.custom_buttons
                        end
                        -- Pick a unique default label: "Custom", "Custom 2", "Custom 3", ...
                        local taken = {}
                        for _i, b in ipairs(cbs) do
                            local lbl = (b.label and b.label ~= "") and b.label or _("Custom")
                            taken[lbl] = true
                        end
                        local default_label
                        if taken[_("Custom")] then
                            local n = 2
                            while taken[_("Custom") .. " " .. n] do n = n + 1 end
                            default_label = _("Custom") .. " " .. n
                        end
                        config.quick_settings.next_custom_id =
                            (config.quick_settings.next_custom_id or 0) + 1
                        local new_cb = {
                            id     = "cb_" .. config.quick_settings.next_custom_id,
                            label  = default_label,
                            icon   = "zen_ui",
                            action = {},
                        }
                        table.insert(cbs, new_cb)
                        config.quick_settings.show_buttons[new_cb.id] = countEnabledButtons() < quick_buttons_max
                        table.insert(config.quick_settings.button_order, new_cb.id)
                        save_and_apply_quick_settings()
                        -- Navigate into new button's config; list refreshes on back
                        local sub_items = build_cb_sub_items(new_cb)
                        if touch_menu and #sub_items > 0 then
                            table.insert(touch_menu.item_table_stack, touch_menu.item_table)
                            touch_menu.parent_id = nil
                            touch_menu.item_table = sub_items
                            touch_menu:updateItems(1)
                        end
                    end,
                })
                -- Existing custom buttons
                if type(config.quick_settings.custom_buttons) == "table" then
                    for _i, cb in ipairs(config.quick_settings.custom_buttons) do
                        local cb_ref = cb
                        table.insert(items, {
                            text_func = function() return get_cb_label(cb_ref) end,
                            keep_menu_open = true,
                            sub_item_table_func = function()
                                return build_cb_sub_items(cb_ref)
                            end,
                        })
                    end
                end
                -- Refresh this list when backToUpperMenu() is called (after add or remove)
                items.needs_refresh = true
                items.refresh_func = build
                return items
            end
            return build()
        end,
    }

    return {
        text = _("Quick Settings"),
        sub_item_table = {
            {
                text = _("Buttons") .. " \u{25B8}",
                keep_menu_open = true,
                callback = showButtonsArrange,
            },
            custom_buttons_item,
            {
                text = _("Show brightness slider"),
                checked_func = function() return config.quick_settings.show_frontlight == true end,
                callback = function()
                    config.quick_settings.show_frontlight = config.quick_settings.show_frontlight ~= true
                    save_and_apply_quick_settings()
                end,
            },
            {
                text = _("Show warmth slider"),
                checked_func = function() return config.quick_settings.show_warmth == true end,
                callback = function()
                    config.quick_settings.show_warmth = config.quick_settings.show_warmth ~= true
                    save_and_apply_quick_settings()
                end,
            },
            {
                text = _("Flip LH/RH icon"),
                checked_func = function() return config.quick_settings.flip_lh_rh_icon == true end,
                callback = function()
                    config.quick_settings.flip_lh_rh_icon = config.quick_settings.flip_lh_rh_icon ~= true
                    save_and_apply_quick_settings()
                end,
            },
            {
                text = _("Reset to defaults"),
                separator = true,
                keep_menu_open = true,
                callback = function(touch_menu)
                    local ConfirmBox = require("ui/widget/confirmbox")
                    UIManager:show(ConfirmBox:new{
                        text = _("Reset quick settings to defaults?"),
                        ok_text = _("Reset"),
                        ok_callback = function()
                            resetQuickSettings()
                            if touch_menu and touch_menu.updateItems then touch_menu:updateItems() end
                        end,
                    })
                end,
            },
        },
    }
end

return M
