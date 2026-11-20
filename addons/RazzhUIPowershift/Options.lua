local ADDON_NAME = ...

-- The module's page at Options > AddOns > RazzhUI > Powershift. It has nothing to set: it says
-- where the powershift keys are bound and how they behave. The key names are the client's:
-- BINDING_NAME_<binding> for each binding in Bindings.xml.

BINDING_HEADER_RAZZHUIPOWERSHIFT = "RazzhUI Powershift"
_G["BINDING_NAME_CLICK RazzhUIPowershiftBear:LeftButton"] = "Powershift: Bear Form"
_G["BINDING_NAME_CLICK RazzhUIPowershiftCat:LeftButton"] = "Powershift: Cat Form"

local LINES = {
	"Bind a key under Options > Keybindings > AddOns > RazzhUI Powershift.",
	"Pressing the key leaves the form. Letting go takes the form again.",
	"A quick tap does both. Use the key in place of a powershift macro.",
}

EventUtil.ContinueOnAddOnLoaded(ADDON_NAME, function()
	local _, layout = RazzhUI.RegisterOptions(ADDON_NAME)
	for _, line in ipairs(LINES) do
		layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(line))
	end
end)
