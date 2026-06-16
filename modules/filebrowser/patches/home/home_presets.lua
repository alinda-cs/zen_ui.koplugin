local M = {}

M.DEFAULT_PRESET_NAME = "Zen Default"
M.CUSTOM_PRESET_NAME = "Custom preset"

local DEFAULT_HOME_PAGE = {
    title = M.DEFAULT_PRESET_NAME,
    rows = {
        max_rows = 5,
        order = {
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
        },
        enabled = {
            datetime = true,
            featured_custom = false,
            featured_recent = true,
            featured_tbr = false,
            quotes = true,
            reading_goals = false,
            stats_triplet = false,
            strip_custom = false,
            strip_recent = true,
            strip_tbr = false,
        },
    },
    middle_stats_triplet = {
        "today_pages",
        "today_duration",
        "streak",
    },
    goals = {
        daily_pages_target = 30,
        daily_target = 30,
        daily_time_target_min = 30,
        metric = "pages",
        period = "daily",
        weekly_pages_target = 210,
        weekly_target = 210,
        weekly_time_target_min = 210,
    },
    show_status_bar = true,
    modules = {
        datetime = {
            show_module_title = false,
        },
        featured_custom = {
            interactive = true,
            order = "default",
            path = nil,
            progress_meta = {
                left = "percent",
                right = "total_pages",
            },
            show_description = true,
            show_module_title = true,
            show_status_bar = false,
            status_bar_bold_text = true,
            status_bar_show_bottom_border = true,
        },
        featured_recent = {
            interactive = true,
            order = "default",
            progress_meta = {
                left = "percent",
                right = "total_pages",
            },
            show_description = true,
            show_module_title = false,
            show_status_bar = false,
            status_bar_bold_text = true,
            status_bar_show_bottom_border = true,
        },
        featured_tbr = {
            interactive = true,
            order = "default",
            progress_meta = {
                left = "percent",
                right = "total_pages",
            },
            show_description = true,
            show_module_title = true,
            show_status_bar = false,
            status_bar_bold_text = true,
            status_bar_show_bottom_border = true,
        },
        quotes = {
            show_module_title = false,
        },
        reading_goals = {
            show_module_title = false,
        },
        stats_triplet = {
            stat_style = "divider",
            show_module_title = false,
        },
        strip_custom = {
            count = 5,
            interactive = true,
            order = "default",
            paths = {},
            show_module_title = false,
            show_strip_titles = false,
        },
        strip_recent = {
            count = 5,
            interactive = true,
            order = "default",
            show_module_title = false,
            show_strip_titles = false,
        },
        strip_tbr = {
            count = 5,
            interactive = true,
            order = "default",
            show_module_title = false,
            show_strip_titles = false,
        },
    },
    quotes = {
        day_seed = 741666,
        manual_index = 11,
        show_author = true,
    },
}

local BOOKSHELF_HOME_PAGE = {
    title = "Bookshelf",
    rows = {
        max_rows = 5,
        order = {
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
        },
        enabled = {
            datetime = false,
            featured_custom = false,
            featured_recent = true,
            featured_tbr = false,
            quotes = false,
            reading_goals = false,
            stats_triplet = false,
            strip_custom = false,
            strip_recent = true,
            strip_tbr = false,
        },
    },
    middle_stats_triplet = {
        "today_pages",
        "today_duration",
        "streak",
    },
    goals = {
        daily_pages_target = 30,
        daily_target = 30,
        daily_time_target_min = 30,
        metric = "pages",
        period = "daily",
        weekly_pages_target = 210,
        weekly_target = 210,
        weekly_time_target_min = 210,
    },
    show_status_bar = false,
    modules = {
        datetime = {
            show_module_title = false,
        },
        featured_custom = {
            interactive = true,
            order = "default",
            progress_meta = {
                left = "percent",
                right = "total_pages",
            },
            show_description = true,
            show_module_title = true,
            show_status_bar = false,
            status_bar_bold_text = true,
            status_bar_show_bottom_border = true,
        },
        featured_recent = {
            interactive = true,
            order = "default",
            progress_meta = {
                left = "percent",
                right = "total_pages",
            },
            show_description = true,
            show_module_title = false,
            show_status_bar = true,
            status_bar_bold_text = true,
            status_bar_show_bottom_border = true,
        },
        featured_tbr = {
            interactive = true,
            order = "default",
            progress_meta = {
                left = "percent",
                right = "total_pages",
            },
            show_description = true,
            show_module_title = true,
            show_status_bar = false,
            status_bar_bold_text = true,
            status_bar_show_bottom_border = true,
        },
        quotes = {
            show_module_title = false,
        },
        reading_goals = {
            show_module_title = false,
        },
        stats_triplet = {
            stat_style = "divider",
            show_module_title = false,
        },
        strip_custom = {
            count = 5,
            interactive = true,
            order = "default",
            paths = {},
            show_badges = false,
            show_module_title = false,
            show_strip_titles = false,
            two_rows = false,
        },
        strip_recent = {
            count = 5,
            interactive = true,
            order = "default",
            show_badges = false,
            show_module_title = false,
            show_strip_titles = false,
            two_rows = true,
        },
        strip_tbr = {
            count = 5,
            interactive = true,
            order = "default",
            show_badges = false,
            show_module_title = false,
            show_strip_titles = false,
            two_rows = false,
        },
    },
    quotes = {
        day_seed = 741666,
        manual_index = 11,
        show_author = true,
    },
}

local HOME_KEYS = {
    "title",
    "rows",
    "middle_stats_triplet",
    "goals",
    "show_status_bar",
    "modules",
    "quotes",
}

local function deepcopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for key, val in pairs(value) do
        out[deepcopy(key, seen)] = deepcopy(val, seen)
    end
    return out
end

function M.copy(value)
    return deepcopy(value)
end

function M.defaultHomePage()
    local page = deepcopy(DEFAULT_HOME_PAGE)
    page.active_preset = M.DEFAULT_PRESET_NAME
    return page
end

function M.getBuiltinPresets()
    return {
        {
            name = M.DEFAULT_PRESET_NAME,
            builtin = true,
            home_page = deepcopy(DEFAULT_HOME_PAGE),
        },
        {
            name = "Bookshelf",
            builtin = true,
            home_page = deepcopy(BOOKSHELF_HOME_PAGE),
        },
    }
end

function M.isBuiltinPresetName(name)
    if type(name) ~= "string" then return false end
    for _i, preset in ipairs(M.getBuiltinPresets()) do
        if preset.name == name then return true end
    end
    return false
end

function M.ensurePresetState(dcfg)
    if type(dcfg.active_preset) ~= "string" or dcfg.active_preset == "" then
        dcfg.active_preset = nil
    end
end

function M.captureHomePage(dcfg)
    local out = {}
    for _i, key in ipairs(HOME_KEYS) do
        out[key] = deepcopy(dcfg[key])
    end
    return out
end

function M.applyHomePagePreset(dcfg, preset)
    if type(dcfg) ~= "table" or type(preset) ~= "table" then return end
    local source = type(preset.home_page) == "table" and preset.home_page or preset
    if source.title == nil and type(preset.name) == "string" then
        dcfg.title = preset.name
    end
    for _i, key in ipairs(HOME_KEYS) do
        if source[key] ~= nil then
            dcfg[key] = deepcopy(source[key])
        end
    end
end

return M
