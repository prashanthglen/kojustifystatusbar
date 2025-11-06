--[[
    This file is modified on top of https://github.com/patelneeraj/koreader-patches/blob/main/2-custom-header-footer.lua
    The aim is to allow for user selected items in the header and footer and place them apart with dynamic width.
--]]

local Blitbuffer = require("ffi/blitbuffer")
local TextWidget = require("ui/widget/textwidget")
local CenterContainer = require("ui/widget/container/centercontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local BD = require("ui/bidi")
local Size = require("ui/size")
local Geom = require("ui/geometry")
local Device = require("device")
local Font = require("ui/font")
local logger = require("logger")
local util = require("util")
local datetime = require("datetime")
local Screen = Device.screen
local _ = require("gettext")
local T = require("ffi/util").template
local ReaderView = require("apps/reader/modules/readerview")
local ReaderFooter = require("apps/reader/modules/readerfooter")

local _ReaderView_paintTo_orig = ReaderView.paintTo
local header_settings = G_reader_settings:readSetting("footer")
local screen_width = Screen:getWidth()
local screen_height = Screen:getHeight()

ReaderView.paintTo = function(self, bb, x, y)
	_ReaderView_paintTo_orig(self, bb, x, y)
	if self.render_mode ~= nil then
		return
	end -- Show only for epub-likes and never on pdf-likes
	-- don't change anything above this line

	-- ===========================!!!!!!!!!!!!!!!=========================== -
	-- Configure formatting options for header here, if desired
	local header_font_face = "ffont" -- this is the same font the footer uses
	-- header_font_face = "source/SourceSerif4-Regular.ttf" -- this is the serif font from Project: Title
	header_font_face = "droid/DroidSansMono.ttf"
	local header_font_size = 16 -- Will use your footer setting if available
	local header_font_bold = header_settings.text_font_bold or false -- Will use your footer setting if available
	--local header_font_color = Blitbuffer.COLOR_GRAY_2 -- black is the default, but there's 15 other shades to try
	local header_font_color = Blitbuffer.COLOR_GRAY_3 -- A nice dark gray, a bit lighter than black
	local header_top_padding = Size.padding.large -- replace small with default or large for more space at the top
	local header_bottom_padding = header_settings.container_height or 7
	local header_use_book_margins = true -- Use same margins as book for header
	local header_margin = Size.padding.large -- Use this instead, if book margins is set to false
	local left_max_width_pct = 40 -- this % is how much space the left corner can use before "truncating..."
	local right_max_width_pct = 40 -- this % is how much space the right corner can use before "truncating..."
	local center_max_width_pct = 84 -- this % is how much space the header can use before "truncating..."
	local separator = {
		bar = "|",
		bullet = "•",
		dot = "·",
		em_dash = "—",
		en_dash = "-",
	}
	-- ===========================!!!!!!!!!!!!!!!=========================== -

	-- You probably don't need to change anything in the section below this line
	-- Infos for whole book:
	local pageno = self.state.page or 1 -- Current page
	local pages = self.ui.doc_settings.data.doc_pages or 1
	local book_title = self.ui.doc_props.display_title or ""
	local page_progress = ("%d / %d"):format(pageno, pages)
	local pages_left_book = pages - pageno
	local percentage = math.floor((pageno / pages) * 100 + 0.5) -- rounds to nearest whole number
	local percentage_format = string.format("%d%%", percentage)

	-- Infos for current chapter:
	local book_chapter = self.ui.toc:getTocTitleByPage(pageno) or "" -- Chapter name
	local pages_chapter = self.ui.toc:getChapterPageCount(pageno) or pages
	local pages_left = self.ui.toc:getChapterPagesLeft(pageno) or self.ui.document:getTotalPagesLeft(pageno)
	local pages_done = self.ui.toc:getChapterPagesDone(pageno) or 0
	pages_done = pages_done + 1 -- This +1 is to include the page you're looking at
	local chapter_progress = pages_done .. " ⁄ ⁄ " .. pages_chapter
	-- Author(s):
	local book_author = self.ui.doc_props.authors
	if book_author:find("\n") then -- Show first author if multiple authors
		book_author = T(_("%1 et al."), util.splitToArray(book_author, "\n")[1] .. ",")
	end
	-- Clock:
	local time = datetime.secondsToHour(os.time(), G_reader_settings:isTrue("twelve_hour_clock"))
	-- Battery:
	local battery = ""
	if Device:hasBattery() then
		local powerd = Device:getPowerDevice()
		local batt_lvl = powerd:getCapacity() or 0
		local is_charging = powerd:isCharging() or false
		local batt_prefix = powerd:getBatterySymbol(powerd:isCharged(), is_charging, batt_lvl) or ""
		battery = ""
		if batt_lvl <= 50 then
			battery = batt_prefix .. batt_lvl .. "%"
		end
	end

	-- You probably don't need to change anything in the section above this line

	-- ===========================!!!!!!!!!!!!!!!=========================== -
	-- What you put here will show in the header:
	local header_left_text = ""
	local header_right_text = ""
	local header_center_text = ""

	-- Prepare footer text
	local lftext = time
	if battery ~= "" then
		lftext = battery .. separator.bar .. lftext
	end
	local footer_left_text = string.format("%s", lftext)
	local footer_right_text = string.format("%s%s%s", pageno, "/", pages)
	local footer_center_text = string.format("%s", book_title)

	-- Look up "string.format" in Lua if you need help.
	-- ===========================!!!!!!!!!!!!!!!=========================== -

	-- Helper Functions
	local margins = 0
	local left_margin = header_margin
	local right_margin = header_margin
	if header_use_book_margins then -- Set width % based on R + L margins
		left_margin = self.document:getPageMargins().left or header_margin
		right_margin = self.document:getPageMargins().right or header_margin
	end
	margins = left_margin + right_margin
	local avail_width = screen_width - margins -- deduct margins from width

	local function getFittedText(text, max_width_pct)
		if text == nil or text == "" then
			return ""
		end
		local text_widget = TextWidget:new({
			text = text:gsub(" ", "\u{00A0}"), -- no-break-space
			max_width = avail_width * max_width_pct * (1 / 100),
			face = Font:getFace(header_font_face, header_font_size),
			bold = header_font_bold,
			padding = 0,
		})
		local fitted_text, add_ellipsis = text_widget:getFittedText()
		text_widget:free()
		if add_ellipsis then
			fitted_text = fitted_text .. "…"
		end
		return BD.auto(fitted_text)
	end

	-- calculate dynamic spacing for entries in the list
	-- if there are multiple such entries, calculate for all of them
	local function getDynamicSpaceWidths(remaining_space, num_spaces)
		local min_width = math.floor(remaining_space / num_spaces)
		local extra = remaining_space % num_spaces
		local dynamic_spaces = {}
		for i = 1, num_spaces do
			dynamic_spaces[i] = min_width
			if i <= extra then
				dynamic_spaces[i] = dynamic_spaces[i] + 1
			end
		end
		return dynamic_spaces
	end

	-- creates a text widget with the required settings
	local function getTextWidget(text, max_width_pct, font_face, font_size, bold, color)
		return TextWidget:new({
			text = getFittedText(text, max_width_pct),
			face = Font:getFace(font_face, font_size),
			bold = bold,
			fgcolor = color,
			padding = 0,
		})
	end

	-- ====================================================================
	-- header set up
	if header_left_text .. header_right_text .. header_center_text == "" then
		local tw_header_left = getTextWidget(
			header_left_text,
			left_max_width_pct,
			header_font_face,
			header_font_size,
			header_font_bold,
			header_font_color
		)
		local tw_header_right = getTextWidget(
			header_right_text,
			left_max_width_pct,
			header_font_face,
			header_font_size,
			header_font_bold,
			header_font_color
		)
		local tw_header_center = getTextWidget(
			header_right_text,
			left_max_width_pct,
			header_font_face,
			header_font_size,
			header_font_bold,
			header_font_color
		)

		local space_remaining = screen_width
			- tw_header_left:getSize().w
			- tw_header_right:getSize().w
			- tw_header_center:getSize().w
			- margins
		local dynamic_header_spaces = getDynamicSpaceWidths(space_remaining, 2)

		local header = CenterContainer:new({
			dimen = Geom:new({
				w = screen_width,
				h = math.max(tw_header_left:getSize().h, tw_header_right:getSize().h, tw_header_center:getSize().h)
					+ header_top_padding,
			}),
			VerticalGroup:new({
				VerticalSpan:new({ width = header_top_padding }),
				HorizontalGroup:new({
					tw_header_left,
					HorizontalSpan:new({ width = dynamic_header_spaces[1] }),
					tw_header_center,
					HorizontalSpan:new({ width = dynamic_header_spaces[2] }),
					tw_header_right,
				}),
			}),
		})
		header:paintTo(bb, x, y)
		header:free()
	end

	local footer_font_face = header_font_face
	local footer_font_size = header_font_size
	local footer_font_bold = header_font_bold
	local footer_font_color = header_font_color

	local footer_bottom_padding = Size.padding.large -- space from bottom edge
	local footer_text_padding = 4

	-- Create text widgets
	local tw_footer_left = getTextWidget(
		footer_left_text,
		center_max_width_pct,
		footer_font_face,
		footer_font_size,
		footer_font_bold,
		footer_font_color
	)
	local tw_footer_right = getTextWidget(
		footer_right_text,
		center_max_width_pct,
		footer_font_face,
		footer_font_size,
		footer_font_bold,
		footer_font_color
	)
	local tw_footer_center = getTextWidget(
		footer_center_text,
		center_max_width_pct,
		footer_font_face,
		footer_font_size,
		footer_font_bold,
		footer_font_color
	)

	local space_remaining = screen_width
		- tw_footer_left:getSize().w
		- tw_footer_right:getSize().w
		- tw_footer_center:getSize().w
		- margins
	local dynamic_footer_spaces = getDynamicSpaceWidths(space_remaining, 2)

	-- Get the progress bar
	local prog_bar = ReaderFooter.progress_bar

	-- Footer Y-position (bottom of screen)
	local footer_height =
		math.max(tw_footer_left:getSize().h, tw_footer_right:getSize().h, tw_footer_center:getSize().h)
	if prog_bar then
		footer_height = footer_height + ReaderFooter.progress_bar:getSize().h
	end
	local footer_y = screen_height - footer_height - footer_bottom_padding

	local footer_contents = {
		HorizontalGroup:new({
			HorizontalSpan:new({ width = left_margin }),
			tw_footer_left,
			HorizontalSpan:new({ width = dynamic_footer_spaces[1] }),
			tw_footer_center,
			HorizontalSpan:new({ width = dynamic_footer_spaces[2] }),
			tw_footer_right,
			HorizontalSpan:new({ width = right_margin }),
		}),
	}

	if prog_bar then
		table.insert(footer_contents, ReaderFooter.progress_bar)
	end

	local footer = CenterContainer:new({
		dimen = Geom:new({
			w = screen_width,
			h = footer_height,
		}),
		VerticalGroup:new(footer_contents),
	})

	footer:paintTo(bb, x, footer_y)
	footer:free()
end
