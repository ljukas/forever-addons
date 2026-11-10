local ADDON_NAME, ns = ...

-- Dev-only: what Forever's player frame art really is, to fit the grown health bar to it.
--   /fufart          logs the candidate atlases (size, file, coords) and where the bars sit (ART)
--   /fufart <n>      previews frame art n on the player frame until /reload (ART)
if not ns.dev.enabled then
	return
end

local ATLASES = {
	"UI-HUD-UnitFrame-Player-PortraitOn",
	"UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health-Mask",
	"UI-HUD-UnitFrame-Player-PortraitOn-Bar-Mana-Mask",
	"UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health",
	"plunderstorm-ui-hud-unitframe-player-portraiton",
	"plunderstorm-ui-hud-unitframe-player-portraiton-bar-health-mask",
	"UI-HUD-UnitFrame-Target-MinusMob-PortraitOn",
	"UI-HUD-UnitFrame-Target-MinusMob-PortraitOn-Bar-Health-Mask",
	"UI-HUD-UnitFrame-Target-PortraitOn",
	"ui-castingbar-frame",
	"ui-castingbar-background",
	"Unit_BarMask",
}

-- Frame art to preview; mirror flips a target-frame atlas to face the player frame's way.
local PREVIEWS = {
	{ atlas = "UI-HUD-UnitFrame-Player-PortraitOn" },
	{ atlas = "plunderstorm-ui-hud-unitframe-player-portraiton" },
	{ atlas = "UI-HUD-UnitFrame-Target-MinusMob-PortraitOn", mirror = true },
}

-- A region's rect relative to the player frame's top-left: left, top, width, height.
local function Rect(region)
	local left, top = region:GetLeft(), region:GetTop()
	if not left then
		return "unplaced"
	end
	return string.format(
		"%.1f,%.1f %.1fx%.1f",
		left - PlayerFrame:GetLeft(),
		top - PlayerFrame:GetTop(),
		region:GetWidth(),
		region:GetHeight()
	)
end

local function LogAtlases()
	for _, name in ipairs(ATLASES) do
		local info = C_Texture.GetAtlasInfo(name)
		if info then
			ns.log(
				"ART",
				name,
				info.width .. "x" .. info.height,
				"file",
				info.filename or info.file,
				"coords",
				info.leftTexCoord,
				info.rightTexCoord,
				info.topTexCoord,
				info.bottomTexCoord
			)
		else
			ns.log("ART", name, "missing")
		end
	end
	local container = PlayerFrame_GetHealthBarContainer()
	ns.log("ART", "frame", Rect(PlayerFrame.PlayerFrameContainer.FrameTexture))
	ns.log("ART", "health container", Rect(container), "bar", Rect(PlayerFrame_GetHealthBar()))
	ns.log("ART", "health mask", Rect(container.HealthBarMask))
end

local function Preview(index)
	local preview = PREVIEWS[index]
	if not preview or InCombatLockdown() then
		return
	end
	local texture = PlayerFrame.PlayerFrameContainer.FrameTexture
	texture:SetAtlas(preview.atlas, TextureKitConstants.UseAtlasSize)
	local info = C_Texture.GetAtlasInfo(preview.atlas)
	if preview.mirror and info then
		texture:SetTexCoord(info.rightTexCoord, info.leftTexCoord, info.topTexCoord, info.bottomTexCoord)
	end
	ns.log("ART", "preview", index, preview.atlas, "frame", Rect(texture))
end

-- /fufart mask <top> <height>: moves the health mask's top (px above the container) and height.
local function TuneMask(top, height)
	local geometry = ns.HealthBar.geometry
	geometry.maskTop = top or geometry.maskTop
	geometry.maskHeight = height or geometry.maskHeight
	ns.HealthBar.Request()
	ns.log("ART", "mask top", geometry.maskTop, "height", geometry.maskHeight)
end

-- /fufart backing: a black backing behind the health bar, shaped by its mask, to see whether the
-- art's divider shows through the empty part of the bar at less than full health.
local backing
local function ToggleBacking()
	local container = PlayerFrame_GetHealthBarContainer()
	if not backing then
		backing = container:CreateTexture(nil, "BACKGROUND", nil, -8)
		backing:SetColorTexture(0, 0, 0, 1)
		backing:SetAllPoints(container)
		backing:AddMaskTexture(container.HealthBarMask)
		backing:Hide()
	end
	backing:SetShown(not backing:IsShown())
	ns.log("ART", "backing", backing:IsShown())
end

SLASH_FOREVERUNITFRAMES_ART1 = "/fufart"
SlashCmdList.FOREVERUNITFRAMES_ART = function(msg)
	local command, first, second = strsplit(" ", strtrim(msg or ""))
	if command == "mask" then
		TuneMask(tonumber(first), tonumber(second))
	elseif command == "backing" then
		ToggleBacking()
	elseif tonumber(command) then
		Preview(tonumber(command))
	else
		LogAtlases()
	end
end
