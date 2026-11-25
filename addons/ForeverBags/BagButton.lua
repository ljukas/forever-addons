local ADDON_NAME, ns = ...

-- A small button in the bag frame's title bar, left of its close button, that opens and
-- closes the cheapest-items window by hand. It is drawn with the coin Blizzard puts on junk
-- items in the bags (bags-junkcoin, ContainerFrame.xml).
--
-- There is one button. It sits on whichever frame holds Blizzard's bag search box and sort
-- button: the backpack, or the combined bag frame. ContainerFrameMixin:UpdateSearchBox moves
-- the sort button there with SetParent, so the button follows that call.
--
-- EllesmereUIBags hides Blizzard's bag frames and draws its own (the EUI_Bags global). There the
-- button joins the row of icons in its header, left of the leftmost one.

local Window = ns.Window

-- The bag frame the button is on, which the window opens beside.
local bagFrame
-- EllesmereUIBags' bag frame (its EUI_Bags global), once that addon has loaded. Blizzard's bag
-- frames are then no longer the ones shown.
local ellesmereBags

local SIZE = 20

local button = CreateFrame("Button", nil, UIParent)
button:SetSize(SIZE, SIZE)
button:Hide()

local icon = button:CreateTexture(nil, "ARTWORK")
-- At the atlas's own size, as Blizzard draws it on a junk item.
local useAtlasSize = true
icon:SetAtlas("bags-junkcoin", useAtlasSize)
icon:SetPoint("CENTER")

local highlight = button:CreateTexture(nil, "HIGHLIGHT")
highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
highlight:SetBlendMode("ADD")
highlight:SetAllPoints()

button:SetScript("OnMouseDown", function()
	icon:SetPoint("CENTER", 1, -1)
end)

button:SetScript("OnMouseUp", function()
	icon:SetPoint("CENTER")
end)

button:SetScript("OnClick", function(self)
	if Window.IsOpen() then
		local byPlayer = true
		Window.Close(byPlayer)
	else
		Window.Open("hand", bagFrame or self:GetParent())
	end
end)

button:SetScript("OnEnter", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip_SetTitle(GameTooltip, ns.L.BUTTON_TOOLTIP, HIGHLIGHT_FONT_COLOR)
	GameTooltip_AddNormalLine(GameTooltip, ns.L.BUTTON_TOOLTIP_TEXT)
	GameTooltip:Show()
end)

button:SetScript("OnLeave", GameTooltip_Hide)

-- The bag frame closed (or the button left it): a window opened by hand goes with it.
button:SetScript("OnHide", function()
	if Window.Owner() == "hand" then
		Window.Close()
	end
end)

local function Attach(frame)
	if ellesmereBags then
		return
	end
	bagFrame = frame
	if not bagFrame or not bagFrame.CloseButton then
		button:Hide()
		return
	end
	button:SetParent(bagFrame)
	button:ClearAllPoints()
	button:SetPoint("RIGHT", bagFrame.CloseButton, "LEFT", 0, 0)
	-- The frame's TitleContainer takes mouse input, spans the title bar up to the close button
	-- and sits at the close button's level (510, seen in game), so at that level the title
	-- bar gets the click. The button goes one above.
	local level = bagFrame.CloseButton:GetFrameLevel()
	if bagFrame.TitleContainer then
		level = math.max(level, bagFrame.TitleContainer:GetFrameLevel())
	end
	button:SetFrameLevel(level + 1)
	button:Show()
end

-- The gap EllesmereUI leaves between its header icons (EUI_Bags:SyncHeaderIcons).
local ELLESMERE_GAP = 6

-- Runs after EUI_Bags:SyncHeaderIcons has laid out the header's icons, right to left. On the
-- WoW Forever look the search box runs up to the leftmost icon; on EllesmereUI's own look the
-- title does, and the leftmost icon is kept in _hdrEdge. Either way the button goes left of that
-- icon and becomes the new edge.
local function AttachEllesmere()
	local header = ellesmereBags.Header
	local search = ellesmereBags._searchBox
	if not header or not search then
		return
	end
	local edge = ellesmereBags._hdrEdge
	local forever = edge == nil
	if forever then
		local _, relativeTo = search:GetPointByName("RIGHT")
		edge = relativeTo
	end
	if not edge or edge == button then
		return
	end
	bagFrame = ellesmereBags
	button:SetParent(header)
	button:ClearAllPoints()
	button:SetPoint("RIGHT", edge, "LEFT", -ELLESMERE_GAP, 0)
	button:SetFrameLevel(edge:GetFrameLevel() + 1)
	button:Show()
	ns.log("BUTTON", "ellesmere", forever and "forever look" or "own look", "level", button:GetFrameLevel())
	if forever then
		search:SetPoint("RIGHT", button, "LEFT", -ELLESMERE_GAP, 0)
	else
		ellesmereBags._hdrEdge = button
		ellesmereBags:FitHeaderText()
	end
end

ns.OnInitialize(function()
	EventUtil.ContinueOnAddOnLoaded("EllesmereUIBags", function()
		local bags = _G["EUI_Bags"]
		if not bags or not bags.SyncHeaderIcons then
			return
		end
		ellesmereBags = bags
		button:Hide()
		hooksecurefunc(bags, "SyncHeaderIcons", AttachEllesmere)
		AttachEllesmere()
	end)

	if not BagItemAutoSortButton then
		return
	end
	hooksecurefunc(BagItemAutoSortButton, "SetParent", function(_, bagFrame)
		Attach(bagFrame)
	end)
	Attach(BagItemAutoSortButton:GetParent())
end)
