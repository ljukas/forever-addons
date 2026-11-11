local ADDON_NAME, ns = ...

-- Deleting one bag stack. DeleteCursorItem only works from the player's own click, so
-- everything here runs inside a button's OnClick or a popup's accept, never from an event or
-- a timer. The slot is read again right before the delete: the bags may have changed since
-- the row was drawn.

ns.Delete = {}

local Delete = ns.Delete

local POPUP = "FOREVERBAGS_DELETE_ITEM"
local POPUP_GOOD = "FOREVERBAGS_DELETE_GOOD_ITEM"

-- True while the slot still holds exactly the stack the entry describes and nothing is on
-- the cursor. A spell waiting for an item to be cast on (an enchant, a poison) counts as
-- something on the cursor: picking a slot up would cast it, as Blizzard's bag buttons check
-- (ContainerFrame.lua).
function Delete.Matches(entry)
	if GetCursorInfo() or SpellIsTargeting() then
		return false
	end
	local info = C_Container.GetContainerItemInfo(entry.bag, entry.slot)
	return info ~= nil
		and not info.isLocked
		and info.itemID == entry.itemID
		and info.hyperlink == entry.link
		and info.stackCount == entry.count
end

-- Returns "deleted" or "stale".
local function DeleteNow(entry, onDeleted)
	if not Delete.Matches(entry) then
		ns.log("DELETE", "stale", entry.link, entry.count)
		return "stale"
	end
	C_Container.PickupContainerItem(entry.bag, entry.slot)
	local cursorType, cursorItemID = GetCursorInfo()
	if cursorType ~= "item" or cursorItemID ~= entry.itemID then
		-- The pickup did something else (a swap, a split). Put it back, delete nothing.
		ClearCursor()
		ns.log("DELETE", "stale", "cursor", cursorType, cursorItemID)
		return "stale"
	end
	DeleteCursorItem()
	if GetCursorInfo() then
		ClearCursor()
		ns.log("DELETE", "refused", entry.link, entry.count)
		return "stale"
	end
	ns.log("DELETE", "deleted", entry.link, entry.count)
	if onDeleted then
		onDeleted()
	end
	return "deleted"
end

local function OnAccept(_, data)
	local result = DeleteNow(data.entry, data.onDeleted)
	if result == "stale" and data.onStale then
		data.onStale()
	end
end

-- A yes/no question, as Blizzard asks for an ordinary item.
StaticPopupDialogs[POPUP] = {
	text = DELETE_ITEM,
	button1 = YES,
	button2 = NO,
	OnAccept = OnAccept,
	timeout = 0,
	whileDead = 1,
	exclusive = 1,
	showAlert = 1,
	hideOnEscape = 1,
}

-- Typing DELETE, as Blizzard asks for a rare or better item (DELETE_GOOD_ITEM in
-- Blizzard_StaticPopup_Game/Mainline/GameDialogDefs.lua).
StaticPopupDialogs[POPUP_GOOD] = {
	text = DELETE_GOOD_ITEM,
	button1 = YES,
	button2 = NO,
	OnAccept = OnAccept,
	timeout = 0,
	whileDead = 1,
	exclusive = 1,
	showAlert = 1,
	hideOnEscape = 1,
	hasEditBox = 1,
	maxLetters = 32,
	OnShow = function(dialog)
		dialog:GetButton1():Disable()
		dialog:GetButton2():Enable()
		dialog:GetEditBox():SetFocus()
	end,
	OnHide = function(dialog)
		dialog:GetEditBox():SetText("")
	end,
	EditBoxOnEnterPressed = function(editBox, data)
		local dialog = editBox:GetParent()
		if dialog:GetButton1():IsEnabled() then
			OnAccept(dialog, data)
			dialog:Hide()
		end
	end,
	EditBoxOnTextChanged = function(editBox)
		StaticPopup_StandardConfirmationTextHandler(editBox, DELETE_ITEM_CONFIRM_STRING)
	end,
	EditBoxOnEscapePressed = function(editBox)
		StaticPopup_StandardEditBoxOnEscapePressed(editBox)
	end,
}

-- Call from an OnClick. Poor and common items are deleted at once; better ones ask first,
-- the way Blizzard's own delete does. onDeleted runs after a delete, onStale when the slot no
-- longer held the entry's stack. Returns "deleted", "confirming" or "stale".
function Delete.Request(entry, onDeleted, onStale)
	if not Delete.Matches(entry) then
		ns.log("DELETE", "stale", entry.link, entry.count)
		return "stale"
	end
	local quality = entry.quality or Enum.ItemQuality.Common
	if quality < Enum.ItemQuality.Uncommon then
		return DeleteNow(entry, onDeleted)
	end
	local which = quality >= Enum.ItemQuality.Rare and POPUP_GOOD or POPUP
	StaticPopup_Show(which, entry.link, nil, { entry = entry, onDeleted = onDeleted, onStale = onStale })
	ns.log("DELETE", "confirming", entry.link, entry.count)
	return "confirming"
end
