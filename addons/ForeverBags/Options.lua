local ADDON_NAME, ns = ...

-- The addon's page in the game's Settings panel: one button that clears the ignore list.

ns.OnInitialize(function()
	local category, layout = Settings.RegisterVerticalLayoutCategory(ADDON_NAME)

	local function ResetIgnored()
		ns.DB.ResetIgnored()
		ns.Window.Refresh()
	end

	-- The settings button asserts that addSearchTags is given.
	local addSearchTags = true
	layout:AddInitializer(
		CreateSettingsButtonInitializer(
			ns.L.RESET_IGNORED,
			ns.L.RESET_IGNORED,
			ResetIgnored,
			ns.L.RESET_IGNORED_TOOLTIP,
			addSearchTags
		)
	)

	Settings.RegisterAddOnCategory(category)
end)
