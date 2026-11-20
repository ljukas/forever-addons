local ADDON_NAME, ns = ...

-- The module's page at Options > AddOns > RazzhUI > Powershift. It has nothing to set: it shows
-- the line to put in a powershift macro, and whether EllesmereUI's action bar was found.

local MACRO_LINE = "/click RazzhUIPowershiftHold"

local STATUS = {
	ready = "EllesmereUI's action bar 1 was found. The hold is active.",
	nobar = "EllesmereUI's action bar 1 was not found. This module does nothing without it.",
}

local Options = {}
ns.Options = Options

local built = false

-- Called by Hold.lua once its setup has found the bar or not, so the status line is known.
function Options.Build()
	if built then
		return
	end
	built = true
	local _, layout = RazzhUI.RegisterOptions(ADDON_NAME)
	layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Put this line first in your powershift macro:"))
	layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(MACRO_LINE))
	layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(STATUS[ns.Hold.status]))
end
