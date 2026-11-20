local _, ns = ...

-- One-key powershift buttons: the key going down leaves the form, the key coming up takes it again.
--
-- Leaving a form and taking it again in one step (a macro with /cancelform, then /cast Bear Form)
-- makes the client report no form for three seconds, although the character is in the form: the
-- action bar pages to the caster bar, and the client refuses the form's abilities ("Must be in
-- Bear Form") while the server refuses everything else. Done as two steps a moment apart, the
-- form reads right at once (probed 20 November 2026, ForeverDev's FORM tag). A macro runs once per
-- press, so the two steps come from a key bound straight to one of these buttons, which the client
-- clicks on the way down and again on the way up.
--
-- Each button is a secure action button whose wrapped OnClick picks the step: "cancelaura" for the
-- form's spell on the way down, "spell" on the way up. A secure action button acts on one of the
-- two clicks only, the one its useOnKeyDown attribute names, so the wrap sets that as well.
--
-- ns.log tag SHIFT: spells <button>=<spell name or none> ..., and <button> down|up at each click.

-- The forms worth a powershift, by the spells that can stand for them on the stance bar.
local FORMS = {
	{ button = "RazzhUIPowershiftBear", spells = { [5487] = true, [9634] = true } }, -- Bear, Dire Bear
	{ button = "RazzhUIPowershiftCat", spells = { [768] = true } },
}
ns.Forms = FORMS

-- Runs before the button's own OnClick, as self, button, down. Without a spell (the character
-- doesn't have the form) the click does nothing.
local PRE_CLICK = [[
	if not self:GetAttribute("spell") then
		self:SetAttribute("type", nil)
	elseif down then
		self:SetAttribute("useOnKeyDown", true)
		self:SetAttribute("type", "cancelaura")
	else
		self:SetAttribute("useOnKeyDown", false)
		self:SetAttribute("type", "spell")
	end
]]

for _, form in ipairs(FORMS) do
	local button = CreateFrame("Button", form.button, UIParent, "SecureActionButtonTemplate")
	button:RegisterForClicks("AnyDown", "AnyUp")
	SecureHandlerWrapScript(button, "OnClick", button, PRE_CLICK)
	if ns.dev.enabled then
		button:HookScript("PostClick", function(_, _, down)
			ns.log("SHIFT", form.button, down and "down" or "up")
		end)
	end
	form.frame = button
end

-- The name of the spell on the stance bar that stands for the form, or nil when the character
-- doesn't have it.
local function FormSpellName(form)
	for i = 1, GetNumShapeshiftForms() do
		local _, _, _, spellID = GetShapeshiftFormInfo(i)
		if spellID and not issecretvalue(spellID) and form.spells[spellID] then
			return C_Spell.GetSpellName(spellID)
		end
	end
end

local pending = false

-- Gives each button its form's spell, by name: "cancelaura" takes a name only. Bear Form turning
-- into Dire Bear Form changes it, so this runs again whenever the stance bar's forms change.
local function UpdateSpells()
	if InCombatLockdown() then
		pending = true
		return
	end
	pending = false
	local found = {}
	for _, form in ipairs(FORMS) do
		local name = FormSpellName(form)
		form.frame:SetAttribute("spell", name)
		table.insert(found, form.button .. "=" .. (name or "none"))
	end
	ns.dev:LogChanged("spells", table.concat(found, " "), "SHIFT", "spells", table.concat(found, " "))
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("UPDATE_SHAPESHIFT_FORMS")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event)
	if event ~= "PLAYER_REGEN_ENABLED" or pending then
		UpdateSpells()
	end
end)
