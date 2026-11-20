local _, ns = ...

-- The hold that keeps EllesmereUI's action bar 1 on a form's page through a powershift.
--
-- Leaving a form and taking it again in one press (/cancelform, then /cast Bear Form) makes the
-- client report no form for three seconds: GetShapeshiftForm() and the [form:N] and [bonusbar:N]
-- conditions all say so, and the bar's state driver pages it to the caster page meanwhile. The
-- form then reads right again without an event (probed 20 November 2026, ForeverDev's FORM tag).
--
-- Only secure code can page the bar in combat, and only the player's own press tells a powershift
-- from leaving the form on purpose. So the player's macro starts with
-- "/click RazzhUIPowershiftHold":
--   * the click notes the bar's page on the bar itself (the HOLD_ATTRIBUTE), when in a form;
--   * a wrap on the bar's OnAttributeChanged cancels the bar's own page handler for as long as
--     that hold is set and the client reports no form;
--   * the hold ends when the bar's driver asks for the held page again (the form reads right), or
--     for any page while a form or a vehicle, override or possess bar is reported.
-- A hold whose form never comes back (the recast failed) can't end on a secure signal: secure
-- code has no clock. Out of combat, Release ends it once the power type is mana.
--
-- ns.log tag HOLD: setup <status>, set <page>, cleared, released <reason>.

local BAR_NAME = "EABBar_MainBar"
local HOLD_ATTRIBUTE = "razzhuipowershift-hold"

local Hold = { status = "waiting" }
ns.Hold = Hold

local button = CreateFrame("Button", "RazzhUIPowershiftHold", UIParent, "SecureHandlerClickTemplate")
-- /click passes a release unless the macro says otherwise, a key bound to the button a press.
button:RegisterForClicks("AnyUp", "AnyDown")
button:SetAttribute(
	"_onclick",
	([[
		local bar = self:GetFrameRef("bar")
		if bar and GetShapeshiftForm() > 0 and not bar:GetAttribute("%s") then
			bar:SetAttribute("%s", bar:GetAttribute("state-page"))
		end
	]]):format(HOLD_ATTRIBUTE, HOLD_ATTRIBUTE)
)

-- Runs before the bar's own OnAttributeChanged, as self, name, value. Returning false cancels the
-- bar's handler, so its buttons and keys stay on the page they are on. Blizzard's controller has
-- by then written the caster page to MainActionBar, which the bar's native keys read, so the held
-- page is written there again ("blizzmainbar" is EllesmereUI's own reference to that frame).
local WRAP_PRE_BODY = ([[
	if name ~= "state-page" then
		return
	end
	local hold = self:GetAttribute("%s")
	if not hold then
		return
	end
	if
		tostring(value) ~= tostring(hold)
		and GetShapeshiftForm() == 0
		and SecureCmdOptionParse("[overridebar][vehicleui][possessbar][shapeshift] 1; 0") == "0"
	then
		local blizzard = self:GetFrameRef("blizzmainbar")
		if blizzard then
			blizzard:SetAttribute("actionpage", tonumber(hold) or 1)
		end
		return false
	end
	self:SetAttribute("%s", nil)
]]):format(HOLD_ATTRIBUTE, HOLD_ATTRIBUTE)

local bar

-- Ends a hold nothing secure will end, and has the bar take the page its driver last asked for.
local function Release(reason)
	if not bar or InCombatLockdown() or bar:GetAttribute(HOLD_ATTRIBUTE) == nil then
		return
	end
	-- A powershift that worked never shows mana; one whose recast failed switches to it at once.
	local powerType = UnitPowerType("player")
	if issecretvalue(powerType) or powerType ~= Enum.PowerType.Mana then
		return
	end
	bar:SetAttribute(HOLD_ATTRIBUTE, nil)
	bar:SetAttribute("state-page", bar:GetAttribute("state-page"))
	ns.log("HOLD", "released", reason)
end

local function Setup()
	if Hold.status ~= "waiting" or InCombatLockdown() then
		return
	end
	local frame = _G[BAR_NAME]
	if not (frame and frame.IsProtected and frame:IsProtected()) then
		Hold.status = "nobar"
	else
		bar = frame
		SecureHandlerSetFrameRef(button, "bar", bar)
		SecureHandlerWrapScript(bar, "OnAttributeChanged", button, WRAP_PRE_BODY)
		bar:HookScript("OnAttributeChanged", function(_, name, value)
			if name == HOLD_ATTRIBUTE then
				if value ~= nil then
					ns.log("HOLD", "set", value)
				else
					ns.log("HOLD", "cleared")
				end
			end
		end)
		Hold.status = "ready"
	end
	ns.log("HOLD", "setup", Hold.status)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
events:SetScript("OnEvent", function(_, event)
	if event == "UNIT_DISPLAYPOWER" then
		Release("power")
		return
	end
	-- Every addon has loaded by the first PLAYER_ENTERING_WORLD, EllesmereUI's bars included. After
	-- a reload in combat the setup waits for the combat to end.
	Setup()
	if event == "PLAYER_ENTERING_WORLD" then
		ns.Options.Build()
	else
		Release("combat end")
	end
end)
