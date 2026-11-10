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

-- The frame art (atlas UI-HUD-UnitFrame-Player-PortraitOn, 198x71) draws over the health bar,
-- including the divider between the health and power wells. Drawing over the divider can't remove
-- it (the well is see-through), so the art is rebuilt without it from pieces of the same texture,
-- and Blizzard's texture is made transparent while the pieces show:
--   above the divider rows, and below them, as they are;
--   the divider rows left of the well (the portrait ring), as they are;
--   the divider and power-well rows over the well, copied from rows inside the health well, whose edges run
--   straight down there.
-- In art pixels from its top-left; tunable by the dev probe (/fufart patch <left> <from> <to>
-- <rows>).
local FRAME_ATLAS = "UI-HUD-UnitFrame-Player-PortraitOn"

-- The art sits at (17, -14.5) in the player frame: the health well is art rows ~32-46, the divider
-- and the power well (which also shades the bar) ~45-56, then the frame's bottom edge. First guess,
-- to be checked in game.
ns.HealthBar.patch = {
	left = 72,
	from = 33,
	to = 45,
	rows = 11,
}

-- Pieces: { source x, source y, width, height, target x, target y }.
local function Pieces(patch, width, height)
	local bottom = patch.to + patch.rows
	return {
		{ 0, 0, width, patch.to, 0, 0 },
		{ 0, bottom, width, height - bottom, 0, bottom },
		{ 0, patch.to, patch.left, patch.rows, 0, patch.to },
		{ patch.left, patch.from, width - patch.left, patch.rows, patch.left, patch.to },
	}
end

local pieceTextures = {}
local patchEnabled = true

local function ApplyPatch()
	local container = PlayerFrame.PlayerFrameContainer
	local frameTexture = container.FrameTexture
	local info = C_Texture.GetAtlasInfo(FRAME_ATLAS)
	-- Only over Forever's own player art: not the vehicle or alternate-power frame.
	local shown = patchEnabled and info ~= nil and frameTexture:IsShown() and frameTexture:GetAtlas() == FRAME_ATLAS
	frameTexture:SetAlpha(shown and 0 or 1)
	for _, texture in ipairs(pieceTextures) do
		texture:SetShown(shown)
	end
	if not shown then
		return
	end

	local width, height = info.width, info.height
	local function U(x)
		return info.leftTexCoord + (info.rightTexCoord - info.leftTexCoord) * x / width
	end
	local function V(y)
		return info.topTexCoord + (info.bottomTexCoord - info.topTexCoord) * y / height
	end
	for index, piece in ipairs(Pieces(ns.HealthBar.patch, width, height)) do
		local sourceX, sourceY, pieceWidth, pieceHeight, targetX, targetY = unpack(piece)
		local texture = pieceTextures[index]
		if not texture then
			texture = container:CreateTexture(nil, "BACKGROUND", nil, 2)
			-- As Blizzard's FrameTexture (PlayerFrame.xml), so the pieces meet without seams.
			texture:SetSnapToPixelGrid(false)
			texture:SetTexelSnappingBias(0)
			pieceTextures[index] = texture
		end
		texture:SetTexture(info.file)
		texture:SetTexCoord(U(sourceX), U(sourceX + pieceWidth), V(sourceY), V(sourceY + pieceHeight))
		texture:ClearAllPoints()
		texture:SetPoint("TOPLEFT", frameTexture, "TOPLEFT", targetX, -targetY)
		texture:SetSize(pieceWidth, pieceHeight)
		texture:Show()
	end
end

local function Request()
	ns.Layout.Request("health", Apply)
	ns.Layout.Request("patch", ApplyPatch)
end
ns.HealthBar.Request = Request

-- Off for the dev probe's before/after comparison.
function ns.HealthBar.SetPatchEnabled(enabled)
	patchEnabled = enabled
	Request()
end

ns.OnInitialize(function()
	-- Blizzard runs this on every art change (player, vehicle, alternate power bar) and resets the
	-- sizes and the mask's anchor, so ours go on again right after.
	hooksecurefunc("PlayerFrame_UpdateHealthBarVisuals", Request)
	Request()
end)
