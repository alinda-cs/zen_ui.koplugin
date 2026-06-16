local SortWidget = require("ui/widget/sortwidget")
local UIManager = require("ui/uimanager")

local M = {}

local function suppress_footer_cancel(button)
    if not button then return end
    button:disableWithoutDimming()
    button.callback = function() return true end
    button.onTapSelectButton = function() return true end
    button.onHoldSelectButton = function() return true end
    button.hidden = false
    button:hide()
end

local function toggle_sort_item(sort_widget, item)
    if not (sort_widget and item and item.checked_func and item.callback) then
        return false
    end
    item:callback()
    if sort_widget.marked and sort_widget.marked > 0 then
        sort_widget.marked = 0
    end
    sort_widget:_populateItems()
    return true
end

local function get_marked_item(sort_widget)
    local idx = sort_widget and sort_widget.marked
    if type(idx) ~= "number" or idx <= 0 then return nil end
    return sort_widget.item_table and sort_widget.item_table[idx]
end

local function get_focused_item(sort_widget)
    local focused = sort_widget and sort_widget.getFocusItem and sort_widget:getFocusItem()
    return focused and focused.item
end

local function sync_footer_cancel(sort_widget)
    local button = sort_widget and sort_widget.footer_cancel
    local item = get_marked_item(sort_widget)
    if not (button and item and item.checked_func and item.callback and item.checked_func()) then
        suppress_footer_cancel(button)
        return
    end
    button:show()
    button:enable()
    button.onTapSelectButton = nil
    button.onHoldSelectButton = nil
    button.onHoldReleaseSelectButton = nil
    button.callback = function()
        return toggle_sort_item(sort_widget, item)
    end
end

local function hide_button_icon(button)
    if not button then return end
    if button._zen_arrange_callback == nil then
        button._zen_arrange_callback = button.callback
        button._zen_arrange_on_tap = button.onTapSelectButton
        button._zen_arrange_on_hold = button.onHoldSelectButton
        button._zen_arrange_on_hold_release = button.onHoldReleaseSelectButton
    end
    button:disableWithoutDimming()
    button.callback = function() return true end
    button.onTapSelectButton = function() return true end
    button.onHoldSelectButton = function() return true end
    button.onHoldReleaseSelectButton = function() return true end
    button.hidden = false
    button:hide()
end

local function restore_button_icon(button)
    if not button then return end
    if button._zen_arrange_callback ~= nil then
        button.callback = button._zen_arrange_callback
        button.onTapSelectButton = button._zen_arrange_on_tap
        button.onHoldSelectButton = button._zen_arrange_on_hold
        button.onHoldReleaseSelectButton = button._zen_arrange_on_hold_release
    end
    button:show()
end

local function suppress_footer_jump_buttons(sort_widget)
    if not sort_widget then return end
    local moving = sort_widget.marked and sort_widget.marked > 0
    if moving then
        restore_button_icon(sort_widget.footer_first_up)
        restore_button_icon(sort_widget.footer_last_down)
        return
    end

    hide_button_icon(sort_widget.footer_first_up)
    hide_button_icon(sort_widget.footer_last_down)
end

local function configure_title_bar(sort_widget)
    local title_bar = sort_widget and sort_widget.title_bar
    if not title_bar then return end

    local left_button = title_bar.left_button
    if left_button then
        left_button:setIcon("chevron.left")
        left_button.allow_flash = false
        left_button.callback = function()
            return sort_widget:onClose()
        end
        left_button.hold_callback = false
        left_button.onHoldIconButton = function() return true end
        left_button.onHoldReleaseIconButton = function() return true end
    end

    local right_button = title_bar.right_button
    if right_button then
        right_button.enabled = false
        right_button.callback = nil
        right_button.hold_callback = false
        right_button.allow_flash = false
        right_button.onTapIconButton = function() return true end
        right_button.onHoldIconButton = function() return true end
        right_button.onHoldReleaseIconButton = function() return true end
        if right_button.image then
            right_button.image.hide = true
        end
    end
end

local SUBMENU_CARET = " \u{25B8}"
local ASCII_SUBMENU_CARET = " >"
local OLD_SUBMENU_CARET = string.char(226, 150, 184)

local function strip_submenu_caret(text)
    if type(text) ~= "string" then return text end
    if text:sub(-#SUBMENU_CARET) == SUBMENU_CARET then
        return text:sub(1, -#SUBMENU_CARET - 1)
    end
    if text:sub(-#ASCII_SUBMENU_CARET) == ASCII_SUBMENU_CARET then
        return text:sub(1, -#ASCII_SUBMENU_CARET - 1)
    end
    if text:sub(-#OLD_SUBMENU_CARET) == OLD_SUBMENU_CARET then
        return (text:sub(1, -#OLD_SUBMENU_CARET - 1):gsub("%s+$", ""))
    end
    return text
end

local function has_submenu(item)
    return type(item) == "table"
        and (type(item.sub_item_table) == "table"
            or type(item.sub_item_table_func) == "function")
end

local function item_base_text(item)
    if type(item) ~= "table" then return nil end
    if type(item.text_func) == "function" then
        return strip_submenu_caret(item.text_func())
    end
    if item._zen_arrange_base_text == nil then
        item._zen_arrange_base_text = strip_submenu_caret(item.text)
    end
    return item._zen_arrange_base_text
end

local function item_submenu_title(item)
    return item.sub_title or item_base_text(item) or item.text
end

local function update_dynamic_text(items)
    if type(items) ~= "table" then return end
    for _i, item in ipairs(items) do
        local text = item_base_text(item)
        if has_submenu(item) and type(text) == "string" then
            item.text = text .. SUBMENU_CARET
        elseif text ~= nil then
            item.text = text
        end
    end
end

local function refresh_after_callbacks(items, refresh, menu_proxy)
    if type(items) ~= "table" or type(refresh) ~= "function" then return end
    for _i, item in ipairs(items) do
        if type(item.callback) == "function" and not item._zen_arrange_refresh_wrapped then
            local orig_callback = item.callback
            item.callback = function(...)
                local result = orig_callback(menu_proxy, select(2, ...))
                refresh()
                return result
            end
            item._zen_arrange_refresh_wrapped = true
        end
        refresh_after_callbacks(item.sub_item_table, refresh, menu_proxy)
    end
end

local show_submenu
local install_submenu_tap_handlers
local install_root_tap_handlers

local function ensure_submenu_callbacks(items)
    if type(items) ~= "table" then return end
    for _i, item in ipairs(items) do
        if not item.hold_callback and has_submenu(item) then
            local submenu_item = item
            item.hold_callback = function(_item, refresh)
                local sub_items = submenu_item.sub_item_table
                if type(submenu_item.sub_item_table_func) == "function" then
                    sub_items = submenu_item.sub_item_table_func()
                end
                show_submenu(item_submenu_title(submenu_item), sub_items, refresh)
            end
        end
        if item.hold_callback and has_submenu(item) then
            item._zen_arrange_submenu_on_tap = true
        end
        ensure_submenu_callbacks(item.sub_item_table)
    end
end

show_submenu = function(title, items, refresh)
    if type(items) ~= "table" or #items == 0 then return end
    ensure_submenu_callbacks(items)
    update_dynamic_text(items)

    local sort_widget
    local menu_proxy
    local function refresh_lists()
        if menu_proxy and type(menu_proxy.item_table) == "table" and menu_proxy.item_table ~= items then
            items = menu_proxy.item_table
        end
        ensure_submenu_callbacks(items)
        update_dynamic_text(items)
        refresh_after_callbacks(items, refresh_lists, menu_proxy)
        if sort_widget then
            sort_widget.item_table = items
            sort_widget:_populateItems()
        end
        if refresh then refresh() end
    end

    menu_proxy = {
        item_table = items,
        updateItems = function(self)
            if type(self.item_table) == "table" then
                items = self.item_table
            end
            refresh_lists()
        end,
    }
    refresh_after_callbacks(items, refresh_lists, menu_proxy)
    sort_widget = SortWidget:new{
        title = title,
        item_table = items,
        sort_disabled = false,
    }
    sort_widget.sort_disabled = true

    configure_title_bar(sort_widget)
    suppress_footer_cancel(sort_widget.footer_cancel)
    suppress_footer_jump_buttons(sort_widget)
    install_submenu_tap_handlers(sort_widget)

    local orig_populate = sort_widget._populateItems
    sort_widget._populateItems = function(self, ...)
        update_dynamic_text(self.item_table)
        local result = orig_populate(self, ...)
        suppress_footer_cancel(self.footer_cancel)
        suppress_footer_jump_buttons(self)
        install_submenu_tap_handlers(self)
        return result
    end

    UIManager:show(sort_widget)
end

install_submenu_tap_handlers = function(sort_widget)
    if not sort_widget or not sort_widget.main_content then return end
    for _i, child in ipairs(sort_widget.main_content) do
        local item = type(child) == "table" and child.item or nil
        if item and item._zen_arrange_submenu_on_tap and not child._zen_arrange_submenu_tap_patched then
            child._zen_arrange_submenu_tap_patched = true
            child.onTap = function(row, _arg, ges)
                if item.checked_func and row.checkmark_widget and ges and ges.pos
                        and ges.pos:intersectWith(row.checkmark_widget.dimen) then
                    if item.callback then
                        item:callback()
                    end
                    row.show_parent:_populateItems()
                    return true
                end
                if item.hold_callback then
                    item:hold_callback(function()
                        row.show_parent:_populateItems()
                    end)
                end
                return true
            end
        end
    end
end

install_root_tap_handlers = function(sort_widget)
    if not sort_widget or not sort_widget.main_content then return end
    for _i, child in ipairs(sort_widget.main_content) do
        local item = type(child) == "table" and child.item or nil
        if item and item._zen_arrange_submenu_on_tap and not child._zen_arrange_root_tap_patched then
            child._zen_arrange_root_tap_patched = true
            child.onTap = function(row, _arg, ges)
                if item.checked_func and row.checkmark_widget and ges and ges.pos
                        and ges.pos:intersectWith(row.checkmark_widget.dimen) then
                    if item.callback then
                        item:callback()
                    end
                    row.show_parent:_populateItems()
                    return true
                end
                if row.show_parent.marked == row.index then
                    if item.hold_callback then
                        item:hold_callback(function()
                            row.show_parent:_populateItems()
                        end)
                    end
                else
                    row.show_parent.marked = row.index
                    row.show_parent:_populateItems()
                end
                return true
            end
        end
    end
end

function M.show(opts)
    opts = opts or {}
    local item_table = opts.item_table or {}
    update_dynamic_text(item_table)
    ensure_submenu_callbacks(item_table)

    local sort_widget = SortWidget:new{
        title = opts.title or "",
        item_table = item_table,
        callback = opts.callback,
    }

    local orig_on_press = sort_widget.onPress
    sort_widget.onPress = function(self)
        if toggle_sort_item(self, get_focused_item(self)) then return true end
        return orig_on_press and orig_on_press(self)
    end
    sort_widget.key_events = sort_widget.key_events or {}
    sort_widget.key_events.ZenArrangeToggleReturn = {
        { "Return" },
        event = "ZenArrangeToggle",
    }
    sort_widget.onZenArrangeToggle = function(self)
        if toggle_sort_item(self, get_focused_item(self)) then return true end
        return self:onReturn()
    end

    configure_title_bar(sort_widget)
    sync_footer_cancel(sort_widget)
    suppress_footer_jump_buttons(sort_widget)
    install_root_tap_handlers(sort_widget)
    local orig_populate = sort_widget._populateItems
    sort_widget._populateItems = function(self, ...)
        update_dynamic_text(self.item_table)
        local result = orig_populate(self, ...)
        sync_footer_cancel(self)
        suppress_footer_jump_buttons(self)
        install_root_tap_handlers(self)
        return result
    end

    UIManager:show(sort_widget)
    return sort_widget
end

return M
