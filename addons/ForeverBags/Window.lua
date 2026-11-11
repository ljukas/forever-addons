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

local frame
local owner
-- True from Window.Close() until the frame is hidden, so OnHide can tell it from the player.
local closingOurselves = false
-- The last scan skipped a stack whose item data hadn't loaded.
local pending = false

ForeverBagsRowMixin = {}

function ForeverBagsRowMixin:OnLoad()
	self.Delete:SetText(DELETE)
end

function ForeverBagsRowMixin:Init(entry)
	self.entry = entry
	SetItemButtonTexture(self.Item, entry.icon)
	SetItemButtonCount(self.Item, entry.count)
	self.Name:SetText(entry.name)
	local colorData = ColorManager.GetColorDataForItemQuality(entry.quality or Enum.ItemQuality.Common)
	if colorData then
		self.Name:SetVertexColor(colorData.color:GetRGB())
		self.NameFrame:SetVertexColor(colorData.color:GetRGB())
	end
	self.Price:SetText(GetMoneyString(entry.value))
end

function ForeverBagsRowMixin:OnDeleteClick()
	local function Deleted()
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
	GameTooltip:Hide()
	Window.Refresh()
end

function ForeverBagsRowMixin:OnItemEnter()
	GameTooltip:SetOwner(self.Item, "ANCHOR_RIGHT")
	GameTooltip:SetBagItem(self.entry.bag, self.entry.slot)
	GameTooltip_AddInstructionLine(GameTooltip, ns.L.IGNORE_HINT)
	GameTooltip:Show()
end

local function Populate()
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
	-- The panel reads its title while it is created, before we could set one. The game's own
	-- words for the situation, without the full stop of the error message.
	frame:SetTitle((ERR_INV_FULL:gsub("%.$", "")))

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

function Window.Close()
	if Window.IsOpen() then
		closingOurselves = true
		frame:Close()
	end
end

function Window.Refresh()
	if Window.IsOpen() then
		Populate()
	end
end
