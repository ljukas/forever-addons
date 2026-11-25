local ADDON_NAME, ns = ...

-- The addon's page at Options > AddOns > RazzhUI > Bags: the current character's ignored
-- items, each with a button that takes it off the list, and a button that clears the list.
--
--   ns.Options.RefreshIgnored()  call after any change to the ignore list
--
-- The list is one element of the page (Options.xml) with a scroll box of its own, since the
-- page's own rows are fixed once it is registered.

ns.Options = {}

-- The list element while the page shows it. The page's scroll box makes the frame when the
-- element scrolls into view and takes it back afterwards.
local shownList

function ns.Options.RefreshIgnored()
	if shownList then
		shownList:Refresh()
	end
end

ForeverBagsIgnoredRowMixin = {}

function ForeverBagsIgnoredRowMixin:Init(itemID)
	self.itemID = itemID
	self.Icon:SetTexture(C_Item.GetItemIconByID(itemID) or QUESTION_MARK_ICON)
	-- Until the item's data has loaded, and for an item the client doesn't know, its ID.
	self.Name:SetText(itemID)
	self.Name:SetTextColor(GRAY_FONT_COLOR:GetRGB())
	-- An item that doesn't exist can't be waited for: ContinueOnItemLoad raises an error.
	if not C_Item.DoesItemExistByID(itemID) then
		return
	end
	local item = Item:CreateFromItemID(itemID)
	item:ContinueOnItemLoad(function()
		-- Rows are reused: by now this one may show another item.
		if self.itemID ~= itemID then
			return
		end
		self.Name:SetText(item:GetItemName())
		local colorData = item:GetItemQualityColor()
		if colorData then
			self.Name:SetTextColor(colorData.color:GetRGB())
		else
			self.Name:SetTextColor(HIGHLIGHT_FONT_COLOR:GetRGB())
		end
	end)
end

function ForeverBagsIgnoredRowMixin:OnEnter()
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetItemByID(self.itemID)
	GameTooltip:Show()
end

function ForeverBagsIgnoredRowMixin:OnRemoveClick()
	ns.DB.Unignore(self.itemID)
	ns.Window.Refresh()
	ns.Options.RefreshIgnored()
end

ForeverBagsIgnoredListMixin = {}

function ForeverBagsIgnoredListMixin:OnLoad()
	local view = CreateScrollBoxListLinearView()
	view:SetElementInitializer("ForeverBagsIgnoredRowTemplate", function(row, itemID)
		row:Init(itemID)
	end)
	ScrollUtil.InitScrollBoxListWithScrollBar(self.ScrollBox, self.ScrollBar, view)
	self.ScrollBar:SetHideIfUnscrollable(true)
	self.Empty:SetText(ns.L.NO_IGNORED_ITEMS)
end

-- Called by the page's list each time it gives the frame to the element.
function ForeverBagsIgnoredListMixin:Init()
	self:Refresh()
end

function ForeverBagsIgnoredListMixin:OnShow()
	shownList = self
	self:Refresh()
end

function ForeverBagsIgnoredListMixin:OnHide()
	if shownList == self then
		shownList = nil
	end
end

function ForeverBagsIgnoredListMixin:Refresh()
	local itemIDs = ns.DB.GetIgnored()
	self.ScrollBox:SetDataProvider(CreateDataProvider(itemIDs), ScrollBoxConstants.RetainScrollPosition)
	self.Empty:SetShown(#itemIDs == 0)
end

ns.OnInitialize(function()
	local _, layout = RazzhUI.RegisterOptions(ADDON_NAME)

	layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(ns.L.IGNORED_ITEMS))
	layout:AddInitializer(Settings.CreateElementInitializer("ForeverBagsIgnoredListTemplate", {}))

	local function ResetIgnored()
		ns.DB.ResetIgnored()
		ns.Window.Refresh()
		ns.Options.RefreshIgnored()
	end

	-- The settings button asserts that addSearchTags is given.
	local addSearchTags = true
	layout:AddInitializer(
		CreateSettingsButtonInitializer("", ns.L.RESET_IGNORED, ResetIgnored, ns.L.RESET_IGNORED_TOOLTIP, addSearchTags)
	)
end)
