local _, ns = ...

-- Action bar support: a slot's key becomes a powershift key when the slot holds a macro that
-- clicks one of the powershift buttons (Shift.lua), for example
--   #showtooltip Bear Form
--   /click RazzhUIPowershiftBear
-- The slot is there for its icon, tooltip and cooldown. A macro runs once per press, so the two
-- steps can't come from the slot itself: the key bound to the slot is pointed at a button of ours
-- instead, with a priority override binding, which wins over the bar's own binding (EllesmereUI's
-- included, whose overrides are not priority ones). A mouse click on the slot still runs the
-- macro, whose /click is the button's "up" step, a plain cast of the form's spell: it takes the
-- form, or leaves it when the character is in it.
--
-- The bars beside and above action bar 1 show the same slots whatever happens, so there the key
-- goes straight to the form's button. Action bar 1 shows another page of slots in each form, all
-- on the same keys, so there the key goes to a dispatcher (RazzhUIPowershiftKey1 to 12) that
-- looks at the slot showing as the key goes down: a slot with a powershift macro is powershifted
-- with that macro's form, any other slot is pressed as the key would have pressed it. So a bear
-- macro on the bear page and a cat macro on the cat page can share a key, and the caster page's
-- slot on that key keeps working.
--
-- Bindings and attributes can't change in combat: a macro moved in a fight is picked up after it.
-- A macro is found by its name (the slot's action text), so of two macros with one name the first
-- is the one read.
--
-- ns.log tag KEYS: what is taken over, as "<key>=<button>" for a bar beside bar 1 and
-- "<key>=<dispatcher>[<slot>:<spell> ...]" for bar 1, whenever it changes.

-- Only druids powershift; for everyone else the scan below would find nothing, at a cost.
if select(2, UnitClass("player")) ~= "DRUID" then
	return
end

local SLOTS_PER_PAGE = 12

-- The binding command (without the button's number) of each bar that always shows one page of
-- action slots (MultiActionBars.xml's actionpage attributes).
local BAR_PAGE_COMMAND = {
	[3] = "MULTIACTIONBAR3BUTTON",
	[4] = "MULTIACTIONBAR4BUTTON",
	[5] = "MULTIACTIONBAR2BUTTON",
	[6] = "MULTIACTIONBAR1BUTTON",
	[13] = "MULTIACTIONBAR5BUTTON",
	[14] = "MULTIACTIONBAR6BUTTON",
	[15] = "MULTIACTIONBAR7BUTTON",
}

-- Action bar 1's pages that can hold a powershift macro: the caster page and the three form pages
-- (bonus bars 1 to 3). Page 2 and bonus page 10 are left out: EllesmereUI gives their slots to
-- bars of its own, with keys of their own.
local MAIN_PAGES = { 1, 7, 8, 9 }
local MAIN_COMMAND = "ACTIONBUTTON"

-- Runs before a dispatcher's own OnClick, as self, button, down. The page is worked out as
-- Blizzard's ActionBarController_UpdateAll does it. A slot with a claim (the attribute
-- "claim-<slot>", a form's spell name) is powershifted: "cancelaura" now, "spell" when the key
-- comes up. Any other slot is pressed: an "action" click, on whichever of the two clicks the
-- player's "cast on key down" setting picks (useOnKeyDown unset).
local DISPATCH_PRE_CLICK = ([[
	if down then
		local page = GetActionBarPage()
		if HasVehicleActionBar() then
			page = GetVehicleBarIndex()
		elseif HasOverrideActionBar() then
			page = GetOverrideBarIndex()
		elseif HasTempShapeshiftActionBar() then
			page = GetTempShapeshiftBarIndex()
		elseif page == 1 and HasBonusActionBar() then
			page = GetBonusBarIndex()
		end
		local slot = (page - 1) * %d + self:GetAttribute("index")
		local claim = self:GetAttribute("claim-" .. slot)
		self:SetAttribute("held", claim)
		if claim then
			self:SetAttribute("spell", claim)
			self:SetAttribute("type", "cancelaura")
			self:SetAttribute("useOnKeyDown", true)
		else
			self:SetAttribute("action", slot)
			self:SetAttribute("type", "action")
			self:SetAttribute("useOnKeyDown", nil)
		end
	else
		local claim = self:GetAttribute("held")
		if claim then
			self:SetAttribute("held", nil)
			self:SetAttribute("spell", claim)
			self:SetAttribute("type", "spell")
			self:SetAttribute("useOnKeyDown", false)
		end
	end
]]):format(SLOTS_PER_PAGE)

local dispatchers = {}
for index = 1, SLOTS_PER_PAGE do
	local name = "RazzhUIPowershiftKey" .. index
	local button = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
	button:RegisterForClicks("AnyDown", "AnyUp")
	button:SetAttribute("index", index)
	SecureHandlerWrapScript(button, "OnClick", button, DISPATCH_PRE_CLICK)
	dispatchers[index] = button
end

-- The form (an entry of ns.Forms) whose powershift button the slot's macro clicks, or nil.
local function SlotForm(slot)
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
		-- The frontier keeps a longer name that starts the same from matching.
		if body:find("/click%s+" .. form.button .. "%f[%W]") then
			return form
		end
	end
	return nil
end

-- What to take over, from the slots as they are now:
--   keys    { [key] = button name }, for the keys to bind
--   claims  { [dispatcher index] = { [slot] = spell name } }, for the dispatchers' attributes
--   text    both as one line, for the log and to tell whether anything changed
local function Wanted()
	local keys, claims, parts = {}, {}, {}

	for page, command in pairs(BAR_PAGE_COMMAND) do
		for index = 1, SLOTS_PER_PAGE do
			local form = SlotForm((page - 1) * SLOTS_PER_PAGE + index)
			if form then
				for _, key in ipairs({ GetBindingKey(command .. index) }) do
					if not keys[key] then
						keys[key] = form.button
						table.insert(parts, key .. "=" .. form.button)
					end
				end
			end
		end
	end

	for index = 1, SLOTS_PER_PAGE do
		local slots = {}
		for _, page in ipairs(MAIN_PAGES) do
			local slot = (page - 1) * SLOTS_PER_PAGE + index
			local form = SlotForm(slot)
			-- A form the character doesn't have has no spell, and so no claim.
			local spell = form and form.frame:GetAttribute("spell")
			if spell then
				claims[index] = claims[index] or {}
				claims[index][slot] = spell
				table.insert(slots, slot .. ":" .. spell)
			end
		end
		if claims[index] then
			local name = dispatchers[index]:GetName()
			for _, key in ipairs({ GetBindingKey(MAIN_COMMAND .. index) }) do
				-- A bar beside bar 1 that got the key first keeps it.
				if not keys[key] then
					keys[key] = name
					table.insert(parts, key .. "=" .. name .. "[" .. table.concat(slots, " ") .. "]")
				end
			end
		end
	end

	table.sort(parts)
	return keys, claims, #parts > 0 and table.concat(parts, " ") or "none"
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
	local keys, claims, text = Wanted()
	-- Setting a binding fires UPDATE_BINDINGS, which queues this again: stop when nothing changed.
	if text == applied then
		return
	end
	applied = text
	for index, button in ipairs(dispatchers) do
		for _, page in ipairs(MAIN_PAGES) do
			local slot = (page - 1) * SLOTS_PER_PAGE + index
			button:SetAttribute("claim-" .. slot, claims[index] and claims[index][slot] or nil)
		end
	end
	ClearOverrideBindings(owner)
	for key, button in pairs(keys) do
		SetOverrideBindingClick(owner, true, key, button, "LeftButton")
	end
	ns.log("KEYS", text)
end

-- Slot, macro and binding events come in bursts (a login fires one per slot). The delay also lets
-- Shift.lua give the form buttons their spells first, which the claims are read from.
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
owner:RegisterEvent("UPDATE_SHAPESHIFT_FORMS")
owner:RegisterEvent("PLAYER_REGEN_ENABLED")
owner:SetScript("OnEvent", Queue)
