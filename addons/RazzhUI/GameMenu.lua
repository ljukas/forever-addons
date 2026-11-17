local _, ns = ...

-- A RazzhUI button in the Esc menu (GameMenuFrame), as its own section directly above "AddOns"
-- (else "Edit Mode", else "Support"). The Game Menu has no API for adding a button: its buttons come
-- from a pool Blizzard rebuilds on every show and shares with Logout, Exit Game, Edit Mode and
-- Macros, so this file writes no field on the menu or its pooled buttons and calls none of its
-- mixin's methods. It only re-sets each pooled button's one point and the menu's height after
-- Blizzard's Layout has set them, and keeps its own state in locals. ns.log tag: MENU.
--
-- Blizzard's layout (Blizzard_SharedXML/LayoutFrame.lua): Layout lays out only shown children with
-- a layoutIndex (:38), so our button, which has none, is left alone. It gives every pooled button
-- one point, TOPLEFT to the menu's TOPLEFT (:319, :355), and sets the menu's size from them (:267).
-- It runs from OnShow (:14) and from OnUpdate after a MarkDirty (:80), always as self:Layout(), so
-- the hook sees every run, and every run resets what Place changed: Place starts from Blizzard's
-- positions and height each time and nothing drifts.
--
-- Beside EllesmereUI (EllesmereUI.lua:4557-4675), which hooks the same Layout at PLAYER_LOGIN, so
-- after this file's hook: it hangs its one or two buttons below "Shop" (else "Options"), moves every
-- pooled button with a higher layoutIndex down by 40 per button (same point, y - 40), and sets the
-- menu's height to a base it cached on its first run plus that 40 or 80. Our anchor always comes
-- after "Shop", so it moves our anchor too. Our button is therefore anchored to the anchor button,
-- not to the menu, and goes along whichever hook runs first. The height adds up either way: run
-- after EllesmereUI, Place adds to the height it set; run before it, as here, EllesmereUI's cached
-- base already holds our shift, because it read the height after Place had grown it.

local L = ns.L
-- Blizzard_GameMenu's frame, which Ketho's annotations don't declare.
local menu = _G["GameMenuFrame"]

-- MainMenuFrameMixin:AddSection's default gap (Blizzard_SharedXML/Shared/Frame/MainMenuFrameTemplates.lua:70).
local SECTION_GAP = 20
-- The GlobalStrings Blizzard creates these buttons with (Blizzard_GameMenu/Shared/GameMenuFrame.lua:227,
-- :235, :250), in the order we look for them. GlobalStrings exist only in the running game.
local ANCHOR_STRINGS = { "ADDONS", "HUD_EDIT_MODE_MENU", "GAMEMENU_SUPPORT" }

local button = CreateFrame("Button", nil, menu, "GameMenuFrameButtonTemplate")
button:SetText(L.TITLE_COLORED)
button:Hide()
-- The shape of Blizzard's own menu callbacks (GameMenuFrame.lua:166-172). OpenOptions decides what
-- happens in combat (the button is hidden then anyway).
button:SetScript("OnClick", function()
	PlaySound(SOUNDKIT.IG_MAINMENU_OPTION)
	HideUIPanel(menu)
	RazzhUI.OpenOptions()
	ns.log("MENU", "click")
end)

-- What Place has applied since Blizzard's last Layout: the pooled buttons it moved down, and by how
-- much (0 when nothing is applied).
local moved = {}
local applied = 0

-- Moves a frame's one point down by dy, keeping its point and relative frame.
local function MoveDown(frame, dy)
	local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
	frame:SetPoint(point, relativeTo, relativePoint, x, y - dy)
end

local function FindAnchor()
	for _, name in ipairs(ANCHOR_STRINGS) do
		local text = _G[name]
		if text then
			for pooled in menu.buttonPool:EnumerateActive() do
				if pooled.layoutIndex and pooled:GetText() == text then
					return pooled, text
				end
			end
		end
	end
end

-- Places our button. Expects nothing of ours applied: right after Blizzard's Layout, or after Undo.
local function Place()
	if InCombatLockdown() then
		button:Hide()
		ns.dev:LogOnce("menu-combat", "MENU", "hidden combat")
		return
	end
	local anchor, anchorText = FindAnchor()
	if not anchor then
		button:Hide()
		return
	end

	-- ignoreRect: the explicit sizes, which hold before a button has been drawn once.
	local height = anchor:GetHeight(true)
	local shift = height + SECTION_GAP
	local anchorIndex = anchor.layoutIndex
	for pooled in menu.buttonPool:EnumerateActive() do
		if pooled.layoutIndex and pooled.layoutIndex >= anchorIndex then
			MoveDown(pooled, shift)
			moved[#moved + 1] = pooled
		end
	end
	applied = shift

	-- The anchor's old place: shift above where it is now.
	button:SetSize(anchor:GetWidth(true), height)
	button:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, shift)
	button:Show()
	menu:SetHeight(menu:GetHeight(true) + shift)
	ns.dev:LogOnce("menu-placed", "MENU", "placed", anchorText)
end

-- Hides our button and gives the other buttons and the height back what Place took.
local function Undo()
	button:Hide()
	if applied == 0 then
		return
	end
	for _, pooled in ipairs(moved) do
		MoveDown(pooled, -applied)
	end
	menu:SetHeight(menu:GetHeight(true) - applied)
	wipe(moved)
	applied = 0
	ns.dev:LogOnce("menu-undo", "MENU", "undone combat")
end

hooksecurefunc(menu, "Layout", function()
	-- Layout has just re-anchored every pooled button and re-sized the menu: nothing of ours is left.
	wipe(moved)
	applied = 0
	Place()
end)

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event)
	if not menu:IsShown() then
		return
	end
	if event == "PLAYER_REGEN_DISABLED" then
		Undo()
	elseif applied == 0 then
		Place()
	end
end)
