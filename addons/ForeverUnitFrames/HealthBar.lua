local ADDON_NAME, ns = ...

-- With the power bar moved out of the player frame (PowerBar.lua), the health bar grows down over
-- the power bar's row. Forever lays the player frame out in PlayerFrame_UpdateHealthBarVisuals
-- (Blizzard_UnitFrame/Camelot/PlayerFrame.lua): the health container is 124x15 at (87, -46), the
-- bar in it 20 high and its mask 32 high; the mana bar is 10 high right below at (87, -61). Each
-- grows by the power row, keeping Blizzard's top anchors, so the bar grows downwards.
local POWER_ROW = 10
local CONTAINER_HEIGHT = 15 + POWER_ROW
local BAR_HEIGHT = 20 + POWER_ROW
local MASK_HEIGHT = 32 + POWER_ROW

local function Apply()
	local container = PlayerFrame_GetHealthBarContainer()
	container:SetHeight(CONTAINER_HEIGHT)
	PlayerFrame_GetHealthBar():SetHeight(BAR_HEIGHT)
	container.HealthBarMask:SetHeight(MASK_HEIGHT)
	if ns.dev.enabled then
		ns.log(
			"LAYOUT",
			"health container",
			container:GetWidth(),
			container:GetHeight(),
			"bar",
			PlayerFrame_GetHealthBar():GetHeight(),
			"mask",
			container.HealthBarMask:GetHeight(),
			"unit",
			PlayerFrame.unit
		)
	end
end

local function Request()
	ns.Layout.Request("health", Apply)
end

ns.OnInitialize(function()
	-- Blizzard runs this on every art change (player, vehicle, alternate power bar) and resets the
	-- sizes, so ours go on again right after.
	hooksecurefunc("PlayerFrame_UpdateHealthBarVisuals", Request)
	Request()
end)
