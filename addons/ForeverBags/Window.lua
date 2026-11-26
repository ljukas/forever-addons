local ADDON_NAME, ns = ...

-- The cheapest-items window. It is Blizzard's loot window frame (ScrollingFlatPanelTemplate,
-- which LootFrame inherits) with our rows in its scroll box, set up the way
-- Blizzard_UIPanels_Game/Mainline/LootFrame.lua sets up its own.
--
-- The window has one owner, which decides what closes it:
--   "loot"  opened by a failed loot; Loot.lua closes it when the loot window closes.
--   "hand"  opened from the bag button; it stays until the player closes it.

ns.Window = {}

local Window = ns.Window

-- Set by Loot.lua. onDeleted runs after each stack the player deleted from the window;
-- onClosedByPlayer when the player closed it (close button, Escape), not Window.Close().
Window.onDeleted = nil
Window.onClosedByPlayer = nil

-- Row height, padding and spacing are the loot window's (LootFrame.lua:1-3).
local ROW_HEIGHT = 46
local PAD = 6
local SPACING = 2
local PANEL_WIDTH = 260
local PANEL_MAX_HEIGHT = 290
local GAP = 8
-- Seconds after a delete during which further Delete clicks are ignored.
local DELETE_PAUSE = 0.5

local frame
local owner
-- True from Window.Close() until the frame is hidden, so OnHide can tell it from the player.
local closingOurselves = false
-- The last scan skipped a stack whose item data hadn't loaded.
local pending = false
-- GetTime() of the last delete made from the window.
local lastDelete = 0

ForeverBagsRowMixin = {}

function ForeverBagsRowMixin:OnLoad()
	self.Delete:SetText(DELETE)
	self.Price:SetPoint("TOPLEFT", self.Name, "BOTTOMLEFT", 0, -4)
	self.Price:SetFontObject(GameFontHighlightSmall)
	-- Only the coins the price has, as GetMoneyString writes it: "6c", not "0s 6c".
	local showsZeroAmount = false
	self.Price.SilverDisplay:SetShowsZeroAmount(showsZeroAmount)
	self.Price.CopperDisplay:SetShowsZeroAmount(showsZeroAmount)
end

function ForeverBagsRowMixin:Init(entry)
	self.entry = entry
	SetItemButtonTexture(self.Item, entry.icon)
	SetItemButtonCount(self.Item, entry.count)
	SetItemButtonQuality(self.Item, entry.quality, entry.link)
	self.Name:SetText(entry.name)
	local colorData = ColorManager.GetColorDataForItemQuality(entry.quality or Enum.ItemQuality.Common)
	if colorData then
		self.Name:SetVertexColor(colorData.color:GetRGB())
		self.NameFrame:SetVertexColor(colorData.color:GetRGB())
	end
	self.Price:SetAmount(entry.value)
end

function ForeverBagsRowMixin:OnDeleteClick()
	-- After a delete the list moves up, and the next stack lands under the cursor. A second
	-- click that quickly was aimed at the row that is gone, so it is dropped.
	if GetTime() - lastDelete < DELETE_PAUSE then
		return
	end
	local function Deleted()
		lastDelete = GetTime()
		if Window.onDeleted then
			Window.onDeleted()
		end
	end
	if ns.Delete.Request(self.entry, Deleted, Window.Refresh) == "stale" then
		Window.Refresh()
	end
end

function ForeverBagsRowMixin:OnItemClick()
	ns.DB.Ignore(self.entry.itemID)
	ns.Options.RefreshIgnored()
	GameTooltip:Hide()
	Window.Refresh()
end

function ForeverBagsRowMixin:OnItemEnter()
	GameTooltip:SetOwner(self.Item, "ANCHOR_RIGHT")
	GameTooltip:SetBagItem(self.entry.bag, self.entry.slot)
	GameTooltip_AddInstructionLine(GameTooltip, ns.L.IGNORE_HINT)
	GameTooltip:Show()
end

-- The game's own words for full bags, without the full stop of the error message.
local TITLE_FULL = (ERR_INV_FULL:gsub("%.$", ""))

-- A window a failed loot opened says why it is there, also while a delete has just made room.
-- One opened by hand only says the bags are full when they are.
local function UpdateTitle()
	local full = owner == "loot" or ns.Items.FreeSlots() == 0
	frame:SetTitle(full and TITLE_FULL or ns.L.BUTTON_TOOLTIP)
end

local function Populate()
	UpdateTitle()
	local entries
	entries, pending = ns.Items.Scan()
	frame.ScrollBox:SetDataProvider(CreateDataProvider(entries), ScrollBoxConstants.RetainScrollPosition)
	frame.Empty:SetShown(#entries == 0)
	frame:Resize()
end

local function OnEvent(_, event)
	if event == "BAG_UPDATE_DELAYED" or pending then
		Populate()
	end
end

local function OnShow(self)
	self:RegisterEvent("BAG_UPDATE_DELAYED")
	self:RegisterEvent("GET_ITEM_INFO_RECEIVED")
end

-- Every way of hiding ends here: the close button and Window.Close() (after the panel's
-- closing animation), and Escape (UISpecialFrames hides the frame directly).
local function OnHide(self)
	self:UnregisterEvent("BAG_UPDATE_DELAYED")
	self:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
	self.isOpen = false
	self.ScrollBox:RemoveDataProvider()
	local byPlayer = not closingOurselves
	ns.log("WINDOW", "close", owner, byPlayer and "player" or "addon")
	closingOurselves = false
	owner = nil
	-- When a parent was hidden (the whole UI, for a cinematic or Alt-Z) the frame itself still
	-- counts as shown and would come back, empty, with the parent. Close it for real.
	if self:IsShown() then
		self:Hide()
	end
	if byPlayer and Window.onClosedByPlayer then
		Window.onClosedByPlayer()
	end
end

local function Create()
	frame = CreateFrame("Frame", "ForeverBagsWindow", UIParent, "ScrollingFlatPanelTemplate")
	frame:Hide()
	frame.panelWidth = PANEL_WIDTH
	frame.panelMaxHeight = PANEL_MAX_HEIGHT
	frame:SetFrameStrata("HIGH")
	-- The panel reads its title while it is created, before we could set one; Populate sets it.

	-- ScrollingFlatPanelMixin leaves this to the frame that uses it.
	function frame:CalculateElementsHeight()
		local height =
			ScrollUtil.CalculateScrollBoxElementExtent(self.ScrollBox:GetDataProviderSize(), ROW_HEIGHT, SPACING)
		return math.max(height, ROW_HEIGHT)
	end

	-- The mixin's version calls HideUIPanel, which is for panels the UI panel manager placed.
	-- This frame is anchored by us, so it is simply hidden.
	function frame:OnHideAnimFinished()
		self:Hide()
	end

	local view = CreateScrollBoxListLinearView(PAD, PAD, PAD, PAD, SPACING)
	view:SetElementInitializer("ForeverBagsRowTemplate", function(row, entry)
		row:Init(entry)
	end)
	ScrollUtil.InitScrollBoxWithScrollBar(frame.ScrollBox, frame.ScrollBar, view)

	-- The template's scroll shadows, sized and placed as LootFrameMixin:OnLoad does.
	local scrollBox = frame.ScrollBox
	scrollBox:SetShadowsFrameLevel(scrollBox.ScrollTarget:GetFrameLevel() + 15)
	scrollBox:SetShadowsScale(0.2)
	scrollBox:GetUpperShadowTexture():SetTexCoord(0, 1, 1, 0)
	scrollBox:GetUpperShadowTexture():SetPoint("TOPLEFT", 30, 0)
	scrollBox:GetUpperShadowTexture():SetPoint("TOPRIGHT", -30, 0)
	scrollBox:GetLowerShadowTexture():SetPoint("BOTTOMLEFT", 30, 0)
	scrollBox:GetLowerShadowTexture():SetPoint("BOTTOMRIGHT", -30, 0)

	frame.Empty = frame:CreateFontString(nil, "ARTWORK", "GameFontDisable")
	frame.Empty:SetPoint("LEFT", frame.ScrollBox, "LEFT", PAD * 2, 0)
	frame.Empty:SetPoint("RIGHT", frame.ScrollBox, "RIGHT", -PAD * 2, 0)
	frame.Empty:SetText(ns.L.EMPTY)
	frame.Empty:Hide()

	frame:SetScript("OnShow", OnShow)
	frame:SetScript("OnHide", OnHide)
	frame:SetScript("OnEvent", OnEvent)

	-- Escape closes it, like the loot window.
	table.insert(UISpecialFrames, "ForeverBagsWindow")
end

-- Beside anchorFrame: to its right, or to its left when that would leave the screen.
local function Place(anchorFrame)
	frame:ClearAllPoints()
	local right = anchorFrame and anchorFrame:IsShown() and anchorFrame:GetRight()
	if not right then
		frame:SetPoint("CENTER", UIParent, "CENTER")
		return
	end
	local scale = anchorFrame:GetEffectiveScale() / UIParent:GetEffectiveScale()
	if right * scale + GAP + frame:GetMaxPossibleWidth() <= UIParent:GetRight() then
		frame:SetPoint("TOPLEFT", anchorFrame, "TOPRIGHT", GAP, 0)
	else
		frame:SetPoint("TOPRIGHT", anchorFrame, "TOPLEFT", -GAP, 0)
	end
end

function Window.IsOpen()
	return frame ~= nil and frame:IsShown() and frame.isOpen == true
end

function Window.Owner()
	return Window.IsOpen() and owner or nil
end

-- Opens the window for newOwner ("loot" or "hand") beside anchorFrame. A window that is
-- already open keeps its owner and its place, and is refreshed.
function Window.Open(newOwner, anchorFrame)
	if not frame then
		Create()
	end
	if Window.IsOpen() then
		Populate()
		return
	end
	closingOurselves = false
	owner = newOwner
	Place(anchorFrame)
	frame:Show()
	frame.isOpen = true
	Populate()
	local skipShow = true
	frame:Open(skipShow)
	ns.log("WINDOW", "open", owner)
end

-- byPlayer: the player asked for it (the bag button), so it counts as them closing the
-- window, the same as its close button.
function Window.Close(byPlayer)
	if Window.IsOpen() then
		closingOurselves = not byPlayer
		frame:Close()
	end
end

function Window.Refresh()
	if Window.IsOpen() then
		Populate()
	end
end
