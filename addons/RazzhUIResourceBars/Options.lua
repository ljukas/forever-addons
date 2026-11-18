local ADDON_NAME, ns = ...
local L = ns.L

-- The addon's page at Options > AddOns > RazzhUI > Resource Bars: one button that opens Edit Mode, where the
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
	-- With unapplied settings Close only shows Blizzard's "discard changes?" popup and leaves Options open. The popup
	-- is then the only result; the player clicks again once Options has settled.
	if SettingsPanel:IsShown() then
		ns.log("OPTIONS", "editmode pending")
		return
	end
	ShowUIPanel(EditModeManagerFrame)
	ns.log("OPTIONS", "editmode open")
end

ns.OnInitialize(function()
	local _, layout = RazzhUI.RegisterOptions(ADDON_NAME)

	-- The settings button asserts that addSearchTags is given.
	local addSearchTags = true
	local initializer = CreateSettingsButtonInitializer(
		L.POWER_BAR,
		_G["HUD_EDIT_MODE_MENU"] or L.EDIT_MODE,
		OpenEditMode,
		L.EDIT_MODE_TOOLTIP,
		addSearchTags
	)
	-- Blizzard's Esc menu leaves its Edit Mode button out when Edit Mode can't be entered (GameMenuFrame.lua:234);
	-- ours is greyed instead.
	initializer:AddModifyPredicate(function()
		return EditModeManagerFrame:CanEnterEditMode()
	end)
	layout:AddInitializer(initializer)
end)
