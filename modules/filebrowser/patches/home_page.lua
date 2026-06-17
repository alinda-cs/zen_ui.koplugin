local logger = require("logger")
local ConfigManager = require("config/manager")
local book_status = require("common/book_status")
local Blitbuffer = require("ffi/blitbuffer")
local HomeQuotes = require("modules/filebrowser/patches/home/home_quotes")
local HomePresets = require("modules/filebrowser/patches/home/home_presets")
local PresetStore = require("config/preset_store")
local Registry = require("modules/filebrowser/patches/home/components/registry")
local StandalonePage = require("modules/filebrowser/patches/standalone_page")
local SharedState = require("common/shared_state")

local M = {}

local _home_menu = nil
local _home_inject_navbar = nil
local _zen_shared = nil
local _zen_plugin = nil

local function refresh_shared_state()
    if _zen_plugin then
        _zen_shared = SharedState.restore(_zen_plugin) or _zen_shared
    end
    return _zen_shared
end

local DEFAULT_ROW_ORDER = {
    "datetime",
    "featured_recent",
    "featured_custom",
    "featured_tbr",
    "stats_triplet",
    "reading_goals",
    "strip_recent",
    "strip_custom",
    "strip_tbr",
    "quotes",
}

local DEFAULT_ROW_ENABLED = {
    datetime = true,
    featured_recent = true,
    quotes = true,
    strip_recent = true,
}

local DEFAULT_FEATURED_PROGRESS_META = {
    left = "percent",
    right = "total_pages",
}

local function copy_default_row_order()
    local out = {}
    for _i, id in ipairs(DEFAULT_ROW_ORDER) do
        out[#out + 1] = id
    end
    return out
end

local function copy_default_row_enabled()
    local out = {}
    for key, value in pairs(DEFAULT_ROW_ENABLED) do
        out[key] = value
    end
    return out
end

local MODULE_TITLES = {
    datetime = "Today",
    featured_custom = "Featured Book",
    featured_tbr = "To be Read",
    featured_recent = "Recently read",
    reading_goals = "Reading goals",
    strip_custom = "Featured Books",
    strip_tbr = "To be Read",
    strip_recent = "Recently read",
    stats_triplet = "Reading stats",
    quotes = "Quote",
}

local function normalize_order(order)
    if order == "reverse" then return "reverse" end
    return "default"
end

local function ensure_module_cfg(dcfg, module_id)
    if type(dcfg.modules) ~= "table" then dcfg.modules = {} end
    if type(dcfg.modules[module_id]) ~= "table" then dcfg.modules[module_id] = {} end
    local mcfg = dcfg.modules[module_id]
    if module_id == "datetime" then
        mcfg.show_module_title = false
    elseif mcfg.show_module_title == nil then
        mcfg.show_module_title = false
    end
    return mcfg
end

local function ensure_featured_module_cfg(dcfg, module_id)
    local mcfg = ensure_module_cfg(dcfg, module_id)
    mcfg.order = normalize_order(mcfg.order)
    if mcfg.show_description == nil then mcfg.show_description = true end
    if mcfg.interactive == nil then mcfg.interactive = true end
    if mcfg.show_status_bar == nil then mcfg.show_status_bar = false end
    if mcfg.status_bar_show_bottom_border == nil then mcfg.status_bar_show_bottom_border = true end
    if mcfg.status_bar_bold_text == nil then mcfg.status_bar_bold_text = true end
    if type(mcfg.progress_meta) ~= "table" then mcfg.progress_meta = {} end
    if mcfg.progress_meta.left == nil and mcfg.progress_meta.right == nil then
        for key, side in pairs(mcfg.progress_meta) do
            if side == "left" and mcfg.progress_meta.left == nil then
                mcfg.progress_meta.left = key
            elseif side == "right" and mcfg.progress_meta.right == nil then
                mcfg.progress_meta.right = key
            end
        end
    end
    for side, metric in pairs(DEFAULT_FEATURED_PROGRESS_META) do
        if mcfg.progress_meta[side] ~= "total_pages"
                and mcfg.progress_meta[side] ~= "current_total"
                and mcfg.progress_meta[side] ~= "percent"
                and mcfg.progress_meta[side] ~= "time_left"
                and mcfg.progress_meta[side] ~= "off" then
            mcfg.progress_meta[side] = metric
        end
    end
    return mcfg
end

local function ensure_strip_module_cfg(dcfg, module_id)
    local mcfg = ensure_module_cfg(dcfg, module_id)
    mcfg.order = normalize_order(mcfg.order)
    if mcfg.interactive == nil then mcfg.interactive = true end
    if mcfg.two_rows == nil then mcfg.two_rows = false end
    if type(mcfg.count) ~= "number" then mcfg.count = mcfg.two_rows and 8 or 4 end
    if mcfg.two_rows then
        if mcfg.count < 2 then mcfg.count = 2 end
        if mcfg.count > 10 then mcfg.count = 10 end
    else
        if mcfg.count < 3 then mcfg.count = 3 end
        if mcfg.count > 5 then mcfg.count = 5 end
    end
    if mcfg.show_strip_titles == nil then
        local cfg = ConfigManager.get()
        mcfg.show_strip_titles = type(cfg) == "table"
            and type(cfg.mosaic_title_strip) == "table"
            and cfg.mosaic_title_strip.show_title == true
    end
    return mcfg
end

local function ensure_home_widget_cfg(dcfg)
    local featured_custom = ensure_featured_module_cfg(dcfg, "featured_custom")
    if type(featured_custom.path) ~= "string" then featured_custom.path = nil end
    ensure_featured_module_cfg(dcfg, "featured_tbr")
    ensure_featured_module_cfg(dcfg, "featured_recent")
    local stats_triplet = ensure_module_cfg(dcfg, "stats_triplet")
    if stats_triplet.stat_style ~= "outline" and stats_triplet.stat_style ~= "none" then
        stats_triplet.stat_style = "divider"
    end
    local strip_custom = ensure_strip_module_cfg(dcfg, "strip_custom")
    if type(strip_custom.paths) ~= "table" then strip_custom.paths = {} end
    ensure_strip_module_cfg(dcfg, "strip_tbr")
    ensure_strip_module_cfg(dcfg, "strip_recent")
end

local function load_zen_config()
    if _zen_plugin and type(_zen_plugin.config) == "table" then
        return _zen_plugin.config
    end
    local ok, cfg = pcall(ConfigManager.load)
    if ok and type(cfg) == "table" then
        return cfg
    end
end

local function mosaic_titles_enabled()
    local cfg = load_zen_config()
    return type(cfg) == "table"
        and type(cfg.mosaic_title_strip) == "table"
        and cfg.mosaic_title_strip.show_title == true
end

local function unique_user_preset_name(base)
    if not PresetStore.find("home", base) then return base end
    local i = 2
    while PresetStore.find("home", base .. " " .. i) do
        i = i + 1
    end
    return base .. " " .. i
end

local function editable_name_for_builtin(preset_name)
    if preset_name == HomePresets.DEFAULT_PRESET_NAME then
        return HomePresets.CUSTOM_PRESET_NAME
    end
    return tostring(preset_name or HomePresets.CUSTOM_PRESET_NAME) .. " custom"
end

local function ensure_home_cfg()
    local dcfg = PresetStore.getSettings("home")
    if type(dcfg) ~= "table" or next(dcfg) == nil then
        dcfg = HomePresets.defaultHomePage()
    end
    HomePresets.ensurePresetState(dcfg)

    if type(dcfg.rows) ~= "table" then dcfg.rows = {} end
    local rows = dcfg.rows

    if type(rows.order) ~= "table" then rows.order = {} end
    local normalized_order = {}
    local seen_order = {}
    for _i, id in ipairs(rows.order) do
        if Registry.get(id) and not seen_order[id] then
            seen_order[id] = true
            table.insert(normalized_order, id)
        end
    end
    if #normalized_order == 0 then
        rows.order = copy_default_row_order()
    else
        rows.order = normalized_order
    end

    if type(rows.enabled) ~= "table" then rows.enabled = {} end
    local normalized_enabled = {}
    local had_enabled = false
    for key, val in pairs(rows.enabled) do
        if Registry.get(key) and val == true then
            normalized_enabled[key] = true
            had_enabled = true
        elseif Registry.get(key) and normalized_enabled[key] == nil then
            normalized_enabled[key] = false
        end
    end
    if not had_enabled then
        normalized_enabled = copy_default_row_enabled()
    end
    for _i, comp in ipairs(Registry.list()) do
        if normalized_enabled[comp.id] == nil then
            normalized_enabled[comp.id] = false
        end
    end
    rows.enabled = normalized_enabled
    rows.max_rows = 5

    if dcfg.show_status_bar == nil then dcfg.show_status_bar = true end

    if type(dcfg.middle_stats_triplet) ~= "table" then
        dcfg.middle_stats_triplet = { "today_pages", "today_duration", "streak" }
    end

    if type(dcfg.goals) ~= "table" then dcfg.goals = {} end
    if dcfg.goals.metric ~= "time" and dcfg.goals.metric ~= "pages" then
        dcfg.goals.metric = "pages"
    end
    if dcfg.goals.period ~= "weekly" and dcfg.goals.period ~= "daily" then
        dcfg.goals.period = "daily"
    end
    if type(dcfg.goals.daily_pages_target) ~= "number" then dcfg.goals.daily_pages_target = 30 end
    if type(dcfg.goals.weekly_pages_target) ~= "number" then dcfg.goals.weekly_pages_target = 210 end
    if type(dcfg.goals.daily_time_target_min) ~= "number" then dcfg.goals.daily_time_target_min = 30 end
    if type(dcfg.goals.weekly_time_target_min) ~= "number" then dcfg.goals.weekly_time_target_min = 210 end

    if type(dcfg.quotes) ~= "table" then dcfg.quotes = {} end
    if dcfg.quotes.show_author == nil then dcfg.quotes.show_author = true end

    if type(dcfg.quotes.manual_index) ~= "number" then dcfg.quotes.manual_index = 1 end

    -- Per-widget home settings.
    for _i, comp in ipairs(Registry.list()) do
        ensure_module_cfg(dcfg, comp.id)
    end
    ensure_home_widget_cfg(dcfg)

    -- When the active preset is still a builtin (e.g. first load of the default),
    -- derive an editable custom preset so the mosaic "Show title below cover"
    -- setting can drive strip book titles. Builtins pin show_strip_titles=false,
    -- so the value only takes effect on a persisted user copy.
    if HomePresets.isBuiltinPresetName(dcfg.active_preset) and mosaic_titles_enabled() then
        HomePresets.applyMosaicTitlesToStrips(dcfg, true)
        local name = unique_user_preset_name(editable_name_for_builtin(dcfg.active_preset))
        dcfg.active_preset = name
        dcfg.title = name
        local state = HomePresets.captureHomePage(dcfg)
        state.title = name
        PresetStore.save("home", name, state)
        PresetStore.setActivePreset("home", name)
        PresetStore.saveSettings("home", dcfg)
    end

    return dcfg
end

local function save_home_settings(dcfg)
    if type(dcfg) == "table" and HomePresets.isBuiltinPresetName(dcfg.active_preset) then
        local name = unique_user_preset_name(editable_name_for_builtin(dcfg.active_preset))
        dcfg.active_preset = name
        dcfg.title = name
        local state = HomePresets.captureHomePage(dcfg)
        state.title = name
        PresetStore.save("home", name, state)
        PresetStore.setActivePreset("home", name)
    end
    PresetStore.saveSettings("home", dcfg)
end

local function resolve_rows(dcfg)
    local rows_cfg = dcfg.rows or {}
    local order = rows_cfg.order or DEFAULT_ROW_ORDER
    local enabled = rows_cfg.enabled or {}
    local max_rows = tonumber(rows_cfg.max_rows) or 5
    if max_rows < 1 then max_rows = 1 end
    if max_rows > 5 then max_rows = 5 end

    local seen = {}
    local out = {}

    local function try_push(id)
        if seen[id] then return end
        if enabled[id] ~= true then return end
        local comp = Registry.get(id)
        if not comp then return end
        seen[id] = true
        -- for strip widgets with two_rows enabled, double the size allocation
        local mcfg = type(dcfg.modules) == "table" and dcfg.modules[id] or nil
        if mcfg and mcfg.two_rows == true and comp.size then
            local s = comp.size
            comp = setmetatable({
                size = {
                    preferred_pct = (s.preferred_pct or 0.20) * 2,
                    min_pct       = (s.min_pct       or 0.12) * 2,
                    max_pct       = (s.max_pct       or 0.30) * 2,
                    grow_priority = s.grow_priority,
                },
            }, { __index = comp })
        end
        table.insert(out, comp)
    end

    for _i, id in ipairs(order) do
        try_push(id)
        if #out >= max_rows then break end
    end

    if #out < max_rows then
        for _i, comp in ipairs(Registry.list()) do
            try_push(comp.id)
            if #out >= max_rows then break end
        end
    end

    if #out == 0 then
        for _i, id in ipairs(DEFAULT_ROW_ORDER) do
            local comp = Registry.get(id)
            if comp then table.insert(out, comp) end
        end
    end

    while #out > max_rows do
        table.remove(out)
    end

    return out
end

local function get_quote_day_index()
    local now = os.date("*t")
    return ((now.year * 366) + now.yday)
end

local function get_daily_quote_index()
    local quotes = HomeQuotes.getQuotes()
    if #quotes == 0 then return 1 end
    return (get_quote_day_index() % #quotes) + 1
end

local function collect_stats_fields(rows, dcfg)
    local fields = {}
    local needs_stats = false

    local function add(name)
        fields[name] = true
        needs_stats = true
    end

    for _i, comp in ipairs(rows or {}) do
        local id = comp and comp.id
        if id == "stats_triplet" then
            local triplet = dcfg.middle_stats_triplet or { "today_pages", "today_duration", "streak" }
            local added = false
            for _j, field in ipairs(triplet) do
                if field == "today_pages" or field == "today_duration"
                        or field == "week_pages" or field == "week_duration"
                        or field == "streak" then
                    add(field)
                    added = true
                else
                    add("today_pages")
                    added = true
                end
            end
            if not added then add("today_pages") end
        elseif id == "reading_goals" then
            local goals = dcfg.goals or {}
            local metric = goals.metric == "time" and "time" or "pages"
            local period = goals.period == "weekly" and "weekly" or "daily"
            if metric == "time" then
                add(period == "weekly" and "week_duration" or "today_duration")
            else
                add(period == "weekly" and "week_pages" or "today_pages")
            end
        end
    end

    if not needs_stats then return nil end
    return fields
end

local function stats_fields_key(fields)
    if type(fields) ~= "table" then return "" end
    local order = { "today_pages", "today_duration", "week_pages", "week_duration", "streak" }
    local out = {}
    for _i, key in ipairs(order) do
        if fields[key] then out[#out + 1] = key end
    end
    return table.concat(out, ",")
end

local function build_data_provider(cfg, dcfg)
    local provider = {}
    local stats_cached = nil
    local stats_cached_key = nil
    local history_cached = nil
    local tbr_cached = nil
    local strip_offsets = {}

    local function is_widget_visible(widget_id)
        if type(widget_id) ~= "string" or widget_id == "" then return false end
        local rows_cfg = dcfg and dcfg.rows or {}
        local order = type(rows_cfg.order) == "table" and rows_cfg.order or DEFAULT_ROW_ORDER
        local enabled = type(rows_cfg.enabled) == "table" and rows_cfg.enabled or {}
        local max_rows = tonumber(rows_cfg.max_rows) or 5
        if max_rows < 1 then max_rows = 1 end
        if max_rows > 5 then max_rows = 5 end

        local seen = {}
        local shown = 0

        local function try_mark(id)
            if seen[id] then return false end
            if enabled[id] ~= true then return false end
            local comp = Registry.get(id)
            if not comp then return false end
            seen[id] = true
            shown = shown + 1
            return id == widget_id
        end

        for _i, id in ipairs(order) do
            if try_mark(id) then return true end
            if shown >= max_rows then return false end
        end

        for _i, comp in ipairs(Registry.list()) do
            if try_mark(comp.id) then return true end
            if shown >= max_rows then return false end
        end

        return false
    end

    local function featured_widget_for_source(source)
        if source == "custom_featured" then return "featured_custom" end
        if source == "custom_strip" then return "featured_custom" end
        if source == "to_be_read" then return "featured_tbr" end
        return "featured_recent"
    end

    local function get_stats(fields)
        if stats_cached then return stats_cached end
        local ok_stats, StatsDB = pcall(require, "common/db_stats")
        if ok_stats and StatsDB and type(StatsDB.queryHomeStats) == "function" then
            stats_cached = StatsDB.queryHomeStats(fields) or {}
        elseif ok_stats and StatsDB and type(StatsDB.queryStats) == "function" then
            stats_cached = StatsDB.queryStats() or {}
        else
            stats_cached = {}
        end
        return stats_cached
    end

    local function get_history()
        if history_cached then return history_cached end
        history_cached = {}
        local ok_rh, ReadHistory = pcall(require, "readhistory")
        if not ok_rh or not ReadHistory then
            return history_cached
        end

        if type(ReadHistory.reload) == "function" then
            pcall(ReadHistory.reload, ReadHistory, false)
        end

        local hist = ReadHistory.hist or {}
        local lfs = require("libs/libkoreader-lfs")
        local paths = require("common/paths")

        for _i, entry in ipairs(hist) do
            local path = entry and entry.file
            if type(path) == "string"
                    and path ~= ""
                    and paths.isInHomeDir(path)
                    and lfs.attributes(path, "mode") == "file" then
                table.insert(history_cached, path)
            end
        end

        return history_cached
    end

    local function get_book(path)
        if not path then return nil end
        local ok_bim, BookInfoManager = pcall(require, "bookinfomanager")
        local cover_bb, title, authors, pages, description
        if ok_bim and BookInfoManager then
            local bi = BookInfoManager:getBookInfo(path, true)
            if bi then
                title = bi.title
                authors = bi.authors
                pages = bi.pages
                description = bi.description
                if bi.cover_bb and bi.has_cover and bi.cover_fetched and not bi.ignore_cover then
                    cover_bb = bi.cover_bb:copy()
                end
            end
        end

        local pct = nil
        local status = nil
        local current_page = nil
        local time_left_secs = nil
        local ok_ds, DocSettings = pcall(require, "docsettings")
        if ok_ds and DocSettings and DocSettings:hasSidecarFile(path) then
            local ok_doc, doc = pcall(DocSettings.open, DocSettings, path)
            if ok_doc and doc then
                pct = doc:readSetting("percent_finished")
                local summary = doc:readSetting("summary")
                status = summary and summary.status
                local stats = doc:readSetting("stats")
                if not pages then
                    pages = stats and stats.pages
                end
                local total_pages = tonumber(pages)
                if total_pages and pct then
                    current_page = math.floor(total_pages * pct + 0.5)
                    if pct > 0 and current_page < 1 then current_page = 1 end
                    if current_page > total_pages then current_page = total_pages end
                end
                local avg_time = stats and tonumber(stats.avg_time)
                if not avg_time and stats and current_page and current_page > 0 then
                    local total_read_time = tonumber(stats.total_read_time or stats.total_time)
                    if total_read_time and total_read_time > 0 then
                        avg_time = total_read_time / current_page
                    end
                end
                if avg_time and avg_time > 0 and total_pages and current_page and current_page < total_pages then
                    time_left_secs = math.floor((total_pages - current_page) * avg_time)
                end
            end
        end

        if not title or title == "" then
            title = (path:match("([^/]+)$") or path):gsub("%.[^%.]+$", "")
        end

        return {
            path = path,
            title = title,
            authors = authors or "",
            cover_bb = cover_bb,
            percent = pct or 0,
            status = status,
            pages = pages,
            current_page = current_page,
            time_left_secs = time_left_secs,
            description = description,
        }
    end

    local function sort_files_like_tbr(files)
        local group_view = cfg and cfg.group_view or {}
        local detail_collate = group_view.detail_collate or {}
        local detail_reverse = group_view.detail_reverse or {}
        local collate_tbl = detail_collate.to_be_read or {}
        local reverse_tbl = detail_reverse.to_be_read or {}

        local collate = collate_tbl.to_be_read or "title"
        local reverse = reverse_tbl.to_be_read == true

        local ok_bim, BookInfoManager = pcall(require, "bookinfomanager")
        local lfs = require("libs/libkoreader-lfs")

        local items = {}
        for _i, fpath in ipairs(files) do
            local key
            if collate == "access" then
                key = lfs.attributes(fpath, "access") or 0
            elseif collate == "series_index" then
                local bi = ok_bim and BookInfoManager:getBookInfo(fpath, false) or nil
                key = (bi and tonumber(bi.series_index)) or math.huge
            elseif collate == "title" then
                local bi = ok_bim and BookInfoManager:getBookInfo(fpath, false) or nil
                key = (bi and bi.title) or (fpath:match("([^/]+)$") or fpath)
            else
                local bi = ok_bim and BookInfoManager:getBookInfo(fpath, false) or nil
                key = (bi and bi.title) or (fpath:match("([^/]+)$") or fpath)
            end
            table.insert(items, { path = fpath, key = key })
        end

        table.sort(items, function(a, b)
            if collate == "access" or collate == "series_index" then
                local ka = type(a.key) == "number" and a.key or 0
                local kb = type(b.key) == "number" and b.key or 0
                if collate == "access" then
                    if reverse then return ka < kb else return ka > kb end
                end
                if reverse then return ka > kb else return ka < kb end
            end
            local sa = tostring(a.key):lower()
            local sb = tostring(b.key):lower()
            if reverse then return sa > sb else return sa < sb end
        end)

        local sorted = {}
        for _i, item in ipairs(items) do
            table.insert(sorted, item.path)
        end
        return sorted
    end

    local function get_tbr_paths()
        if tbr_cached then return tbr_cached end
        tbr_cached = {}
        local ok_db, db = pcall(require, "common/db_bookinfo")
        if ok_db and db and type(db.getTBRBooks) == "function" then
            local raw_tbr = db.getTBRBooks() or {}
            local normalized = {}
            for _i, item in ipairs(raw_tbr) do
                local path = item
                if type(item) == "table" then
                    path = item.path or item.file
                end
                if type(path) == "string" and path ~= "" then
                    table.insert(normalized, path)
                end
            end
            tbr_cached = normalized
            tbr_cached = sort_files_like_tbr(tbr_cached)
        end
        return tbr_cached
    end

    local function get_paths_by_status(status_key, limit)
        local hist = get_history()
        local out = {}
        for _i, path in ipairs(hist) do
            local eff = book_status.getEffectiveStatusFromFile(path)
            if eff == status_key then
                table.insert(out, path)
                if #out >= limit then break end
            end
        end
        return out
    end

    local function append_unique_paths(dst, src, limit)
        if type(src) ~= "table" then return end
        local seen = {}
        for _i, path in ipairs(dst) do
            if type(path) == "string" and path ~= "" then
                seen[path] = true
            end
        end
        for _i, path in ipairs(src) do
            if type(path) == "string" and path ~= "" and not seen[path] then
                seen[path] = true
                table.insert(dst, path)
                if #dst >= limit then break end
            end
        end
    end

    local function reverse_copy(paths)
        local out = {}
        for i = #paths, 1, -1 do
            out[#out + 1] = paths[i]
        end
        return out
    end

    local function collect_paths_for_source(source_key, limit)
        local source = source_key
        if source ~= "custom_featured"
                and source ~= "custom_strip"
                and source ~= "currently_reading"
                and source ~= "to_be_read" then
            source = "recently_read"
        end
        local lim = tonumber(limit) or 5000
        if source == "custom_featured" then
            local mcfg = dcfg and dcfg.modules and dcfg.modules.featured_custom or {}
            local path = type(mcfg.path) == "string" and mcfg.path or nil
            return path and { path } or {}
        end
        if source == "custom_strip" then
            local mcfg = dcfg and dcfg.modules and dcfg.modules.strip_custom or {}
            local paths = type(mcfg.paths) == "table" and mcfg.paths or {}
            local out = {}
            for _i, path in ipairs(paths) do
                if type(path) == "string" and path ~= "" then
                    out[#out + 1] = path
                    if #out >= lim then break end
                end
            end
            return out
        end
        if source == "currently_reading" then
            return get_paths_by_status("reading", lim)
        end
        if source == "to_be_read" then
            local tbr = get_tbr_paths()
            local out = {}
            for _i, path in ipairs(tbr) do
                table.insert(out, path)
                if #out >= lim then break end
            end
            return out
        end
        local hist = get_history()
        local out = {}
        for _i, path in ipairs(hist) do
            table.insert(out, path)
            if #out >= lim then break end
        end
        return out
    end

    function provider:getFeaturedBook(source_key, order_key)
        local paths = collect_paths_for_source(source_key)
        if source_key ~= "custom_featured" and normalize_order(order_key) == "reverse" then
            paths = reverse_copy(paths)
        end
        local path = paths[1]
        return get_book(path)
    end

    local function get_strip_paths(source_key, count, order_key)
        local n = tonumber(count) or 5
        if n < 1 then n = 1 end
        local source = source_key
        if source ~= "custom_strip" and source ~= "currently_reading" and source ~= "to_be_read" then
            source = "recently_read"
        end
        local paths = collect_paths_for_source(source, 5000)

        if source ~= "custom_strip" and normalize_order(order_key) == "reverse" then
            paths = reverse_copy(paths)
        end

        -- Keep strip distinct from featured only when that featured widget is visible.
        local featured_widget_id = featured_widget_for_source(source)
        local should_dedupe_featured = source ~= "custom_strip" and is_widget_visible(featured_widget_id)
        if should_dedupe_featured and #paths > 0 then
            local featured_path = paths[1]
            if featured_path and featured_path ~= "" then
                local filtered = {}
                for _i, path in ipairs(paths) do
                    if path ~= featured_path then
                        filtered[#filtered + 1] = path
                    end
                end
                paths = filtered
            end
        end

        -- Keep strip density stable: when a source has too few items, backfill
        -- with recent valid history so the row can still show 3-5 covers.
        if source == "currently_reading" and #paths < n then
            append_unique_paths(paths, get_history(), n)
        end

        return source, paths, n
    end

    function provider:getBooksForStrip(source_key, count, order_key, component_id)
        local source, paths, n = get_strip_paths(source_key, count, order_key)

        local offset_key = tostring(component_id or source) .. ":" .. source .. ":" .. normalize_order(order_key)
        local offset = tonumber(strip_offsets[offset_key]) or 0
        if #paths > 0 then
            offset = offset % #paths
            strip_offsets[offset_key] = offset
        else
            offset = 0
        end

        local books = {}
        for i = 1, math.min(n, #paths) do
            local idx = ((offset + i - 1) % #paths) + 1
            local path = paths[idx]
            local book = get_book(path)
            if book then
                table.insert(books, book)
                if #books >= n then break end
            end
        end
        return books
    end

    function provider:shiftStrip(source_key, count, order_key, direction, component_id)
        local source, paths, n = get_strip_paths(source_key, count, order_key)
        if #paths <= n then return false end
        local offset_key = tostring(component_id or source) .. ":" .. source .. ":" .. normalize_order(order_key)
        local cur = tonumber(strip_offsets[offset_key]) or 0
        local step = direction == "previous" and -n or n
        strip_offsets[offset_key] = (cur + step) % #paths
        if _home_menu and _home_menu._home_rebuild then
            _home_menu:_home_rebuild()
        end
        return true
    end

    function provider:getCurrentQuote()
        local quotes = HomeQuotes.getQuotes()
        local quote_count = #quotes
        if quote_count == 0 then return nil end
        local idx
        local quote_cfg = dcfg.quotes or {}
        if quote_cfg.day_seed == get_quote_day_index() and type(quote_cfg.manual_index) == "number" then
            idx = quote_cfg.manual_index
        else
            idx = get_daily_quote_index()
        end
        if idx < 1 then idx = 1 end
        if idx > quote_count then idx = ((idx - 1) % quote_count) + 1 end
        return quotes[idx]
    end

    function provider:nextQuote()
        local quotes = HomeQuotes.getQuotes()
        local quote_count = #quotes
        if quote_count == 0 then return end
        local quote_cfg = dcfg.quotes or {}
        local current = quote_cfg.manual_index or get_daily_quote_index()
        local next_idx = current
        if quote_count > 1 then
            while next_idx == current do
                next_idx = math.random(1, quote_count)
            end
        end
        quote_cfg.manual_index = next_idx
        quote_cfg.day_seed = get_quote_day_index()
        dcfg.quotes = quote_cfg
        save_home_settings(dcfg)
        if _home_menu and _home_menu._home_rebuild then
            _home_menu:_home_rebuild()
        end
    end

    provider.stats = {}

    function provider:prepareStats(rows, force)
        local fields = collect_stats_fields(rows, dcfg)
        local key = stats_fields_key(fields)
        if key == "" then
            stats_cached = {}
            stats_cached_key = key
            self.stats = stats_cached
            return self.stats
        end
        if force or key ~= stats_cached_key then
            stats_cached = nil
            stats_cached_key = key
        end
        self.stats = get_stats(fields)
        return self.stats
    end

    function provider:refreshStats(rows)
        return self:prepareStats(rows, true)
    end

    function provider:getStats(rows)
        return self:prepareStats(rows, false)
    end

    function provider:clearStats()
        stats_cached = nil
        stats_cached_key = nil
        self.stats = {}
        return self.stats
    end

    return provider
end

local function size_to_px(size, key, pct_key, body_h, fallback)
    local pct = tonumber(size[pct_key])
    if pct then
        return math.max(1, math.floor(body_h * pct + 0.5))
    end
    return tonumber(size[key]) or fallback
end

local function compute_row_heights(rows, body_h)
    local specs = {}
    local total_min = 0

    for _i, comp in ipairs(rows) do
        local size = comp.size or {}
        local pref = size_to_px(size, "preferred", "preferred_pct", body_h, math.floor(body_h * 0.20))
        local min_h = size_to_px(size, "min", "min_pct", body_h, math.max(1, math.floor(pref * 0.55)))
        local max_h = size_to_px(size, "max", "max_pct", body_h, math.max(pref, min_h))
        if max_h < min_h then max_h = min_h end
        if pref < min_h then pref = min_h end
        if pref > max_h then pref = max_h end
        local id = comp.id or ""
        table.insert(specs, {
            id = id,
            is_strip = id == "strip" or id:match("^strip_") ~= nil,
            is_featured = id == "featured" or id:match("^featured_") ~= nil,
            is_datetime = id == "datetime",
            pref = pref,
            min = min_h,
            max = max_h,
            grow_priority = tonumber(size.grow_priority) or 10,
            h = pref,
        })
        total_min = total_min + min_h
    end

    if #specs == 0 then return specs end
    if body_h < #specs then body_h = #specs end

    if total_min > body_h then
        -- When strict mins cannot fit, shrink proportionally so rows stay contained.
        local scale = body_h / total_min
        local total = 0
        for _i, sp in ipairs(specs) do
            sp.h = math.max(1, math.floor(sp.min * scale))
            total = total + sp.h
        end
        local remaining = body_h - total
        local i = 1
        while remaining > 0 and #specs > 0 do
            specs[i].h = specs[i].h + 1
            remaining = remaining - 1
            i = i + 1
            if i > #specs then i = 1 end
        end
        return specs
    end

    local total = 0
    for _i, sp in ipairs(specs) do
        sp.h = sp.pref
        if sp.h < sp.min then sp.h = sp.min end
        if sp.h > sp.max then sp.h = sp.max end
        total = total + sp.h
    end

    local function pick_shrink_candidate(strip_only)
        local best_i = nil
        local best_room = 0
        for i, sp in ipairs(specs) do
            if not strip_only or sp.is_strip then
                local room = sp.h - sp.min
                if room > best_room then
                    best_room = room
                    best_i = i
                end
            end
        end
        return best_i, best_room
    end

    while total > body_h do
        local best_i, best_room = pick_shrink_candidate(true)
        if not best_i or best_room <= 0 then
            best_i, best_room = pick_shrink_candidate(false)
        end
        if not best_i or best_room <= 0 then break end
        specs[best_i].h = specs[best_i].h - 1
        total = total - 1
    end

    local grow_priorities = {}
    local seen_priority = {}
    for _i, sp in ipairs(specs) do
        local pri = tonumber(sp.grow_priority) or 10
        if not seen_priority[pri] then
            seen_priority[pri] = true
            grow_priorities[#grow_priorities + 1] = pri
        end
    end
    table.sort(grow_priorities)
    for _i, pri in ipairs(grow_priorities) do
        if total >= body_h then break end
        while total < body_h do
            local grew = false
            for _j, sp in ipairs(specs) do
                if total >= body_h then break end
                if (tonumber(sp.grow_priority) or 10) == pri and sp.h < sp.max then
                    sp.h = sp.h + 1
                    total = total + 1
                    grew = true
                end
            end
            if not grew then break end
        end
    end

    return specs
end

local function grow_row_heights_by_priority(row_heights, extra_px)
    local remaining = tonumber(extra_px) or 0
    local grown = 0
    if remaining <= 0 then
        return grown
    end
    local priorities = {}
    local seen = {}
    for _i, row in ipairs(row_heights) do
        local pri = tonumber(row.grow_priority) or 10
        if not seen[pri] then
            seen[pri] = true
            priorities[#priorities + 1] = pri
        end
    end
    table.sort(priorities)
    for _i, pri in ipairs(priorities) do
        if remaining <= 0 then break end
        while remaining > 0 do
            local grew = false
            for _j, row in ipairs(row_heights) do
                if remaining <= 0 then break end
                if (tonumber(row.grow_priority) or 10) == pri then
                    local max_h = tonumber(row.max) or tonumber(row.h) or 0
                    local cur_h = tonumber(row.h) or 0
                    if cur_h < max_h then
                        row.h = cur_h + 1
                        remaining = remaining - 1
                        grown = grown + 1
                        grew = true
                    end
                end
            end
            if not grew then break end
        end
    end
    return grown
end

local function build_home_content(menu, dcfg, rows, data_provider)
    local Device = require("device")
    local Screen = Device.screen
    local Geom = require("ui/geometry")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local HorizontalSpan = require("ui/widget/horizontalspan")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan = require("ui/widget/verticalspan")
    local TextWidget = require("ui/widget/textwidget")
    local LeftContainer = require("ui/widget/container/leftcontainer")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local Font = require("ui/font")

    local show_status_bar = dcfg.show_status_bar ~= false
    local tb = menu.title_bar
    local tb_h = show_status_bar and tb and tb:getSize().h or 0
    local menu_h = menu.height or (menu.inner_dimen and menu.inner_dimen.h or menu.dimen.h)
    local body_h = menu_h - tb_h
    local navbar_h = tonumber(rawget(_G, "__ZEN_UI_NAVBAR_HEIGHT")) or 0
    local hard_body_h = Screen:getHeight() - tb_h - navbar_h
    if hard_body_h < 1 then hard_body_h = Screen:getHeight() - tb_h end
    if body_h < 1 then body_h = hard_body_h end
    if body_h > hard_body_h then body_h = hard_body_h end
    local body_w = menu.inner_dimen and menu.inner_dimen.w or Screen:getWidth()
    local side_pad = math.max(2, math.min(Screen:scaleBySize(8), math.floor(body_w * 0.025)))
    if side_pad * 2 >= body_w then
        side_pad = math.max(0, math.floor(body_w * 0.04))
    end
    local content_w = math.max(1, body_w - side_pad * 2)
    local right_pad = math.max(0, body_w - content_w - side_pad)
    local page_pad = 0
    local layout_h = math.max(1, body_h - page_pad * 2)
    local row_gap = 0
    local max_row_gap = 0
    if #rows > 1 then
        local base_gap = math.max(4, Screen:scaleBySize(8))
        local max_gaps_h = math.floor(layout_h * 0.08)
        row_gap = math.min(base_gap, math.floor(max_gaps_h / (#rows - 1)))
        max_row_gap = math.max(row_gap, Screen:scaleBySize(10))
    end
    local gaps_h = row_gap * math.max(0, #rows - 1)
    local rows_h_budget = layout_h - gaps_h
    if rows_h_budget < #rows then rows_h_budget = math.max(1, layout_h) end

    local row_heights = compute_row_heights(rows, rows_h_budget)
    local rows_h_used = 0
    for _i, row in ipairs(row_heights) do
        rows_h_used = rows_h_used + (row.h or 0)
    end
    local extra_spacing_h = rows_h_budget - rows_h_used
    if extra_spacing_h > 0 then
        local grown = grow_row_heights_by_priority(row_heights, extra_spacing_h)
        extra_spacing_h = extra_spacing_h - grown
    end
    if extra_spacing_h > 0 and #rows > 1 and row_gap < max_row_gap then
        local gap_room = max_row_gap - row_gap
        local add_each = math.floor(extra_spacing_h / (#rows - 1))
        if add_each > gap_room then add_each = gap_room end
        if add_each > 0 then
            row_gap = row_gap + add_each
            extra_spacing_h = extra_spacing_h - add_each * (#rows - 1)
        end
    end
    local extra_top_pad = 0
    if extra_spacing_h > 0 then extra_top_pad = math.floor(extra_spacing_h / 2) end

    local face_title = Font:getFace("smallinfofont", Screen:scaleBySize(24))
    local face_value = Font:getFace("smallinfofont", Screen:scaleBySize(20))
    local face_label = Font:getFace("smallinfofont", Screen:scaleBySize(16))
    local row_title_face = Font:getFace("smallinfofont", Screen:scaleBySize(13))
    local row_title_gap = Screen:scaleBySize(3)

    local FileManager = require("apps/filemanager/filemanager")
    local filemanagerutil = require("apps/filemanager/filemanagerutil")

    local function open_book(path)
        if not path then return end
        local fm = FileManager.instance
        if filemanagerutil.openFile then
            filemanagerutil.openFile(fm, path)
        elseif fm and type(fm.openFile) == "function" then
            fm:openFile(path)
        end
    end

    local function show_book_context_menu(path, source)
        if type(path) ~= "string" or path == "" then return false end
        local fm = FileManager.instance
        local fc = fm and fm.file_chooser
        if not (fc and type(fc.showFileDialog) == "function") then return false end
        fc:showFileDialog({
            path = path,
            is_file = true,
            _zen_home_context = true,
            _zen_disable_select = true,
            _zen_is_history = source == "recently_read",
        })
        return true
    end

    local function shift_strip(source_key, count, order_key, direction, component_id)
        if not (data_provider and type(data_provider.shiftStrip) == "function") then return false end
        return data_provider:shiftStrip(source_key, count, order_key, direction, component_id)
    end

    local top_tap_zone_h = math.max(1, math.floor(Screen:getHeight() * 0.05))
    local function open_top_menu(ges)
        if not (ges and ges.pos and ges.pos.y < top_tap_zone_h) then return false end
        local fm = FileManager.instance
        local fm_menu = fm and fm.menu
        if fm_menu and fm_menu.activation_menu ~= "swipe" then
            fm_menu:onShowMenu(fm_menu:_getTabIndexFromLocation(ges))
            return true
        end
        return false
    end

    local children = { align = "left" }
    local used_h = 0
    local top_pad = page_pad + extra_top_pad
    if top_pad > 0 then
        table.insert(children, VerticalSpan:new{ width = top_pad })
        used_h = used_h + top_pad
    end

    local function title_for_component(comp_id)
        return MODULE_TITLES[comp_id]
    end

    for i, comp in ipairs(rows) do
        local h = row_heights[i] and row_heights[i].h or 120
        local module_cfg = type(dcfg.modules) == "table" and dcfg.modules[comp.id] or nil
        local show_row_title = not (module_cfg and module_cfg.show_module_title == false)
        local row_title = title_for_component(comp.id) or comp.title or comp.label or ""
        local title_h = 0
        local title_widget = nil
        if show_row_title and row_title ~= "" then
            title_widget = TextWidget:new{ text = row_title, face = row_title_face, bold = true }
            title_h = title_widget:getSize().h
        end
        local content_h = h
        local title_gap_h = title_h > 0 and row_title_gap or 0
        if title_widget then
            local reserved = title_h + title_gap_h
            if h > reserved + 20 then
                content_h = h - reserved
            else
                -- Hide row title when space is constrained, so widget content fits.
                title_widget = nil
                title_h = 0
                title_gap_h = 0
                content_h = h
            end
        end
        if content_h < 1 then content_h = 1 end
        local row_ctx = {
            width = content_w,
            height = content_h,
            config = dcfg,
            data = data_provider,
            openBook = open_book,
            showBookMenu = show_book_context_menu,
            shiftStrip = shift_strip,
            openTopMenu = open_top_menu,
            buildStatusRow = _zen_shared and _zen_shared.buildStatusRow,
            face_title = face_title,
            face_value = face_value,
            face_label = face_label,
            component_id = comp.id,
            module_cfg = module_cfg,
            is_first_row = i == 1,
        }
        local ok_widget, widget = pcall(comp.build, row_ctx)
        if ok_widget and widget then
            local final_widget = widget
            if title_widget then
                final_widget = VerticalGroup:new{
                    align = "left",
                    LeftContainer:new{
                        dimen = Geom:new{ w = content_w, h = title_h },
                        title_widget,
                    },
                    VerticalSpan:new{ width = title_gap_h },
                    widget,
                }
            end
            table.insert(children, FrameContainer:new{
                width = content_w,
                height = h,
                padding = 0,
                bordersize = 0,
                background = Blitbuffer.COLOR_WHITE,
                final_widget,
            })
            used_h = used_h + h
        else
            logger.warn("zen-ui home: failed to build component:", comp.id, widget)
        end
        if row_gap > 0 and i < #rows then
            table.insert(children, VerticalSpan:new{ width = row_gap })
            used_h = used_h + row_gap
        end
    end

    if used_h < body_h then
        table.insert(children, VerticalSpan:new{ width = body_h - used_h })
    end

    return HorizontalGroup:new{
        HorizontalSpan:new{ width = side_pad },
        FrameContainer:new{
            width = content_w,
            height = body_h,
            padding = 0,
            bordersize = 0,
            background = Blitbuffer.COLOR_WHITE,
            VerticalGroup:new(children),
        },
        HorizontalSpan:new{ width = right_pad },
    }
end

local function rows_need_clock_rebuild(rows, dcfg)
    for _i, comp in ipairs(rows or {}) do
        if comp.id == "datetime" then
            return true
        end
        if comp.id == "featured_recent" or comp.id == "featured_custom" or comp.id == "featured_tbr" then
            local mcfg = type(dcfg.modules) == "table" and dcfg.modules[comp.id] or nil
            if mcfg and mcfg.show_status_bar == true then
                return true
            end
        end
    end
    return false
end

function M.showHomeView(injectNavbar)
    local UIManager = require("ui/uimanager")

    refresh_shared_state()
    _home_inject_navbar = injectNavbar
    local cfg = load_zen_config()
    if type(cfg) ~= "table" then return end
    local dcfg = ensure_home_cfg()
    local show_status_bar = dcfg.show_status_bar ~= false

    local menu = StandalonePage.create_menu{
        name = "home",
        title = " ",
        no_title = not show_status_bar,
    }
    StandalonePage.prepare_shell(menu)

    local createStatusRow = _zen_shared and _zen_shared.createStatusRow
    local createStatusRowCustomBack = _zen_shared and _zen_shared.createStatusRowCustomBack
    local repaintTitleBar = _zen_shared and _zen_shared.repaintTitleBar
    if show_status_bar then
        StandalonePage.apply_status_row(menu, {
            createStatusRow = createStatusRow,
            createStatusRowCustomBack = createStatusRowCustomBack,
            repaintTitleBar = repaintTitleBar,
        })
    end
    menu._zen_home_show_status_bar = show_status_bar

    local rows = resolve_rows(dcfg)
    local data_provider = build_data_provider(cfg, dcfg)
    local needs_clock_rebuild = rows_need_clock_rebuild(rows, dcfg)
    menu._zen_home_needs_clock_rebuild = needs_clock_rebuild

    local function rebuild(refresh_stats)
        if data_provider then
            if type(data_provider.prepareStats) == "function" then
                data_provider:prepareStats(rows, refresh_stats == true)
            elseif refresh_stats and type(data_provider.refreshStats) == "function" then
                data_provider:refreshStats(rows)
            end
        end
        local content = build_home_content(menu, dcfg, rows, data_provider)
        StandalonePage.mount_body(menu, content)
        UIManager:setDirty(menu, "ui")
    end

    if show_status_bar then
        local status_refresh = menu._zen_status_refresh
        menu._zen_status_refresh = function(self, ...)
            local target = type(self) == "table" and self or menu
            if status_refresh then
                status_refresh(target, ...)
            end
            if needs_clock_rebuild and target and target._home_rebuild then
                target:_home_rebuild()
            end
        end
    else
        menu._zen_status_refresh = nil
    end
    if not show_status_bar and needs_clock_rebuild then
        pcall(function()
            require("common/clock_timer").bind(menu, function(target)
                if target and target._home_rebuild then
                    target:_home_rebuild()
                end
            end)
        end)
    end

    function menu:_home_rebuild(refresh_stats, reload_config)
        refresh_shared_state()
        if reload_config == true then
            local next_cfg = load_zen_config()
            if type(next_cfg) == "table" then
                cfg = next_cfg
                dcfg = ensure_home_cfg()
                data_provider = build_data_provider(cfg, dcfg)
            end
        end
        rows = resolve_rows(dcfg)
        needs_clock_rebuild = rows_need_clock_rebuild(rows, dcfg)
        self._zen_home_needs_clock_rebuild = needs_clock_rebuild
        rebuild(refresh_stats == true)
    end

    menu.close_callback = function()
        UIManager:close(menu)
        _home_menu = nil
    end

    local orig_onCloseWidget = menu.onCloseWidget
    function menu:onCloseWidget(...)
        if rawequal(_home_menu, self) then
            _home_menu = nil
        end
        pcall(function()
            require("common/clock_timer").unbind(self)
        end)
        if self.item_group and type(self.item_group.free) == "function" then
            pcall(function() self.item_group:free() end)
            while #self.item_group > 0 do table.remove(self.item_group) end
        end
        if orig_onCloseWidget then
            return orig_onCloseWidget(self, ...)
        end
    end

    _home_menu = menu

    if injectNavbar then
        injectNavbar(menu, "home")
    end

    UIManager:show(menu)
    UIManager:nextTick(function()
        rebuild(true)
        if menu._zen_status_refresh then
            menu:_zen_status_refresh()
        end
    end)
end

function M.getActivePage()
    return _home_menu and (_home_menu.page or 1)
end

function M.rebuildActive()
    if _home_menu and _home_menu._home_rebuild then
        local cfg = load_zen_config()
        local dcfg = type(cfg) == "table" and ensure_home_cfg() or nil
        local show_status_bar = not dcfg or dcfg.show_status_bar ~= false
        local needs_clock_rebuild = false
        if dcfg then
            needs_clock_rebuild = rows_need_clock_rebuild(resolve_rows(dcfg), dcfg)
        end
        if _home_menu._zen_home_show_status_bar ~= show_status_bar
                or _home_menu._zen_home_needs_clock_rebuild ~= needs_clock_rebuild then
            local UIManager = require("ui/uimanager")
            UIManager:close(_home_menu)
            _home_menu = nil
            M.showHomeView(_home_inject_navbar)
            return true
        end
        _home_menu:_home_rebuild(true, true)
        return true
    end
    return false
end

function M.hasActive()
    return _home_menu ~= nil
end

function M.isActiveOnTop()
    if not _home_menu then return false end
    local UIManager = require("ui/uimanager")
    local stack = UIManager._window_stack
    local top = stack and stack[#stack]
    return top and top.widget == _home_menu
end

function M.closeAll()
    if _home_menu then
        local UIManager = require("ui/uimanager")
        UIManager:close(_home_menu)
        _home_menu = nil
    end
end

local function register_home_api(zen_plugin)
    if not zen_plugin or type(zen_plugin.config) ~= "table" then return end
    _zen_shared = SharedState.register(zen_plugin, { home = M })
    _zen_plugin = zen_plugin
end

SharedState.registerLoader("home", register_home_api)

return function()
    register_home_api(rawget(_G, "__ZEN_UI_PLUGIN"))
end
