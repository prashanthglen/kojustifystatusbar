--[[
    This user patch attempts to provide dynamic spacing between multiple items in the "Status Bar"
    without affecting any of the other entries present.
    - [x] replace the dynamic filler text generator so that it 
        does not conflict with our changes
    - [x] rewrite the genAllFooterText so that we can generate the
        text first and then replace all the separators with custom spacing.
    - [x] add menu entries to toggle this feature.
    |   Status bar > Configure items > Alignment > Justify
    - [ ] allow for grouping of entries.
    
--]]

local BD = require("ui/bidi")
local TextWidget = require("ui/widget/textwidget")
local ReaderFooter = require("apps/reader/modules/readerfooter")
local logger = require("logger")
local _ = require("gettext")

local _ReaderFooter_init_orig = ReaderFooter.init
local _ReaderFooter_genAllFooterText_orig = ReaderFooter.genAllFooterText
local _ReadeFooter_dynamicFiller_orig = ReaderFooter.textGeneratorMap.dynamic_filler

local new_filler_func = function(footer)
	if footer.settings.align ~= "justify" then
		logger.dbg("[justiify-status-bar] Justify not set. Calling original dynamic filler function.")
		return _ReadeFooter_dynamicFiller_orig(footer)
	end
	logger.dbg("[justiify-status-bar] Disabling dynamic filler as alingment is set to justify.")
	if not footer.settings.disable_progress_bar then
		if footer.settings.progress_bar_position == "alongside" then
			return
		end
	end
	return "", false
end

local getTextLength = function(footer, text)
	local text_widget = TextWidget:new({
		text = text,
		face = footer.footer_text_face,
		bold = footer.settings.text_font_bold,
	})
	return text_widget:getSize().w
end

local calculate_spaces = function(footer, texts, lengths)
	if #texts == 1 then
		return texts
	end
	local tot_width = footer.dimen.w
	if footer.settings.progress_margin and not footer.settings.disable_progress_bar then
		tot_width = footer.progress_bar.width
	end
	-- get the width of a space
	local filler_space = " "
	local filler_space_width = getTextLength(footer, filler_space)
	local num_fillers = #lengths - 1
	local tot_text_space = 1
	for i = 1, #lengths do
		tot_text_space = tot_text_space + lengths[i]
	end
	local empty_space = tot_width - tot_text_space
	-- this table contains the start location from where each item will be placed
	-- based on how far the next items is, that many spaces will be added to it.
	local item_spacing = math.floor(empty_space / num_fillers)
	local large_item_spaces = empty_space % num_fillers
	-- append spaces to every element to create a gap
	for i = 1, #lengths - 1 do
		-- get the location spacing to the next entry
		local space_to_fill = item_spacing
		if i <= large_item_spaces then
			space_to_fill = space_to_fill + 1
		end
		local num_spaces = math.floor(space_to_fill / filler_space_width)
		-- append the spaces to the current text to create the spacing
		texts[i] = BD.wrap(texts[i] .. filler_space:rep(num_spaces))
	end
	return texts
end

ReaderFooter.init = function(self)
	if ReaderFooter.textGeneratorMap then
		if ReaderFooter.textGeneratorMap.dynamic_filler then
			ReaderFooter.textGeneratorMap.dynamic_filler = new_filler_func
			logger.dbg("[justiify-status-bar] textGeneratorMap dynamic filler exists and is replaced.")
		end
	end
	_ReaderFooter_init_orig(self)
	logger.info("[justiify-status-bar] 2-justify-status-bar.lua patch initialized successfully.")
end

function ReaderFooter.genAllFooterText(self, gen_to_skip)
	-- if alignment is not set to Justify, then use original text generation
	if self.settings.align ~= "justify" then
		return _ReaderFooter_genAllFooterText_orig(self, gen_to_skip)
	end
	-- The lines below until the end of the for loop belong to the original
	-- genAllFooterText function. We copy the whole function because we need
	-- it to return only the table and not the line of text.
	local info = {}
	local lengths = {}
	-- We need to BD.wrap() all items and separators, so we're
	-- sure they are laid out in our order (reversed in RTL),
	-- without ordering by the RTL Bidi algorithm.
	local count = 0 -- total number of visible items
	local prev_had_merge
	for _, gen in ipairs(self.footerTextGenerators) do
		-- Skip empty generators, so they don't generate bogus separators
		local text, merge = gen(self)
		if text and text ~= "" then
			count = count + 1
			if self.settings.item_prefix == "compact_items" then
				-- remove whitespace from footer items if symbol_type is compact_items
				-- use a hair-space to avoid issues with RTL display
				text = text:gsub("%s", "\u{200A}")
			end
			-- if generator request a merge of this item, add it directly,
			-- i.e. no separator before and after the text then.
			if merge then
				local merge_pos = #info == 0 and 1 or #info
				info[merge_pos] = (info[merge_pos] or "") .. text
				prev_had_merge = true
			elseif prev_had_merge then
				info[#info] = info[#info] .. text
				prev_had_merge = false
			else
				-- store the size of the text so that we can use it
				-- later to calculate locations of the various entries
				table.insert(lengths, getTextLength(self, text))
				table.insert(info, text)
			end
		end
	end
	info = calculate_spaces(self, info, lengths)
	local out = table.concat(info)
	logger.dbg(
		string.format(
			"[justiify-status-bar] calculated text as: %s; total text lenght is: %d.",
			out,
			getTextLength(self, out)
		)
	)
	-- The below line belongs to the original genAllFooterText function and we will be replacing it.
	return out, false
end

-- Maybe it is just enough to rewrite the genAlignmentMenuItems to add justify option to it!!
local _ReaderFooter_genAlingmentMenuItems_orig = ReaderFooter.genAlignmentMenuItems
ReaderFooter.genAlignmentMenuItems = function(self, val)
	-- when a nil value is passed in, the current settings value is picked
	-- and its string value is returned. The original function will fail
	-- if nil is passed and the alignment settign is "justify".
	-- That is taken care of in the following if-condition
	if val == nil and self.settings.align == "justify" then
		return _("Justify")
	end
	if val ~= "justify" then
		return _ReaderFooter_genAlingmentMenuItems_orig(self, val)
	end
	-- return the entry for Justify option in the menu
	return {
		text = _("Justify"),
		checked_func = function()
			return self.settings.align == val
		end,
		callback = function()
			self.settings.align = val
			self:refreshFooter(true)
		end,
	}
end

-- Extract an entry from the menu
-- The menu entries are just table objects with no identifiers
-- and we have to do a graph search by comparing the text entry
-- This will return the first entry that starts with the text
-- `item_text`. The matching performed is case sensitive.
local function getEntryInMenu(menu_entry, item_text)
	if menu_entry.sub_item_table == nil then
		return nil
	end
	for _, entry in pairs(menu_entry.sub_item_table) do
		local text = entry.text
		if text == nil then
			text = entry.text_func()
		end
		-- found the text, return entry
		if string.find(text, item_text) == 1 then
			return entry
		end
		-- search through all the sub entries of this entry
		local found = getEntryInMenu(entry, item_text)
		if found ~= nil then
			return found
		end
	end
	return nil
end

-- Below function adds the justify option to the main menu
local _ReaderFooter_addToMainMenu = ReaderFooter.addToMainMenu
ReaderFooter.addToMainMenu = function(self, menu_items)
	_ReaderFooter_addToMainMenu(self, menu_items)
	-- find the alignment entry
	local alignment_entry = getEntryInMenu(menu_items.status_bar, "Alignment:")
	if alignment_entry == nil then
		logger.info("[justiify-status-bar] Could not find alignment entry in Menu, not adding justify option to it.")
		return
	end
	local dbg_text = alignment_entry.text_func()
	logger.dbg(string.format("Found entry with text: %s", dbg_text))
	table.insert(alignment_entry.sub_item_table, self.genAlignmentMenuItems(self, "justify"))
end
