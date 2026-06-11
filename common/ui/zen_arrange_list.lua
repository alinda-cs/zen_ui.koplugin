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

local function update_dynamic_text(items)
    if type(items) ~= "table" then return end
    for _i, item in ipairs(items) do
        if type(item.text_func) == "function" then
            item.text = item.text_func()
        end
    end
end

local function refresh_after_callbacks(items, refresh)
    if type(items) ~= "table" or type(refresh) ~= "function" then return end
    for _i, item in ipairs(items) do
        if type(item.callback) == "function" and not item._zen_arrange_refresh_wrapped then
            local orig_callback = item.callback
            item.callback = function(...)
                local result = orig_callback(...)
                refresh()
                return result
            end
            item._zen_arrange_refresh_wrapped = true
        end
        refresh_after_callbacks(item.sub_item_table, refresh)
    end
end

local function show_submenu(title, items, refresh)
    if type(items) ~= "table" or #items == 0 then return end
    update_dynamic_text(items)

    local sort_widget
    local function refresh_lists()
        update_dynamic_text(items)
        if sort_widget then sort_widget:_populateItems() end
        if refresh then refresh() end
    end

    refresh_after_callbacks(items, refresh_lists)
    sort_widget = SortWidget:new{
        title = title,
        item_table = items,
        sort_disabled = true,
    }

    suppress_footer_cancel(sort_widget.footer_cancel)

    local orig_populate = sort_widget._populateItems
    sort_widget._populateItems = function(self, ...)
        update_dynamic_text(self.item_table)
        local result = orig_populate(self, ...)
        suppress_footer_cancel(self.footer_cancel)
        return result
    end

    UIManager:show(sort_widget)
end

local function install_submenu_tap_handlers(sort_widget)
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

function M.show(opts)
    opts = opts or {}
    local item_table = opts.item_table or {}
    update_dynamic_text(item_table)
    for _i, item in ipairs(item_table) do
        if not item.hold_callback
                and (type(item.sub_item_table) == "table"
                    or type(item.sub_item_table_func) == "function") then
            item.hold_callback = function(_item, refresh)
                local sub_items = item.sub_item_table
                if type(item.sub_item_table_func) == "function" then
                    sub_items = item.sub_item_table_func()
                end
                show_submenu(item.sub_title or item.text, sub_items, refresh)
            end
        end
        if item.hold_callback
                and (type(item.sub_item_table) == "table"
                    or type(item.sub_item_table_func) == "function") then
            item._zen_arrange_submenu_on_tap = true
        end
    end

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

    local title_bar = sort_widget.title_bar
    if title_bar and title_bar.left_button then
        local button = title_bar.left_button
        button:setIcon(opts.icon or "zen_ui")
        button.allow_flash = false
        button.callback = function() return true end
        button.hold_callback = false
        button.onTapIconButton = function() return true end
        button.onHoldIconButton = function() return true end
        button.onHoldReleaseIconButton = function() return true end
    end

    sync_footer_cancel(sort_widget)
    install_submenu_tap_handlers(sort_widget)
    local orig_populate = sort_widget._populateItems
    sort_widget._populateItems = function(self, ...)
        update_dynamic_text(self.item_table)
        local result = orig_populate(self, ...)
        sync_footer_cancel(self)
        install_submenu_tap_handlers(self)
        return result
    end

    UIManager:show(sort_widget)
    return sort_widget
end

return M
