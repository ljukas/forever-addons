local ADDON_NAME, ns = ...
local L = ns.L

-- The addon's page at Options > AddOns > RazzhUI > Unit Frames: one button that opens Edit Mode, where the
-- power bar is moved and set up. The settings themselves live in its Edit Mode dialog (EditMode.lua).
-- The click is guarded because panels can't be shown or hidden from addon code in combat.

-- Copies the Edit Mode entry of Blizzard's damage meter menu (DamageMeterSessionWindow.lua).
local function OpenEditMode()
	if InCombatLockdown() then
		local message = _G["ERR_NOT_IN_COMBAT"]
		if message then
			UIErrorsFrame:AddMessage(message, 1.0, 0.1, 0.1, 1.0)
		end
		ns.log("OPTIONS", "editmode combat")
		return
	end
	if not EditModeManagerFrame:CanEnterEditMode() then
		ns.log("OPTIONS", "editmode refused")
		return
	end
	local skipTransitionBackToOpeningPanel = true
	SettingsPanel:Close(skipTransitionBackToOpeningPanel)
	ShowUIPanel(EditModeManagerFrame)
	ns.log("OPTIONS", "editmode open")
end

ns.OnInitialize(function()
	local _, layout = RazzhUI.RegisterOptions(ADDON_NAME)

	-- The settings button asserts that addSearchTags is given.
	local addSearchTags = true
	layout:AddInitializer(
		CreateSettingsButtonInitializer(
			L.POWER_BAR,
			_G["HUD_EDIT_MODE_MENU"] or L.EDIT_MODE,
			OpenEditMode,
			L.EDIT_MODE_TOOLTIP,
			addSearchTags
		)
	)
end)
