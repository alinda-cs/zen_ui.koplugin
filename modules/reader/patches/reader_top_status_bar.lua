local function apply_reader_top_status_bar()
    --[[
        Paints a configurable three-zone header at the top of the reader screen (reflowable docs).
        Left / center / right slots each hold an ordered list of item keys.
        Items: time, battery, wifi, frontlight, ram, disk, custom_text,
               book_title, author, chapter
        Wraps ReaderView.paintTo. Config via config.reader_top_status_bar.
    --]]

    local Blitbuffer    = require("ffi/blitbuffer")
    local TextWidget    = require("ui/widget/textwidget")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local LeftContainer   = require("ui/widget/container/leftcontainer")
    local RightContainer  = require("ui/widget/container/rightcontainer")
    local OverlapGroup  = require("ui/widget/overlapgroup")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan  = require("ui/widget/verticalspan")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local HorizontalSpan  = require("ui/widget/horizontalspan")
    local BD       = require("ui/bidi")
    local Size     = require("ui/size")
    local Geom     = require("ui/geometry")
    local Device   = require("device")
    local Font     = require("ui/font")
    local datetime = require("datetime")
    local UIManager = require("ui/uimanager")
    local _ = require("gettext")
    local Screen = Device.screen
    local ReaderView = require("apps/reader/modules/readerview")
    local _ReaderView_paintTo_orig = ReaderView.paintTo
    local zen_plugin = rawget(_G, "__ZEN_UI_PLUGIN")

    local logger = require("logger")
    local DBG = function(...) logger.dbg("ZenHeader:", ...) end

    local function is_enabled()
        local plugin = zen_plugin or rawget(_G, "__ZEN_UI_PLUGIN")
        local features = plugin and plugin.config and plugin.config.features
        return type(features) == "table" and features.reader_top_status_bar == true
    end

    -- Stable reference so suspend/resume can cancel/restart the timer.
    local _autoRefresh

    -- === Separator lookup ===

    local separator_presets = {
        { key = "dot",         value = "  \xC2\xB7  " }, -- middle dot (UTF-8)
        { key = "bar",         value = "  |  "  },
        { key = "dash",        value = "  -  "  },
        { key = "bullet",      value = "  \xE2\x80\xA2  " }, -- bullet (UTF-8)
        { key = "space",       value = "   "    },
        { key = "small-space", value = " "      },
        { key = "none",        value = ""       },
    }

    -- === Caches for slow item fetchers ===

    local cached_disk_text, cached_disk_time = nil, 0
    local cached_ram_text,  cached_ram_time  = nil, 0

    -- === Item fetchers: return (primary_text, suffix_or_nil) ===

    local function getWifiItem()
        local ok, NetworkMgr = pcall(require, "ui/network/manager")
        if not ok then return nil end
        return NetworkMgr:isWifiOn() and "\u{ECA8}" or "\u{ECA9}", nil
    end

    local function getRamItem()
        local now = os.time()
        if cached_ram_text and (now - cached_ram_time) < 30 then
            return "\u{EA5A}", " " .. cached_ram_text
        end
        local statm = io.open("/proc/self/statm", "r")
        if statm then
            local pages, rss_pages = statm:read("*number", "*number")
            statm:close()
            if rss_pages then
                cached_ram_text = string.format("%dM", math.floor(rss_pages / 256))
                cached_ram_time = now
                return "\u{EA5A}", " " .. cached_ram_text
            end
        end
        return "\u{EA5A}", " ?M"
    end

    local function getDiskItem()
        local now = os.time()
        if cached_disk_text and (now - cached_disk_time) < 300 then
            return "\u{F0A0}", " " .. cached_disk_text
        end
        local paths = require("common/paths")
        local home_dir = paths.getHomeDir()
        local dirs = {}
        if home_dir and home_dir ~= "" then table.insert(dirs, home_dir) end
        for _i, p in ipairs({ "/mnt/us", "/mnt/onboard", "/sdcard", "/" }) do
            table.insert(dirs, p)
        end
        for _i, dir in ipairs(dirs) do
            local pipe = io.popen("df -h " .. dir .. " 2>/dev/null")
            if pipe then
                for line in pipe:lines() do
                    local avail = line:match("%S+%s+%S+%s+%S+%s+(%S+)")
                    if avail and avail:match("^%d") then
                        pipe:close()
                        cached_disk_text = avail
                        cached_disk_time = now
                        return "\u{F0A0}", " " .. avail
                    end
                end
                pipe:close()
            end
        end
        return "\u{F0A0}", " ?"
    end

    local function getFrontlightItem()
        local powerd = Device:getPowerDevice()
        if not powerd then return nil end
        if powerd:isFrontlightOn() then
            return "\xe2\x98\xbc", string.format(" %d", powerd:frontlightIntensity())
        end
        return "\xe2\x98\xbc", " " .. _("Off")
    end

    local function getBatteryItem()
        if not Device:hasBattery() then return nil end
        local powerd = Device:getPowerDevice()
        local batt_lvl = powerd:getCapacity()
        local batt_symbol = powerd:getBatterySymbol(
            powerd:isCharged(), powerd:isCharging(), batt_lvl)
        return BD.wrap(batt_symbol), batt_lvl .. "%"
    end

    local function getTimeItem()
        local use_12h = G_reader_settings:isTrue("twelve_hour_clock")
        return datetime.secondsToHour(os.time(), use_12h) or "", nil
    end

    local function getCustomTextItem()
        local cfg = zen_plugin and zen_plugin.config and zen_plugin.config.reader_top_status_bar
        local text = type(cfg) == "table" and cfg.custom_text
        if not text or text == "" then text = Device.model or "Zen UI" end
        return text ~= "" and text or nil, nil
    end

    -- doc_ctx is the ReaderView; its .ui.doc_props has title/authors, .ui.toc has chapter.
    local function getBookTitleItem(doc_ctx)
        if not doc_ctx or not doc_ctx.ui then return nil end
        local props = doc_ctx.ui.doc_props
        local title = props and props.title
        if not title or title == "" then return nil end
        if #title > 40 then title = title:sub(1, 37) .. "..." end
        return title, nil
    end

    local function getAuthorItem(doc_ctx)
        if not doc_ctx or not doc_ctx.ui then return nil end
        local props = doc_ctx.ui.doc_props
        local authors = props and props.authors
        if not authors or authors == "" then return nil end
        if #authors > 30 then authors = authors:sub(1, 27) .. "..." end
        return authors, nil
    end

    local function getChapterItem(doc_ctx)
        if not doc_ctx or not doc_ctx.ui then return nil end
        local toc = doc_ctx.ui.toc
        if not toc then return nil end
        local chapter = toc:getTocTitleOfCurrentPage()
        if not chapter or chapter == "" then return nil end
        if #chapter > 35 then chapter = chapter:sub(1, 32) .. "..." end
        return chapter, nil
    end

    local item_fetchers = {
        wifi        = getWifiItem,
        disk        = getDiskItem,
        ram         = getRamItem,
        frontlight  = getFrontlightItem,
        battery     = getBatteryItem,
        time        = getTimeItem,
        custom_text = getCustomTextItem,
        book_title  = getBookTitleItem,
        author      = getAuthorItem,
        chapter     = getChapterItem,
    }

    -- Builds a HorizontalGroup from an ordered item list.
    -- Returns (group_or_nil, widgets_list) where widgets_list holds all TextWidgets for free().
    local function buildGroup(order, face, sep, doc_ctx)
        if type(order) ~= "table" or #order == 0 then return nil, {} end
        local group   = HorizontalGroup:new{}
        local widgets = {}
        local first   = true
        for _i, key in ipairs(order) do
            local fn = item_fetchers[key]
            if fn then
                local icon, label = fn(doc_ctx)
                if icon ~= nil then
                    if not first and sep ~= "" then
                        local sep_w = TextWidget:new{ text = sep, face = face, padding = 0 }
                        table.insert(group, sep_w)
                        table.insert(widgets, sep_w)
                    end
                    local text = label and (icon .. label) or icon
                    local tw = TextWidget:new{
                        text    = text,
                        face    = face,
                        fgcolor = Blitbuffer.COLOR_BLACK,
                        padding = 0,
                    }
                    table.insert(group, tw)
                    table.insert(widgets, tw)
                    first = false
                end
            end
        end
        if #group == 0 then return nil, {} end
        return group, widgets
    end

    -- Builds the header widget from current config.
    -- doc_ctx: ReaderView (or nil); needed for book_title, author, chapter items.
    -- Returns header, all_widgets, header_h, screen_width; or nil if nothing to paint.
    local function buildHeader(doc_ctx)
        local screen_width = Screen:getWidth()
        local cfg = zen_plugin and zen_plugin.config and zen_plugin.config.reader_top_status_bar
        local footer_settings = G_reader_settings:readSetting("footer")

        local face_cfg = type(cfg) == "table" and cfg.font_face or "default"
        local font_name
        if face_cfg == "default" then
            font_name = (footer_settings and footer_settings.text_font_face) or "NotoSans-Regular.ttf"
        else
            font_name = face_cfg
        end
        local font_size = (type(cfg) == "table" and cfg.font_size) or 14
        local face = Font:getFace(font_name, font_size)

        local top_pad = Size.padding.small
        local h_pad   = Screen:scaleBySize(10)

        -- Slot orders (with backward compat for old position = "left/center/right" key)
        local left_order   = (type(cfg) == "table" and cfg.left_order)   or {}
        local center_order = (type(cfg) == "table" and cfg.center_order)
        local right_order  = (type(cfg) == "table" and cfg.right_order)  or {}
        if center_order == nil then
            local pos = type(cfg) == "table" and cfg.position
            if pos == "left" then
                left_order, center_order, right_order = { "time" }, {}, {}
            elseif pos == "right" then
                left_order, center_order, right_order = {}, {}, { "time" }
            else
                center_order = { "time" }
            end
        end

        local sep_key = (type(cfg) == "table" and cfg.separator_key) or "small-space"
        local sep_val = " "
        for _i, preset in ipairs(separator_presets) do
            if preset.key == sep_key then
                sep_val = preset.value
                break
            end
        end
        if sep_key == "custom" then
            sep_val = (type(cfg) == "table" and cfg.custom_separator) or "  "
        end

        local all_widgets = {}
        local left_grp,   left_ws   = buildGroup(left_order,   face, sep_val, doc_ctx)
        local center_grp, center_ws = buildGroup(center_order, face, sep_val, doc_ctx)
        local right_grp,  right_ws  = buildGroup(right_order,  face, sep_val, doc_ctx)
        for _i, w in ipairs(left_ws)   do table.insert(all_widgets, w) end
        for _i, w in ipairs(center_ws) do table.insert(all_widgets, w) end
        for _i, w in ipairs(right_ws)  do table.insert(all_widgets, w) end

        if not left_grp and not center_grp and not right_grp then
            DBG("buildHeader: all groups nil, doc_ctx=", doc_ctx and "present" or "nil",
                "left_order=", #left_order, "center_order=", #(center_order or {}), "right_order=", #right_order)
            return nil, {}, 0, screen_width
        end

        local row_h = 0
        local function upd(w)
            if w then local s = w:getSize(); if s and s.h > row_h then row_h = s.h end end
        end
        upd(left_grp); upd(center_grp); upd(right_grp)
        local header_h = row_h + top_pad

        local function padded(grp)
            if not grp then return nil end
            local vg = VerticalGroup:new{}
            table.insert(vg, VerticalSpan:new{ width = top_pad })
            table.insert(vg, grp)
            return vg
        end

        local header = OverlapGroup:new{ dimen = Geom:new{ w = screen_width, h = header_h } }
        if left_grp then
            table.insert(header, LeftContainer:new{
                dimen = Geom:new{ w = screen_width, h = header_h },
                HorizontalGroup:new{
                    HorizontalSpan:new{ width = h_pad },
                    padded(left_grp),
                },
            })
        end
        if center_grp then
            table.insert(header, CenterContainer:new{
                dimen = Geom:new{ w = screen_width, h = header_h },
                padded(center_grp),
            })
        end
        if right_grp then
            table.insert(header, RightContainer:new{
                dimen = Geom:new{ w = screen_width, h = header_h },
                HorizontalGroup:new{
                    padded(right_grp),
                    HorizontalSpan:new{ width = h_pad },
                },
            })
        end

        return header, all_widgets, header_h, screen_width
    end

    -- Partial repaint: clears only the header strip in Screen.bb, repaints it,
    -- then flushes just that region to the display.  Avoids triggering a full
    -- ReaderView:paintTo (full page repaint) on every clock tick -- critical on
    -- color e-ink devices (e.g. Kobo Libre Color).
    local function repaintHeader(view)
        if not view._zen_header_dimen then
            DBG("repaintHeader SKIP: no _zen_header_dimen (paintTo never ran?)")
            return
        end
        if not view.ui then
            DBG("repaintHeader SKIP: view.ui is nil")
            return
        end
        local header, all_widgets, header_h, screen_width = buildHeader(view)
        if not header then
            DBG("repaintHeader SKIP: buildHeader returned nil")
            return
        end
        local dimen = view._zen_header_dimen
        dimen.h = header_h
        dimen.w = screen_width
        local bb = Screen.bb
        if bb then
            bb:paintRect(dimen.x, dimen.y, dimen.w, dimen.h, Blitbuffer.COLOR_WHITE)
        end
        UIManager:widgetRepaint(header, dimen.x, dimen.y)
        UIManager:setDirty(nil, "ui", dimen)
        for _i, w in ipairs(all_widgets) do
            if w.free then w:free() end
        end
    end

    ReaderView.paintTo = function(self, bb, x, y)
        _ReaderView_paintTo_orig(self, bb, x, y)
        if not is_enabled() then return end
        if self.render_mode ~= nil then return end -- pdf-like; skip
        if not self.document then return end
        -- Guard: don't paint when reader is not the topmost widget.
        local _stack = UIManager._window_stack
        if not _stack then return end
        local _top = _stack[#_stack]
        local _w = _top and _top.widget
        if _w ~= self.ui and _w ~= (self.ui and self.ui.show_parent) then
            return
        end

        local header, all_widgets, header_h, screen_width = buildHeader(self)
        if not header then
            DBG("paintTo: buildHeader returned nil, skipping header paint")
            return
        end

        header:paintTo(bb, x, y)
        -- Store geometry so repaintHeader can flush only this strip on clock ticks.
        self._zen_header_dimen = Geom:new{ x = x, y = y, w = screen_width, h = header_h }

        -- Free FFI-backed TextWidget memory immediately after paint.
        for _i, w in ipairs(all_widgets) do
            if w.free then w:free() end
        end

        -- Periodic refresh aligned to the top of each minute.
        -- Armed once per ReaderView instance; cancelled on suspend, restarted on resume.
        if not self._header_clock_refresh then
            self._header_clock_refresh = true
            local view = self
            local _autoRefreshFn
            _autoRefreshFn = function()
                if not (view.ui and view.ui.document) then
                    _autoRefresh = nil
                    return
                end
                local stack = UIManager._window_stack
                local top   = stack and stack[#stack]
                if top then
                    local w = top.widget
                    if w == view.ui or w == view.ui.show_parent then
                        repaintHeader(view)
                    end
                end
                local t = os.date("*t")
                UIManager:scheduleIn(60 - t.sec, _autoRefreshFn)
            end
            _autoRefresh = _autoRefreshFn
            local t = os.date("*t")
            UIManager:scheduleIn(60 - t.sec, _autoRefreshFn)

            -- Cancel timer on suspend so it does not fire during sleep.
            local ReaderUI = require("apps/reader/readerui")
            -- Shared upvalue between onSuspend and the charging hooks below.
            local _charging_refresh_timer = nil
            local orig_onSuspend = ReaderUI.onSuspend
            ReaderUI.onSuspend = function(rui, ...)
                if orig_onSuspend then orig_onSuspend(rui, ...) end
                if _autoRefresh then
                    UIManager:unschedule(_autoRefresh)
                end
                if _charging_refresh_timer then
                    UIManager:unschedule(_charging_refresh_timer)
                    _charging_refresh_timer = nil
                end
            end
            local orig_onResume = ReaderUI.onResume
            ReaderUI.onResume = function(rui, ...)
                if orig_onResume then orig_onResume(rui, ...) end
                DBG("onResume fired, _autoRefresh=", _autoRefresh and "armed" or "nil",
                    "view._zen_header_dimen=", view._zen_header_dimen and "present" or "nil",
                    "view.ui=", view.ui and "present" or "nil")
                if _autoRefresh then
                    UIManager:unschedule(_autoRefresh)
                    -- Repaint immediately so header is visible on wakeup
                    -- without waiting for the next minute tick or page turn.
                    repaintHeader(view)
                    local t = os.date("*t")
                    UIManager:scheduleIn(60 - t.sec, _autoRefresh)
                end
            end

            -- Debounce charging events: USB negotiation fires NotCharging then
            -- Charging within seconds; coalesce into one repaint after 1.5 s.
            local function scheduleChargingRefresh()
                if _charging_refresh_timer then
                    UIManager:unschedule(_charging_refresh_timer)
                end
                _charging_refresh_timer = function()
                    _charging_refresh_timer = nil
                    if not (view.ui and view.ui.document) then return end
                    local stack = UIManager._window_stack
                    local top   = stack and stack[#stack]
                    if top then
                        local w = top.widget
                        if w == view.ui or w == view.ui.show_parent then
                            repaintHeader(view)
                        end
                    end
                end
                UIManager:scheduleIn(1.5, _charging_refresh_timer)
            end
            local orig_onCharging    = ReaderUI.onCharging
            local orig_onNotCharging = ReaderUI.onNotCharging
            ReaderUI.onCharging = function(rui, ...)
                if orig_onCharging then orig_onCharging(rui, ...) end
                scheduleChargingRefresh()
            end
            ReaderUI.onNotCharging = function(rui, ...)
                if orig_onNotCharging then orig_onNotCharging(rui, ...) end
                scheduleChargingRefresh()
            end
        end
    end
end

return apply_reader_top_status_bar
