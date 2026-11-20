local ADDON_NAME = ...

-- The module's page at Options > AddOns > RazzhUI > Powershift. It has nothing to set: it says
-- how the powershift keys behave and the two ways to get one (Keys.lua, Bindings.xml). The key
-- names are the client's: BINDING_NAME_<binding> for each binding in Bindings.xml.

BINDING_HEADER_RAZZHUIPOWERSHIFT = "RazzhUI Powershift"
_G["BINDING_NAME_CLICK RazzhUIPowershiftBear:LeftButton"] = "Powershift: Bear Form"
_G["BINDING_NAME_CLICK RazzhUIPowershiftCat:LeftButton"] = "Powershift: Cat Form"

local LINES = {
	"Pressing a powershift key leaves the form. Letting go takes it again. A quick tap does both.",
	"On an action bar: put a macro with these two lines on a bar slot.",
	"#showtooltip Bear Form",
	"/click RazzhUIPowershiftBear",
	"That slot's key then powershifts. For Cat Form: RazzhUIPowershiftCat.",
	"Clicking the slot with the mouse only casts the form, as its own button does.",
	"Or bind a key under Options > Keybindings > AddOns > RazzhUI Powershift.",
}

EventUtil.ContinueOnAddOnLoaded(ADDON_NAME, function()
	local _, layout = RazzhUI.RegisterOptions(ADDON_NAME)
	for _, line in ipairs(LINES) do
		layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(line))
	end
end)
