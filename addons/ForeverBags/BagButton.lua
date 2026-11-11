local ADDON_NAME, ns = ...

-- A small button in the bag frame's title bar, left of its close button, that opens and
-- closes the cheapest-items window by hand. It is drawn with the coin Blizzard puts on junk
-- items in the bags (bags-junkcoin, ContainerFrame.xml).
--
-- There is one button. It sits on whichever frame holds Blizzard's bag search box and sort
-- button: the backpack, or the combined bag frame. ContainerFrameMixin:UpdateSearchBox moves
-- the sort button there with SetParent, so the button follows that call.

local Window = ns.Window

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
		Window.Open("hand", self:GetParent())
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

local function Attach(bagFrame)
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

ns.OnInitialize(function()
	if not BagItemAutoSortButton then
		return
	end
	hooksecurefunc(BagItemAutoSortButton, "SetParent", function(_, bagFrame)
		Attach(bagFrame)
	end)
	Attach(BagItemAutoSortButton:GetParent())
end)
