local function apply_app_launcher()
    local Blitbuffer = require("ffi/blitbuffer")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local Device = require("device")
    local Font = require("ui/font")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local Geom = require("ui/geometry")
    local GestureRange = require("ui/gesturerange")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local HorizontalSpan = require("ui/widget/horizontalspan")
    local IconWidget = require("ui/widget/iconwidget")
    local InputContainer = require("ui/widget/container/inputcontainer")
    local TextWidget = require("ui/widget/textwidget")
    local UIManager = require("ui/uimanager")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan = require("ui/widget/verticalspan")
    local _ = require("gettext")

    local Dispatcher = require("dispatcher")
    local Model = require("modules/menu/app_launcher/model")
    local PluginScan = require("modules/menu/app_launcher/plugin_scan")
    local utils = require("common/utils")
    local library_font = require("modules/filebrowser/patches/library_font")

    local zen_plugin = rawget(_G, "__ZEN_UI_PLUGIN")
    if not zen_plugin or type(zen_plugin.config) ~= "table" then
        return
    end

    local Screen = Device.screen
    local _icons_dir
    do
        local root = require("common/plugin_root")
        if root then _icons_dir = root .. "/icons/" end
    end

    local function is_enabled()
        local features = zen_plugin.config and zen_plugin.config.features
        return type(features) == "table" and features.app_launcher == true
    end

    local function icon_spec(name)
        local icon_name = (type(name) == "string" and name ~= "") and name or "app_launcher"
        local icon_path = _icons_dir and utils.resolveIcon(_icons_dir, icon_name)
        return icon_path, icon_name
    end

    local LauncherCell = InputContainer:extend{}

    function LauncherCell:init()
        self.dimen = self.dimen or Geom:new{ w = self.width, h = self.height }
        self.ges_events = {
            TapSelect = {
                GestureRange:new{ ges = "tap", range = self.dimen },
            },
        }
    end

    function LauncherCell:paintTo(bb, x, y)
        self.dimen.x = x
        self.dimen.y = y
        self[1]:paintTo(bb, x, y)
    end

    function LauncherCell:onTapSelect()
        if self.callback then
            self.callback()
        end
        return true
    end

    function LauncherCell:onFocus()
        self.frame.invert = true
        if self.dimen then UIManager:setDirty(nil, "fast", self.dimen) end
        return true
    end

    function LauncherCell:onUnfocus()
        self.frame.invert = false
        if self.dimen then UIManager:setDirty(nil, "fast", self.dimen) end
        return true
    end

    local function make_cell(opts)
        local icon_path, icon_name = icon_spec(opts.icon)
        local icon_size = opts.icon_size
        local label_face = opts.label_face
        local fg = opts.dim and Blitbuffer.COLOR_DARK_GRAY or Blitbuffer.COLOR_BLACK
        local icon = IconWidget:new{
            file = icon_path or nil,
            icon = icon_path and nil or icon_name,
            width = icon_size,
            height = icon_size,
            alpha = true,
        }
        local label = TextWidget:new{
            text = opts.label,
            face = label_face,
            fgcolor = fg,
            max_width = opts.cell_w - opts.pad * 2,
        }
        local content = VerticalGroup:new{
            align = "center",
            VerticalSpan:new{ width = opts.pad },
            icon,
            VerticalSpan:new{ width = Screen:scaleBySize(4) },
            label,
        }
        local frame = FrameContainer:new{
            width = opts.cell_w,
            height = opts.cell_h,
            bordersize = 0,
            background = Blitbuffer.COLOR_WHITE,
            padding = 0,
            CenterContainer:new{
                dimen = Geom:new{ w = opts.cell_w, h = opts.cell_h },
                content,
            },
        }
        local cell = LauncherCell:new{
            width = opts.cell_w,
            height = opts.cell_h,
            dimen = Geom:new{ w = opts.cell_w, h = opts.cell_h },
            callback = opts.callback,
            frame = frame,
            frame,
        }
        return cell
    end

    local function current_entries(touch_menu)
        local cfg = Model.ensure(zen_plugin.config)
        local folder_id = touch_menu._app_launcher_folder_id
        if folder_id then
            local _list, _index, folder = Model.find_by_id(cfg.entries, folder_id)
            if folder and folder.type == "folder" then
                return folder.children or {}, folder
            end
            touch_menu._app_launcher_folder_id = nil
        end
        return cfg.entries, nil
    end

    local function show_unavailable()
        local InfoMessage = require("ui/widget/infomessage")
        UIManager:show(InfoMessage:new{ text = _("Launcher entry is unavailable") })
    end

    local function activate_entry(touch_menu, entry)
        if not entry then return end
        if entry._app_back then
            touch_menu._app_launcher_folder_id = nil
            touch_menu:updateItems(1)
            return
        end
        if entry.type == "folder" then
            touch_menu._app_launcher_folder_id = entry.id
            touch_menu:updateItems(1)
            return
        end
        if entry.type == "action" then
            touch_menu:closeMenu()
            UIManager:nextTick(function()
                if type(entry.action) == "table" and next(entry.action) then
                    Dispatcher:execute(entry.action)
                end
            end)
            return
        end
        if entry.type == "plugin" and type(entry.plugin) == "table" then
            local launch = PluginScan.resolve(entry.plugin.key, entry.plugin.method)
            if not launch then
                show_unavailable()
                return
            end
            touch_menu:closeMenu()
            UIManager:nextTick(function()
                pcall(launch)
            end)
        end
    end

    local function entry_available(entry)
        if entry.type ~= "plugin" then return true end
        local plugin = entry.plugin
        return type(plugin) == "table" and PluginScan.exists(plugin.key, plugin.method)
    end

    local function create_panel(touch_menu)
        local entries, folder = current_entries(touch_menu)
        local panel_width = touch_menu.item_width
        local pad = Screen:scaleBySize(8)
        local inner_w = panel_width - pad * 2
        local min_cell_w = Screen:scaleBySize(96)
        local cols = math.max(2, math.floor(inner_w / min_cell_w))
        local cell_w = math.floor(inner_w / cols)
        local cell_h = Screen:scaleBySize(92)
        local icon_size = Screen:scaleBySize(38)
        local label_size = Font.sizemap and Font.sizemap["xx_smallinfofont"] or 18
        local label_face = library_font.getFace(label_size)
        local rows = {}
        local row_counts = {}
        local layout_rows = {}
        local refs = { buttons = {}, layout_rows = layout_rows }
        local visible = {}

        if folder then
            visible[#visible + 1] = {
                id = "__back",
                label = _("Back"),
                icon = "chevron.left",
                _app_back = true,
            }
        end
        for _i, entry in ipairs(entries or {}) do
            visible[#visible + 1] = entry
        end

        if #visible == 0 then
            touch_menu._qs_refs = refs
            return VerticalGroup:new{
                align = "center",
                VerticalSpan:new{ width = Screen:scaleBySize(16) },
                TextWidget:new{
                    text = _("App Launcher"),
                    face = library_font.getFace(Font.sizemap and Font.sizemap["smallinfofont"] or 22),
                },
                VerticalSpan:new{ width = Screen:scaleBySize(8) },
                TextWidget:new{
                    text = _("No entries yet"),
                    face = label_face,
                },
                VerticalSpan:new{ width = Screen:scaleBySize(16) },
            }
        end

        local panel = VerticalGroup:new{
            align = "left",
            VerticalSpan:new{ width = pad },
        }

        for i, entry in ipairs(visible) do
            local col = ((i - 1) % cols) + 1
            if col == 1 then
                rows[#rows + 1] = HorizontalGroup:new{ align = "top" }
                row_counts[#rows] = 0
                rows[#rows][#rows[#rows] + 1] = HorizontalSpan:new{ width = pad }
                layout_rows[#layout_rows + 1] = {}
            end
            row_counts[#rows] = row_counts[#rows] + 1
            local dim = not entry._app_back and not entry_available(entry)
            local cell = make_cell{
                cell_w = cell_w,
                cell_h = cell_h,
                pad = pad,
                icon_size = icon_size,
                label_face = label_face,
                label = Model.display_label(entry),
                icon = entry.icon or (entry.type == "folder" and "app_menu" or "app_launcher"),
                dim = dim,
                callback = not dim and function()
                    activate_entry(touch_menu, entry)
                end or nil,
            }
            rows[#rows][#rows[#rows] + 1] = cell
            layout_rows[#layout_rows][#layout_rows[#layout_rows] + 1] = cell
            refs.buttons[#refs.buttons + 1] = {
                widget = cell,
                callback = cell.callback and function()
                    cell.callback()
                end or nil,
            }
        end

        for _i, row in ipairs(rows) do
            local used = (row_counts[_i] or 0) * cell_w
            row[#row + 1] = HorizontalSpan:new{ width = math.max(0, panel_width - pad - used) }
            panel[#panel + 1] = row
        end
        panel[#panel + 1] = VerticalSpan:new{ width = pad }
        touch_menu._qs_refs = refs
        return panel
    end

    rawset(_G, "__ZEN_UI_BUILD_APP_LAUNCHER_PREVIEW", function(item_width)
        return create_panel{
            item_width = item_width,
            closeMenu = function() end,
            updateItems = function() end,
        }
    end)

    local app_launcher_tab = {
        id = "app_launcher",
        icon = "app_launcher",
        remember = false,
        panel = create_panel,
    }

    local function find_tab(tab_table, id)
        for i, tab in ipairs(tab_table or {}) do
            if tab.id == id then return i end
        end
    end

    local function insert_tab(menu_self)
        if not is_enabled() or type(menu_self.tab_item_table) ~= "table" then return end
        if find_tab(menu_self.tab_item_table, "app_launcher") then return end
        local qs_pos = find_tab(menu_self.tab_item_table, "quicksettings")
        table.insert(menu_self.tab_item_table, qs_pos and (qs_pos + 1) or 1, app_launcher_tab)
    end

    local function patch_menu_class(menu_class)
        if not menu_class or menu_class.__zen_app_launcher_tab_patched then return end
        menu_class.__zen_app_launcher_tab_patched = true
        local orig_sut = menu_class.setUpdateItemTable
        menu_class.setUpdateItemTable = function(self)
            orig_sut(self)
            insert_tab(self)
        end
    end

    local ok_fm, FileManagerMenu = pcall(require, "apps/filemanager/filemanagermenu")
    if ok_fm then patch_menu_class(FileManagerMenu) end
    local ok_rm, ReaderMenu = pcall(require, "apps/reader/modules/readermenu")
    if ok_rm then patch_menu_class(ReaderMenu) end

    local TouchMenu = require("ui/widget/touchmenu")
    if not TouchMenu.__zen_app_launcher_back_patched then
        TouchMenu.__zen_app_launcher_back_patched = true
        local function leave_folder(self)
            if self.item_table and self.item_table.id == "app_launcher"
                    and self._app_launcher_folder_id then
                self._app_launcher_folder_id = nil
                self:updateItems(1)
                return true
            end
            return false
        end
        local orig_onBack = TouchMenu.onBack
        TouchMenu.onBack = function(self, ...)
            if leave_folder(self) then return true end
            return orig_onBack(self, ...)
        end
        local orig_onClose = TouchMenu.onClose
        TouchMenu.onClose = function(self, ...)
            if leave_folder(self) then return true end
            return orig_onClose(self, ...)
        end
        local orig_onFocusMove = TouchMenu.onFocusMove
        TouchMenu.onFocusMove = function(self, args)
            local dx = type(args) == "table" and args[1] or 0
            if dx < 0 and self.selected and self.selected.x == 1 and leave_folder(self) then
                return true
            end
            return orig_onFocusMove(self, args)
        end
    end
end

return apply_app_launcher
