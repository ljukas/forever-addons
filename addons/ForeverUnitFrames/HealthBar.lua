local ADDON_NAME, ns = ...

-- With the power bar moved out of the player frame (PowerBar.lua), the health bar grows down over
-- the power bar's row. Forever lays the player frame out in PlayerFrame_UpdateHealthBarVisuals
-- (Blizzard_UnitFrame/Camelot/PlayerFrame.lua): the health container is 124x15 at (87, -46), the
-- bar in it 20 high (3 px above the container), and its mask (atlas 128x32) 9 px above the
-- container. The mana bar is 10 high right below, at (87, -61).
--
-- The mask's open part is its rows 9-24: the 15 px health well. Measured in game (/fufart,
-- 2026-11-10). Scaling the mask by the grown height over the old one keeps that open part on the
-- two wells together, -46 to -71, so the frame art's divider and the old power well are covered.
ns.HealthBar = {}

local POWER_ROW = 10
local HEALTH_ROW = 15
local CONTAINER_HEIGHT = HEALTH_ROW + POWER_ROW
local SCALE = CONTAINER_HEIGHT / HEALTH_ROW

-- Tunable by the dev probe (/fufart mask <top> <height>).
ns.HealthBar.geometry = {
	barHeight = 20 + POWER_ROW,
	maskTop = 9 * SCALE,
	maskHeight = 32 * SCALE,
}

local function Apply()
	local geometry = ns.HealthBar.geometry
	local container = PlayerFrame_GetHealthBarContainer()
	container:SetHeight(CONTAINER_HEIGHT)
	PlayerFrame_GetHealthBar():SetHeight(geometry.barHeight)

	local mask = container.HealthBarMask
	mask:ClearAllPoints()
	mask:SetPoint("TOPLEFT", container, "TOPLEFT", -2, geometry.maskTop)
	mask:SetHeight(geometry.maskHeight)

	if ns.dev.enabled then
		ns.log(
			"LAYOUT",
			"health container",
			container:GetWidth(),
			container:GetHeight(),
			"bar",
			PlayerFrame_GetHealthBar():GetHeight(),
			"mask top",
			geometry.maskTop,
			"height",
			mask:GetHeight(),
			"unit",
			PlayerFrame.unit
		)
	end
end

local function Request()
	ns.Layout.Request("health", Apply)
end
ns.HealthBar.Request = Request

ns.OnInitialize(function()
	-- Blizzard runs this on every art change (player, vehicle, alternate power bar) and resets the
	-- sizes and the mask's anchor, so ours go on again right after.
	hooksecurefunc("PlayerFrame_UpdateHealthBarVisuals", Request)
	Request()
end)
