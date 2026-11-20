local ADDON_NAME = ...

-- The module's page at Options > AddOns > RazzhUI > Powershift. It has nothing to set: it says
-- how the powershift keys behave and the two ways to get one (Keys.lua, Bindings.xml). The key
-- names are the client's: BINDING_NAME_<binding> for each binding in Bindings.xml.

BINDING_HEADER_RAZZHUIPOWERSHIFT = "RazzhUI Powershift"
_G["BINDING_NAME_CLICK RazzhUIPowershiftBear:LeftButton"] = "Powershift: Bear Form"
_G["BINDING_NAME_CLICK RazzhUIPowershiftCat:LeftButton"] = "Powershift: Cat Form"

local LINES = {
	"Pressing a powershift key leaves the form. Letting go takes the form again. A quick tap does both.",
	"On an action bar: make a macro with the two lines below and put it on a bar.",
	"#showtooltip Bear Form",
	"/click RazzhUIPowershiftBear",
	"The key of that bar slot is then the powershift key. For Cat Form: RazzhUIPowershiftCat.",
	"Without a bar slot: bind a key under Options > Keybindings > AddOns > RazzhUI Powershift.",
}

EventUtil.ContinueOnAddOnLoaded(ADDON_NAME, function()
	local _, layout = RazzhUI.RegisterOptions(ADDON_NAME)
	for _, line in ipairs(LINES) do
		layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(line))
	end
end)
