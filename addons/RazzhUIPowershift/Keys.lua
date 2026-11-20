local _, ns = ...

-- Action bar support: a slot's key becomes a powershift key when the slot holds a macro that
-- clicks one of the powershift buttons, for example
--   #showtooltip Bear Form
--   /click RazzhUIPowershiftBear
-- The slot is there for its icon, tooltip and cooldown. A macro runs once per press, so the two
-- steps can't come from the slot itself: the key bound to the slot is pointed at the button
-- instead, with a priority override binding, which wins over the bar's own binding (EllesmereUI's
-- included, whose overrides are not priority ones). A mouse click on the slot still runs the
-- macro, whose /click is the button's "up" step: it casts the form, as the form's own button does.
--
-- A key is one binding on every page of its bar, so on action bar 1 the key powershifts whatever
-- page is showing. Bindings can't change in combat: a macro moved in a fight is picked up after it.
--
-- ns.log tag KEYS: the keys taken over, as "<key>=<button> ...", whenever they change.

local SLOTS_PER_PAGE = 12
local LAST_SLOT = 180

-- The binding command (without the button's number) for each page of action slots. Pages 3 to 6
-- are the bars beside and above action bar 1 as well as its manual pages; the bars' keys are the
-- ones that reach them. Pages 7 to 10 are action bar 1's bonus pages (forms and stances).
local PAGE_COMMAND = {
	[1] = "ACTIONBUTTON",
	[2] = "ACTIONBUTTON",
	[3] = "MULTIACTIONBAR3BUTTON",
	[4] = "MULTIACTIONBAR4BUTTON",
	[5] = "MULTIACTIONBAR2BUTTON",
	[6] = "MULTIACTIONBAR1BUTTON",
	[7] = "ACTIONBUTTON",
	[8] = "ACTIONBUTTON",
	[9] = "ACTIONBUTTON",
	[10] = "ACTIONBUTTON",
	[13] = "MULTIACTIONBAR5BUTTON",
	[14] = "MULTIACTIONBAR6BUTTON",
	[15] = "MULTIACTIONBAR7BUTTON",
}

-- The binding command whose key presses the slot, or nil for a slot no bar key reaches.
local function SlotCommand(slot)
	local prefix = PAGE_COMMAND[math.floor((slot - 1) / SLOTS_PER_PAGE) + 1]
	return prefix and (prefix .. ((slot - 1) % SLOTS_PER_PAGE + 1))
end

-- The name of the powershift button the slot's macro clicks, or nil.
local function SlotButton(slot)
	if not C_ActionBar.HasAction(slot) then
		return nil
	end
	-- A macro's action text is its name, which GetMacroBody takes.
	local name = C_ActionBar.GetActionText(slot)
	if not name or issecretvalue(name) or name == "" then
		return nil
	end
	local body = GetMacroBody(name)
	if not body then
		return nil
	end
	for _, form in ipairs(ns.Forms) do
		if body:find("/click%s+" .. form.button) then
			return form.button
		end
	end
	return nil
end

-- Returns { [key] = button name } for every key of a slot whose macro clicks a powershift button.
-- The first slot to claim a key keeps it.
local function WantedKeys()
	local keys = {}
	for slot = 1, LAST_SLOT do
		local command = SlotCommand(slot)
		local button = command and SlotButton(slot)
		if button then
			for _, key in ipairs({ GetBindingKey(command) }) do
				keys[key] = keys[key] or button
			end
		end
	end
	return keys
end

local function Describe(keys)
	local parts = {}
	for key, button in pairs(keys) do
		table.insert(parts, key .. "=" .. button)
	end
	table.sort(parts)
	return #parts > 0 and table.concat(parts, " ") or "none"
end

local owner = CreateFrame("Frame")
local applied = "none"
local queued = false

local function Apply()
	queued = false
	if InCombatLockdown() then
		-- PLAYER_REGEN_ENABLED queues it again.
		return
	end
	local keys = WantedKeys()
	local described = Describe(keys)
	-- Setting a binding fires UPDATE_BINDINGS, which queues this again: stop when nothing changed.
	if described == applied then
		return
	end
	applied = described
	ClearOverrideBindings(owner)
	for key, button in pairs(keys) do
		SetOverrideBindingClick(owner, true, key, button, "LeftButton")
	end
	ns.log("KEYS", described)
end

-- Slot, macro and binding events come in bursts (a login fires one per slot).
local function Queue()
	if not queued then
		queued = true
		C_Timer.After(0.2, Apply)
	end
end

owner:RegisterEvent("PLAYER_ENTERING_WORLD")
owner:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
owner:RegisterEvent("UPDATE_BINDINGS")
owner:RegisterEvent("UPDATE_MACROS")
owner:RegisterEvent("PLAYER_REGEN_ENABLED")
owner:SetScript("OnEvent", Queue)
