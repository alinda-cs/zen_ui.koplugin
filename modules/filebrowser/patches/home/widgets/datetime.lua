local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local FrameContainer = require("ui/widget/container/framecontainer")
local TextWidget = require("ui/widget/textwidget")

local function time_text()
    local gs = rawget(_G, "G_reader_settings")
    local twelve_hour = gs and gs:isTrue("twelve_hour_clock")
    local text = os.date(twelve_hour and "%I:%M" or "%H:%M")
    if twelve_hour then
        text = text:gsub("^0(%d:)", "%1")
    end
    return text
end

local function date_text()
    local t = os.date("*t")
    local weekday = os.date("%A")
    local month = os.date("%B")
    return weekday .. ", " .. month .. " " .. tostring(t.day)
end

return {
    id = "datetime",
    label = "Date/time widget",
    size = { preferred_pct = 0.18, min_pct = 0.10, max_pct = 0.40, grow_priority = 2 },
    build = function(ctx)
        local width = ctx.width
        local height = ctx.height
        local Screen = Device.screen
        local time_str = time_text()
        local date_str = date_text()
        local date_gap = math.max(1, Screen:scaleBySize(2))
        local max_content_h = math.max(1, height - Screen:scaleBySize(2))
        local time_widget
        local date_widget
        local time_size
        local date_size
        local time_h
        local date_h
        local content_h
        local time_date_overlap = 0

        local max_time_px = math.max(22, math.min(56, math.floor(height * 0.48)))
        local min_time_px = 4
        for time_px = max_time_px, min_time_px, -1 do
            local date_px = math.max(8, math.min(18, math.floor(time_px * 0.36)))
            local tw = TextWidget:new{
                text = time_str,
                face = Font:getFace("smallinfofont", Screen:scaleBySize(time_px)),
                bold = true,
            }
            local dw = TextWidget:new{
                text = date_str,
                face = Font:getFace("smallinfofont", Screen:scaleBySize(date_px)),
                fgcolor = Blitbuffer.COLOR_GRAY_3,
            }
            local ts = tw:getSize()
            local ds = dw:getSize()
            local th = ts.h or 18
            local dh = ds.h or 10
            local overlap = math.floor(th * 0.16)
            local ch = th - overlap + date_gap + dh
            if ch <= max_content_h or time_px == min_time_px then
                time_widget = tw
                date_widget = dw
                time_size = ts
                date_size = ds
                time_h = th
                date_h = dh
                content_h = ch
                time_date_overlap = overlap
                break
            end
            if tw.free then tw:free() end
            if dw.free then dw:free() end
        end

        local first_row_trim = math.floor((time_h or 0) * 0.20)
        -- center text block vertically within the widget
        local top = ctx.is_first_row
            and math.floor((height - content_h - first_row_trim) / 2)
            or math.floor((height - content_h) / 2)

        local content = {
            dimen = Geom:new{ w = width, h = height },
            getSize = function(self)
                return self.dimen
            end,
            handleEvent = function()
                return false
            end,
            paintTo = function(_self, bb, x, y)
                local time_x = x + math.floor((width - (time_size.w or 0)) / 2)
                local date_x = x + math.floor((width - (date_size.w or 0)) / 2)
                local time_y = y + top
                local date_y = math.min(y + height - date_h, time_y + time_h - time_date_overlap + date_gap)
                time_widget:paintTo(bb, time_x, time_y)
                date_widget:paintTo(bb, date_x, date_y)
            end,
        }

        return FrameContainer:new{
            width = width,
            height = height,
            padding = 0,
            bordersize = 0,
            background = Blitbuffer.COLOR_WHITE,
            content,
        }
    end,
}
