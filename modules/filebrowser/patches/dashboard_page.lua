local logger = require("logger")
local ConfigManager = require("config/manager")
local book_status = require("common/book_status")
local Blitbuffer = require("ffi/blitbuffer")
local QUOTES = require("common/dashboard_quotes")
local DashboardPresets = require("common/dashboard_presets")
local Registry = require("modules/filebrowser/patches/dashboard/components/registry")
local StandalonePage = require("modules/filebrowser/patches/standalone_page")

local M = {}

local _dashboard_menu = nil
local _zen_shared = nil
local _zen_plugin = nil

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
    return mcfg
end

local function ensure_strip_module_cfg(dcfg, module_id)
    local mcfg = ensure_module_cfg(dcfg, module_id)
    mcfg.order = normalize_order(mcfg.order)
    if type(mcfg.count) ~= "number" then mcfg.count = 5 end
    if mcfg.count < 3 then mcfg.count = 3 end
    if mcfg.count > 5 then mcfg.count = 5 end
    if mcfg.show_strip_titles == nil then mcfg.show_strip_titles = false end
    return mcfg
end

local function ensure_dashboard_widget_cfg(dcfg)
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

local function save_zen_config(cfg)
    if type(cfg) ~= "table" then return end
    if _zen_plugin and _zen_plugin.config == cfg and type(_zen_plugin.saveConfig) == "function" then
        _zen_plugin:saveConfig()
        return
    end
    pcall(ConfigManager.save, cfg)
    if _zen_plugin and type(_zen_plugin.config) == "table" then
        _zen_plugin.config = cfg
    end
end

local function ensure_dashboard_cfg(cfg)
    if type(cfg.group_view) ~= "table" then cfg.group_view = {} end
    if type(cfg.group_view.dashboard_page) ~= "table" then cfg.group_view.dashboard_page = {} end
    local dcfg = cfg.group_view.dashboard_page
    DashboardPresets.ensurePresetState(dcfg)

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

    -- Per-widget dashboard settings.
    for _i, comp in ipairs(Registry.list()) do
        ensure_module_cfg(dcfg, comp.id)
    end
    ensure_dashboard_widget_cfg(dcfg)

    return dcfg
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
    if #QUOTES == 0 then return 1 end
    return (get_quote_day_index() % #QUOTES) + 1
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
        if ok_stats and StatsDB and type(StatsDB.queryDashboardStats) == "function" then
            stats_cached = StatsDB.queryDashboardStats(fields) or {}
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
        local ok_ds, DocSettings = pcall(require, "docsettings")
        if ok_ds and DocSettings and DocSettings:hasSidecarFile(path) then
            local ok_doc, doc = pcall(DocSettings.open, DocSettings, path)
            if ok_doc and doc then
                pct = doc:readSetting("percent_finished")
                local summary = doc:readSetting("summary")
                status = summary and summary.status
                if not pages then
                    local stats = doc:readSetting("stats")
                    pages = stats and stats.pages
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

    function provider:getBooksForStrip(source_key, count, order_key)
        local n = tonumber(count) or 5
        if n < 1 then n = 1 end
        local source = source_key
        if source ~= "custom_strip" and source ~= "currently_reading" and source ~= "to_be_read" then
            source = "recently_read"
        end
        local paths = collect_paths_for_source(source, n + 1)

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

        local books = {}
        for _i, path in ipairs(paths) do
            local book = get_book(path)
            if book then
                table.insert(books, book)
                if #books >= n then break end
            end
        end
        return books
    end

    function provider:getCurrentQuote()
        local idx
        local quote_cfg = dcfg.quotes or {}
        if quote_cfg.day_seed == get_quote_day_index() and type(quote_cfg.manual_index) == "number" then
            idx = quote_cfg.manual_index
        else
            idx = get_daily_quote_index()
        end
        if idx < 1 then idx = 1 end
        if idx > #QUOTES then idx = ((idx - 1) % #QUOTES) + 1 end
        return QUOTES[idx]
    end

    function provider:nextQuote()
        local quote_cfg = dcfg.quotes or {}
        if type(quote_cfg.manual_index) ~= "number" then
            quote_cfg.manual_index = get_daily_quote_index()
        end
        quote_cfg.manual_index = quote_cfg.manual_index + 1
        if quote_cfg.manual_index > #QUOTES then quote_cfg.manual_index = 1 end
        quote_cfg.day_seed = get_quote_day_index()
        dcfg.quotes = quote_cfg
        save_zen_config(cfg)
        if _dashboard_menu and _dashboard_menu._dashboard_rebuild then
            _dashboard_menu:_dashboard_rebuild()
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

local function compute_row_heights(rows, body_h)
    local specs = {}
    local total_min = 0

    for _i, comp in ipairs(rows) do
        local size = comp.size or {}
        local pref = tonumber(size.preferred) or 120
        local min_h = tonumber(size.min) or math.max(60, math.floor(pref * 0.7))
        local max_h = tonumber(size.max) or math.max(pref, min_h)
        local id = comp.id or ""
        table.insert(specs, {
            id = id,
            is_strip = id == "strip" or id:match("^strip_") ~= nil,
            is_featured = id == "featured" or id:match("^featured_") ~= nil,
            is_datetime = id == "datetime",
            pref = pref,
            min = min_h,
            max = max_h,
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

    while total < body_h do
        local grew = false
        for _i, sp in ipairs(specs) do
            if total >= body_h then break end
            if sp.h < sp.max then
                sp.h = sp.h + 1
                total = total + 1
                grew = true
            end
        end
        if not grew then break end
    end

    return specs
end

local function grow_row_heights_evenly(row_heights, extra_px)
    local remaining = tonumber(extra_px) or 0
    local grown = 0
    if remaining <= 0 then
        return grown
    end
    while remaining > 0 do
        local grew = false
        for _i, row in ipairs(row_heights) do
            if remaining <= 0 then break end
            local max_h = tonumber(row.max) or tonumber(row.h) or 0
            local cur_h = tonumber(row.h) or 0
            if cur_h < max_h then
                row.h = cur_h + 1
                remaining = remaining - 1
                grown = grown + 1
                grew = true
            end
        end
        if not grew then break end
    end
    return grown
end

local function build_dashboard_content(menu, cfg, dcfg, rows, data_provider)
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

    local tb = menu.title_bar
    local tb_h = tb and tb:getSize().h or 0
    local menu_h = menu.height or (menu.inner_dimen and menu.inner_dimen.h or menu.dimen.h)
    local body_h = menu_h - tb_h
    local navbar_h = tonumber(rawget(_G, "__ZEN_UI_NAVBAR_HEIGHT")) or 0
    local hard_body_h = Screen:getHeight() - tb_h - navbar_h
    if hard_body_h < 1 then hard_body_h = Screen:getHeight() - tb_h end
    if body_h < 1 then body_h = hard_body_h end
    if body_h > hard_body_h then body_h = hard_body_h end
    local body_w = menu.inner_dimen and menu.inner_dimen.w or Screen:getWidth()
    local side_pad = Screen:scaleBySize(10) -- keep dashboard body gutters aligned with status bar edge padding
    if side_pad * 2 >= body_w then
        side_pad = math.max(0, math.floor(body_w * 0.08))
    end
    local content_w = math.max(1, body_w - side_pad * 2)
    local right_pad = math.max(0, body_w - content_w - side_pad)
    local page_pad = math.max(2, Screen:scaleBySize(4))
    if page_pad * 2 >= body_h then
        page_pad = math.max(0, math.floor((body_h - 1) / 2))
    end
    local layout_h = math.max(1, body_h - page_pad * 2)
    local row_gap = 0
    if #rows > 1 then
        row_gap = math.max(1, math.floor(Screen:scaleBySize(3)))
    end
    local max_row_gap = #rows > 1 and math.max(row_gap, math.floor(Screen:scaleBySize(6))) or 0
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
        local grown = grow_row_heights_evenly(row_heights, extra_spacing_h)
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
    if extra_spacing_h > 0 then
        extra_top_pad = math.floor(extra_spacing_h / 2)
    end

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
            logger.warn("zen-ui dashboard: failed to build component:", comp.id, widget)
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

function M.showDashboardView(injectNavbar)
    local UIManager = require("ui/uimanager")

    local cfg = load_zen_config()
    if type(cfg) ~= "table" then return end
    local dcfg = ensure_dashboard_cfg(cfg)

    local menu = StandalonePage.create_menu{
        name = "dashboard",
        title = " ",
    }
    StandalonePage.prepare_shell(menu)

    local createStatusRow = _zen_shared and _zen_shared.createStatusRow
    local createStatusRowCustomBack = _zen_shared and _zen_shared.createStatusRowCustomBack
    local repaintTitleBar = _zen_shared and _zen_shared.repaintTitleBar
    StandalonePage.apply_status_row(menu, {
        createStatusRow = createStatusRow,
        createStatusRowCustomBack = createStatusRowCustomBack,
        repaintTitleBar = repaintTitleBar,
    })

    local rows = resolve_rows(dcfg)
    local data_provider = build_data_provider(cfg, dcfg)

    local function rebuild(refresh_stats)
        if data_provider then
            if type(data_provider.prepareStats) == "function" then
                data_provider:prepareStats(rows, refresh_stats == true)
            elseif refresh_stats and type(data_provider.refreshStats) == "function" then
                data_provider:refreshStats(rows)
            end
        end
        local content = build_dashboard_content(menu, cfg, dcfg, rows, data_provider)
        StandalonePage.mount_body(menu, content)
        UIManager:setDirty(menu, "ui")
    end

    local status_refresh = menu._zen_status_refresh
    menu._zen_status_refresh = function(self, ...)
        local target = type(self) == "table" and self or menu
        if status_refresh then
            status_refresh(target, ...)
        end
        for _i, comp in ipairs(rows) do
            if comp.id == "datetime" then
                if target and target._dashboard_rebuild then
                    target:_dashboard_rebuild()
                end
                break
            end
        end
    end

    function menu:_dashboard_rebuild(refresh_stats)
        rows = resolve_rows(dcfg)
        rebuild(refresh_stats == true)
    end

    menu.close_callback = function()
        UIManager:close(menu)
        _dashboard_menu = nil
    end

    local orig_onCloseWidget = menu.onCloseWidget
    function menu:onCloseWidget(...)
        if rawequal(_dashboard_menu, self) then
            _dashboard_menu = nil
        end
        pcall(function()
            require("common/clock_timer").unbind(self)
        end)
        if orig_onCloseWidget then
            return orig_onCloseWidget(self, ...)
        end
    end

    _dashboard_menu = menu

    if injectNavbar then
        injectNavbar(menu, "dashboard")
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
    return _dashboard_menu and (_dashboard_menu.page or 1)
end

function M.rebuildActive()
    if _dashboard_menu and _dashboard_menu._dashboard_rebuild then
        _dashboard_menu:_dashboard_rebuild()
        return true
    end
    return false
end

function M.closeAll()
    if _dashboard_menu then
        local UIManager = require("ui/uimanager")
        UIManager:close(_dashboard_menu)
        _dashboard_menu = nil
    end
end

return function()
    local zen_plugin = rawget(_G, "__ZEN_UI_PLUGIN")
    if not zen_plugin or type(zen_plugin.config) ~= "table" then return end
    if not zen_plugin._zen_shared then zen_plugin._zen_shared = {} end
    _zen_shared = zen_plugin._zen_shared
    _zen_plugin = zen_plugin
    zen_plugin._zen_shared.dashboard = M
end
