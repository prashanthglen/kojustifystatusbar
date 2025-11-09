--[[
    This user patch attempts to provide dynamic spacing between multiple items in the "Status Bar"
    without affecting any of the other entries present.
    - [x] replace the dynamic filler text generator so that it 
        does not conflict with our changes
    - [x] rewrite the genAllFooterText so that we can generate the
        text first and then replace all the separators with custom spacing.
    - [ ] add mennu entries to toggle this feature.
    - [ ] allow for grouping of entries.
    
--]]

local BD = require("ui/bidi")
local TextWidget = require("ui/widget/textwidget")
local ReaderFooter = require("apps/reader/modules/readerfooter")
local logger = require("logger")

local _ReaderFooter_init_orig = ReaderFooter.init
local _ReaderFooter_genAllFooterText_orig = ReaderFooter.genAllFooterText

local new_filler_func = function(footer)
	logger.dbg("[justiify-status-bar] Custom filler function called")
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
	-- this table contains the start location from where each item will be placed
	-- based on how far the next items is, that many spaces will be added to it.
	local item_spacing = math.floor(tot_width / num_fillers)
	local large_item_spaces = tot_width % num_fillers
	-- calculate midpoints for the items
	-- and hence the start locations for them
	-- this loop runs only if there are more than 2 items
	local width_covered = lengths[1]
	for i = 2, #lengths do
		-- get the location where the midpoint of the current entry should be placed
		local midpoint = item_spacing * (i - 1)
		if i <= large_item_spaces then
			midpoint = midpoint + 1
		end
		-- calculate the location of the item
		local item_pos = midpoint - math.floor(lengths[i] / 2)
		-- if this is the last item then it should be left aligned
		if i == #lengths then
			item_pos = tot_width - lengths[i]
		end
		-- figure out spacing and append the spaces to previous text entry
		local space_to_fill = item_pos - width_covered
		local num_spaces = math.floor(space_to_fill / filler_space_width)
		texts[i - 1] = BD.wrap(texts[i - 1] .. filler_space:rep(num_spaces))
		width_covered = width_covered + lengths[i] + space_to_fill
	end
	return texts
end

ReaderFooter.init = function(self)
	if ReaderFooter.textGeneratorMap then
		if ReaderFooter.textGeneratorMap.dynamic_filler then
			ReaderFooter.textGeneratorMap.dynamic_filler = new_filler_func
			logger.dbg("[justiify-status-bar] textGeneratorMap dynamic filler exists and is replaced")
		end
	end
	_ReaderFooter_init_orig(self)
	logger.info("[justiify-status-bar] 2-justify-status-bar.lua patch initialized successfully")
end

function ReaderFooter.genAllFooterText(self, gen_to_skip)
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
			"[justiify-status-bar] calculated text as: %s; total text lenght is: %d",
			out,
			getTextLength(self, out)
		)
	)
	-- The below line belongs to the original genAllFooterText function and we will be replacing it.
	return out, false
end
