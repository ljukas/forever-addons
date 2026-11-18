local ADDON_NAME, ns = ...

-- The addon's page at Options > AddOns > RazzhUI > Bags: one button that clears the ignore list.

ns.OnInitialize(function()
	local _, layout = RazzhUI.RegisterOptions(ADDON_NAME)

	local function ResetIgnored()
		ns.DB.ResetIgnored()
		ns.Window.Refresh()
	end

	-- The settings button asserts that addSearchTags is given.
	local addSearchTags = true
	layout:AddInitializer(
		CreateSettingsButtonInitializer("", ns.L.RESET_IGNORED, ResetIgnored, ns.L.RESET_IGNORED_TOOLTIP, addSearchTags)
	)
end)
