--[[--
This is a plugin to justify all entries in the status bar so that they
are equally spaced apart.

@module koplugin.JustifyStatusBar
--]]
--

-- This is a debug plugin, remove the following if block to enable it
if true then
	return { disabled = true }
end

local Dispatcher = require("dispatcher") -- luacheck:ignore
local InfoMessage = require("ui/widget/infomessage")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local JustifySB = WidgetContainer:extend({
	name = "justifyStatusBar",
	is_doc_only = false,
})

function JustifySB:onDispatcherRegisterActions()
	Dispatcher:registerAction(
		"justify_sb_action",
		{ category = "none", event = "justify", title = _("Justify Status Bar"), general = true }
	)
end

function JustifySB:init()
	self:onDispatcherRegisterActions()
	self.ui.menu:registerToMainMenu(self)
end

function JustifySB:addToMainMenu(menu_items)
	menu_items.hello_world = {
		text = _("Justify Items"),
		-- in which menu this should be appended
		sorting_hint = "status_bar",
	}
end

function JustifySB:onHelloWorld()
	-- perform justification over status bar here
end

return JustifySB
