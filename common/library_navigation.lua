local paths = require("common/paths")

local M = {}

function M.restoreEnabled(plugin)
    local features = plugin and plugin.config and plugin.config.features
    return type(features) == "table" and features.restore_library_view == true
end

function M.returnToRakuyomiReader(restore)
    if not restore and not G_reader_settings:isTrue("allow_commaneer_filemanager") then
        return false
    end
    local ok, MangaReader = pcall(require, "MangaReader")
    if not ok or type(MangaReader) ~= "table"
            or MangaReader.is_showing ~= true
            or type(MangaReader.onReturn) ~= "function" then
        return false
    end
    MangaReader:onReturn()
    return true
end

function M.showFromReader(ui, plugin)
    if not ui or not ui.document then return false end

    local file = ui.document.file
    local restore = M.restoreEnabled(plugin)
    local outside_home = file and not paths.isInHomeDir(file)

    ui:handleEvent(require("ui/event"):new("CloseConfigMenu"))
    if M.returnToRakuyomiReader(restore) then
        return true
    end

    ui:onClose()
    if type(ui.showFileManager) == "function" then
        if not restore and not outside_home then
            _G.__ZEN_UI_FORCE_DEFAULT_LIBRARY_TAB = true
        end
        if outside_home then
            _G.__ZEN_UI_KEEP_BOOK_LOCATION = true
        end
        ui:showFileManager(file)
    end
    return true
end

return M
