local ADDON_NAME, ns = ...

-- The collector: finds other addons' minimap buttons, moves them into a strip that folds out from
-- our bag button (UI/BagButton.lua), keeps them there and puts them back.
--   ns.ButtonBag.Found()                  every button found, ignored and hidden ones too, sorted
--                                         by label: { { key = frame name, label, frame } }
--   ns.ButtonBag.IsIgnored(key)           whether the player keeps that button on the minimap
--   ns.ButtonBag.SetIgnored(key, ignored) keeps a button out of the bag (or lets it back in) now
--
-- A collected button is reparented into the strip container, so its own shown state is left alone
-- and closing the bag hides it through the parent. Its parent, strata, level and scale are saved
-- and restored when it leaves. Its anchors are those its addon last gave it (recorded while it is
-- in the bag); a LibDBIcon button is placed by LibDBIcon itself. Blizzard's and protected frames are
-- never touched (Logic/ButtonRules.lua and the checks in Reject). Nothing is moved or hooked while
-- the bag is turned off.
ns.ButtonBag = {}

-- A gathered button's size in pixels at 100%, whatever its own (31 is LibDBIcon's and Cinematic's),
-- and the gap between.
local SIZE, GAP = 31, 2

-- Blizzard frames whose named children are looked at.
local PARENTS = { "Minimap", "MinimapBackdrop", "MinimapCluster" }
-- UIParent's children are looked at too, but only those on the minimap's ring: some addons
-- (Cinematic) keep their button there so it isn't shrunk or faded with the minimap.
local RING_PARENTS = { "UIParent" }

local H = ns.ButtonBagHelpers -- Logic/ButtonBagHelpers.lua
local IsSecret, Direction, HasHandler, ByLabel = H.IsSecret, H.Direction, H.HasHandler, H.ByLabel
local LIBDBICON_PREFIX = H.LIBDBICON_PREFIX

local container -- the strip, anchored to our bag button and shown while the bag is open
local found = {} -- [name] = { key, label, frame, fighting = true once its addon fought the bag }
-- [frame] = { parent, points, strata, level, scale } for Release to restore, plus key, label,
-- libDBIcon, object (its LibDBIcon name) and moves/movesSince (foreign re-anchors, see OnForeignMove)
local collected = {}
local hooked = {} -- [frame] = true once its hooks are in (hooks can't be removed)
local layingOut = false -- set while our own calls move a frame, so its hooks ignore them
local layoutPending, scanPending = false, false
local libDBIconRegistered = false

local function LibDBIcon()
	return LibStub and LibStub("LibDBIcon-1.0", true)
end

local function Enabled()
	return ns.Options.Get("showButtonBag")
end

-- The size setting, kept in the slider's range; a hand-edited one that isn't a number reads as 1.
local function Scale()
	local scale = ns.Options.Get("buttonBagScale")
	if type(scale) ~= "number" then
		return 1
	end
	return math.min(math.max(scale, ns.Options.SCALE_MIN), ns.Options.SCALE_MAX)
end

-- Why a named, non-forbidden minimap child isn't a candidate, or nil when it is one, then its
-- distance from the ring (or why there is none) for the log.
local function Reject(frame, name)
	local distance, why = H.RingDistance(frame)
	local ring = distance or why
	local verdict = ns.ButtonRules.Verdict(name)
	if verdict ~= "ok" then
		return verdict, ring
	end
	if _G[name] ~= frame then
		return "not its global", ring
	end
	if frame == ns.BagButton or frame == container then
		return "ours", ring
	end
	local protected = frame:IsProtected()
	if IsSecret(protected) or protected then
		return "protected", ring
	end
	local isButton = frame:IsObjectType("Button")
	if IsSecret(isButton) or not isButton then
		return "not a button", ring
	end
	if not HasHandler(frame, "OnClick") then
		return "not clickable", ring
	end
	if H.IsHereBeDragonsPin(frame) then
		return "pin", ring
	end
	if not distance then
		return why, ring
	end
	if not ns.ButtonRules.NearRing(distance) then
		return "off the ring", ring
	end
	-- Unverified in Forever: without it the other checks alone decide.
	if issecurevariable and issecurevariable(_G, name) then
		return "secure", ring
	end
	return nil, ring
end

-- Lays the shown collected buttons out along the strip, sorted by label, each SIZE pixels across
-- times the size setting.
local function Layout()
	local size = SIZE * Scale()
	local shown = {}
	layingOut = true
	for frame, saved in pairs(collected) do
		-- Taken back by its addon (a foreign SetParent): bring it home.
		if frame:GetParent() ~= container then
			frame:SetParent(container)
		end
		-- A shown state we can't read leaves the frame out of the layout.
		local isShown = frame:IsShown()
		if not IsSecret(isShown) and isShown then
			table.insert(shown, { frame = frame, label = saved.label, key = saved.key })
		end
	end
	table.sort(shown, ByLabel)
	local direction = Direction()
	for i, entry in ipairs(shown) do
		local frame = entry.frame
		-- Scaled rather than resized, so its own art and children keep their layout.
		local width = frame:GetWidth()
		local scale = (not IsSecret(width) and width > 0) and size / width or 1
		frame:SetScale(scale)
		local x, y = ns.Strip.Offset(i, direction, ns.Strip.PER_LINE, size, GAP)
		frame:ClearAllPoints()
		-- Offsets are in the frame's own (scaled) units.
		frame:SetPoint("CENTER", container, "CENTER", x / scale, y / scale)
	end
	layingOut = false
end

-- Debounced to the next frame, so a burst of foreign re-anchors lays out once.
local function LayoutSoon()
	if layoutPending then
		return
	end
	layoutPending = true
	C_Timer.After(0, function()
		layoutPending = false
		Layout()
	end)
end

local Release

-- An addon that re-anchors its button more than FIGHT_MOVES times in FIGHT_SECONDS is fighting the
-- bag: the button goes back to it and stays out for the session.
local FIGHT_MOVES, FIGHT_SECONDS = 10, 1

local function OnForeignMove(frame)
	local saved = collected[frame]
	if not saved or layingOut then
		return
	end
	if ns.dev.enabled then
		ns.log("BAG", "reanchor", frame:GetName())
	end
	local now = GetTime()
	if not saved.movesSince or now - saved.movesSince > FIGHT_SECONDS then
		saved.movesSince, saved.moves = now, 0
	end
	saved.moves = saved.moves + 1
	if saved.moves > FIGHT_MOVES then
		found[saved.key].fighting = true
		ns.log("BAG", "fighting", saved.key)
		Release(frame)
	end
	LayoutSoon()
end

-- The addon placing its own button while it is in the bag: remembered, so Release puts it where
-- the addon last wanted it rather than where it was when collected. Not for a button found off the
-- minimap: its addon places it on UIParent by its own (in the bag, much smaller) scale, so those
-- anchors would be wrong once Release gives its scale back, and the ones from before it was
-- collected are kept instead.
local function Remembers(saved)
	return saved and not saved.offMinimap and not layingOut
end

local function OnForeignSetPoint(frame, ...)
	local saved = collected[frame]
	if Remembers(saved) then
		table.insert(saved.points, { n = select("#", ...), ... })
	end
	OnForeignMove(frame)
end

local function OnForeignClearAllPoints(frame)
	local saved = collected[frame]
	if Remembers(saved) then
		wipe(saved.points)
	end
	if saved and not layingOut then
		LayoutSoon()
	end
end

local function OnShownChanged(frame)
	if collected[frame] and not layingOut then
		LayoutSoon()
	end
end

-- No dragging in the strip: a drag would pull the button out (and a LibDBIcon drag rewrites its
-- addon's saved minimapPos), so drag registration is cleared on collect and again whenever its
-- addon (or LibDBIcon's Refresh or Unlock) registers it while the button is in the bag.
local clearingDrag = false

local function ClearDrag(frame)
	clearingDrag = true
	frame:RegisterForDrag()
	clearingDrag = false
end

-- What its addon registers while the button is in the bag is what Release gives back.
local function OnForeignRegisterForDrag(frame, ...)
	local saved = collected[frame]
	if saved and not clearingDrag then
		saved.drag = { n = select("#", ...), ... }
		ClearDrag(frame)
	end
end

local function Hook(frame)
	if hooked[frame] then
		return
	end
	hooked[frame] = true
	hooksecurefunc(frame, "SetPoint", OnForeignSetPoint)
	hooksecurefunc(frame, "ClearAllPoints", OnForeignClearAllPoints)
	hooksecurefunc(frame, "SetParent", OnForeignMove)
	hooksecurefunc(frame, "Show", OnShownChanged)
	hooksecurefunc(frame, "Hide", OnShownChanged)
	hooksecurefunc(frame, "SetShown", OnShownChanged)
	hooksecurefunc(frame, "RegisterForDrag", OnForeignRegisterForDrag)
end

-- Sets a frame's strata and level, then fixes each again if `fixedStrata` / `fixedLevel` say so.
-- A fixed strata or level ignores SetFrameStrata / SetFrameLevel, and LibDBIcon fixes its buttons at
-- MEDIUM 8, under the open strip and the frames round the minimap; so the fix is lifted for the set.
local function SetLayer(frame, strata, level, fixedStrata, fixedLevel)
	frame:SetFixedFrameStrata(false)
	frame:SetFixedFrameLevel(false)
	frame:SetFrameStrata(strata)
	frame:SetFrameLevel(level)
	frame:SetFixedFrameStrata(fixedStrata)
	frame:SetFixedFrameLevel(fixedLevel)
end

local function Collect(frame, entry)
	if collected[frame] or entry.fighting then
		return
	end
	local points = {}
	for i = 1, frame:GetNumPoints() do
		local point = { frame:GetPoint(i) }
		-- An anchor we can't read is one we couldn't restore: leave the frame where it is.
		if IsSecret(unpack(point, 1, 5)) then
			if ns.dev.enabled then
				ns.dev:LogOnce("secret:" .. entry.key, "BAG", "secret", "anchor", entry.key)
			end
			return
		end
		point.n = 5
		points[i] = point
	end
	-- Nor a parent, strata, level or scale we can't read.
	local parent, scale = frame:GetParent(), frame:GetScale()
	local strata, level = frame:GetFrameStrata(), frame:GetFrameLevel()
	local fixedStrata, fixedLevel = frame:HasFixedFrameStrata(), frame:HasFixedFrameLevel()
	if IsSecret(parent, strata, level, scale, fixedStrata, fixedLevel) then
		if ns.dev.enabled then
			ns.dev:LogOnce("secret:" .. entry.key, "BAG", "secret", "frame values", entry.key)
		end
		return
	end
	local libDBIcon = entry.key:find(LIBDBICON_PREFIX) ~= nil
	collected[frame] = {
		parent = parent,
		points = points,
		strata = strata,
		level = level,
		fixedStrata = fixedStrata,
		fixedLevel = fixedLevel,
		scale = scale,
		key = entry.key,
		label = entry.label,
		offMinimap = entry.offMinimap,
		libDBIcon = libDBIcon,
		object = libDBIcon and entry.key:match(LIBDBICON_PREFIX .. "(.+)") or nil,
	}
	layingOut = true
	frame:SetParent(container)
	SetLayer(frame, container:GetFrameStrata(), container:GetFrameLevel() + 2, fixedStrata, fixedLevel)
	layingOut = false
	-- LibDBIcon's showOnMouseover fades a button out; in the bag it is always visible. Release's
	-- Refresh hands the alpha back to LibDBIcon, and the saved one is put back first in case it doesn't.
	if libDBIcon then
		local alpha = frame:GetAlpha()
		collected[frame].alpha = not IsSecret(alpha) and alpha or nil
		frame:SetAlpha(1)
	end
	ClearDrag(frame)
	Hook(frame)
	if ns.dev.enabled then
		ns.dev:LogOnce("collect:" .. entry.key, "BAG", "collect", entry.key)
	end
end

-- Puts a collected frame back as it was. A no-op for frames not collected.
function Release(frame)
	local saved = collected[frame]
	if not saved then
		return
	end
	collected[frame] = nil
	ns.log("BAG", "release", saved.key)
	layingOut = true
	frame:SetParent(saved.parent)
	frame:SetScale(saved.scale)
	SetLayer(frame, saved.strata, saved.level, saved.fixedStrata, saved.fixedLevel)
	local lib = saved.libDBIcon and LibDBIcon()
	if lib then
		-- LibDBIcon locks a button by clearing its drag scripts, not its drag registration, so the
		-- registration always comes back. Refresh then places the button from its own minimapPos
		-- and applies its hide and lock settings.
		frame:RegisterForDrag("LeftButton")
		if saved.alpha then
			frame:SetAlpha(saved.alpha)
		end
		-- Handing back the db the addon registered changes nothing; the annotation wants one.
		local button = lib:GetMinimapButton(saved.object)
		if button then
			lib:Refresh(saved.object, button.db)
		end
	else
		frame:ClearAllPoints()
		for _, point in ipairs(saved.points) do
			frame:SetPoint(unpack(point, 1, point.n))
		end
		-- Its addon cleared its anchors and never set new ones: somewhere visible beats nowhere.
		if #saved.points == 0 then
			frame:SetPoint("CENTER", Minimap, "CENTER")
			ns.log("BAG", "release", "noanchor", saved.key)
		end
		-- The client can't read a drag registration back. One its addon made while the button was in
		-- the bag is given back exactly; otherwise a button with a drag script gets the usual
		-- left-button drag (a registration without a drag script does nothing).
		if saved.drag then
			frame:RegisterForDrag(unpack(saved.drag, 1, saved.drag.n))
		elseif HasHandler(frame, "OnDragStart") then
			frame:RegisterForDrag("LeftButton")
		end
	end
	layingOut = false
end

local function Consider(frame, name, offMinimap)
	local entry = found[name]
	if not entry then
		entry = { key = name, label = H.Label(name), frame = frame, offMinimap = offMinimap or nil }
		found[name] = entry
	end
	if Enabled() and not ns.db.buttonBag.ignored[name] then
		Collect(frame, entry)
	end
end

local Scan

local function ScanSoon()
	if scanPending then
		return
	end
	scanPending = true
	C_Timer.After(0, function()
		scanPending = false
		Scan()
	end)
end

-- Off the minimap, only a frame about the size of a minimap button counts (LibDBIcon's and
-- Cinematic's are 31 pixels): toolbars and panels near the minimap are left alone.
local MAX_RING_SIZE = 40

-- [frame] = true while a UIParent button that had no place at scan time waits for its first
-- SetPoint (Cinematic places its button only while the minimap is shown), false after.
local waiting = {}

local function WaitForPlacement(frame)
	if waiting[frame] ~= nil then
		return
	end
	waiting[frame] = true
	hooksecurefunc(frame, "SetPoint", function()
		if waiting[frame] then
			waiting[frame] = false
			ScanSoon()
		end
	end)
end

-- Whether a UIParent child could be a minimap button: a clickable button of a button's size whose
-- center is in the band round the minimap's edge. One not placed yet is looked at again once it is.
local function OnRing(frame)
	local isButton = frame:IsObjectType("Button")
	if IsSecret(isButton) or not isButton or not HasHandler(frame, "OnClick") then
		return false
	end
	local width, height = frame:GetSize()
	if IsSecret(width, height) or width > MAX_RING_SIZE or height > MAX_RING_SIZE then
		return false
	end
	local distance, why = H.RingDistance(frame)
	if why == "not placed yet" then
		WaitForPlacement(frame)
	end
	return distance ~= nil and ns.ButtonRules.NearRing(distance)
end

-- Considers the parent's named children. With ringOnly, children that can't be a button on the
-- minimap's ring are passed over unlogged: UIParent has hundreds of them.
local function ScanChildren(parent, ringOnly)
	for _, frame in ipairs(parent and { parent:GetChildren() } or {}) do
		-- GetChildren may return secret frames (its Hierarchy aspect); those are left alone. A
		-- forbidden frame refuses every other method call, so that check comes next.
		local forbidden = not IsSecret(frame) and frame:IsForbidden()
		local name = forbidden == false and H.Name(frame)
		if name and (found[name] or not ringOnly or OnRing(frame)) then
			local reason, ring
			if not found[name] then
				reason, ring = Reject(frame, name)
			end
			if reason then
				if ns.dev.enabled then
					ring = type(ring) == "number" and string.format("%.2f", ring) or ring
					ns.dev:LogOnce("skip:" .. name .. reason, "BAG", "skip", reason, name, "ring", ring)
				end
			else
				Consider(frame, name, ringOnly)
			end
		end
	end
end

-- Finds the candidates (always: it only reads) and collects them (only while the bag is on).
function Scan()
	local lib = LibDBIcon()
	if lib then
		if not libDBIconRegistered then
			libDBIconRegistered = true
			lib.RegisterCallback(ns.ButtonBag, "LibDBIcon_IconCreated", ScanSoon)
		end
		-- It returns the registered names (the annotation says buttons).
		local objects = lib:GetButtonList() --[[@as string[] ]]
		for _, object in ipairs(objects) do
			local button = lib:GetMinimapButton(object)
			local reason = button and H.RejectLibDBIcon(button)
			local name = button and not reason and H.Name(button)
			if reason then
				if ns.dev.enabled then
					ns.dev:LogOnce("skip:" .. object .. reason, "BAG", "skip", reason, object)
				end
			elseif name then
				Consider(button, name)
			end
		end
	end
	for _, parentName in ipairs(PARENTS) do
		ScanChildren(_G[parentName], false)
	end
	for _, parentName in ipairs(RING_PARENTS) do
		ScanChildren(_G[parentName], true)
	end
	Layout()
end

function ns.ButtonBag.Found()
	local list = {}
	for _, entry in pairs(found) do
		table.insert(list, entry)
	end
	table.sort(list, ByLabel)
	return list
end

function ns.ButtonBag.IsIgnored(key)
	return ns.db.buttonBag.ignored[key] == true
end

function ns.ButtonBag.SetIgnored(key, ignored)
	if not key then
		return
	end
	ns.db.buttonBag.ignored[key] = ignored and true or nil
	local entry = found[key]
	if not entry then
		return
	end
	if ignored then
		Release(entry.frame)
	elseif Enabled() then
		Collect(entry.frame, entry)
	end
	Layout()
end

-- Turning the bag on collects; turning it off puts every button back.
local function Refresh()
	if Enabled() then
		Scan()
	else
		for frame in pairs(collected) do
			Release(frame)
		end
	end
end

-- OptionChanged fires for every setting; only the bag's three matter here.
local lastEnabled, lastDirection, lastScale

local function OnOptionChanged()
	local enabled, direction, scale = Enabled(), Direction(), Scale()
	if enabled ~= lastEnabled then
		lastEnabled, lastDirection, lastScale = enabled, direction, scale
		Refresh()
	elseif direction ~= lastDirection or scale ~= lastScale then
		lastDirection, lastScale = direction, scale
		Layout()
	end
end

-- Runs after UI/BagButton.lua's initializer (TOC order), which creates ns.BagButton.
ns.OnInitialize(function()
	container = CreateFrame("Frame", nil, ns.BagButton)
	-- Above the minimap cluster and most addon frames, so the open strip isn't drawn under them.
	container:SetFrameStrata("HIGH")
	container:SetSize(1, 1)
	container:SetPoint("CENTER", ns.BagButton, "CENTER")
	container:SetShown(ns.BagButton:IsOpen())
	ns.callbacks:RegisterCallback("BagToggled", function(_, open)
		container:SetShown(open)
	end, ns.ButtonBag)
	lastEnabled, lastDirection, lastScale = Enabled(), Direction(), Scale()
	ns.callbacks:RegisterCallback("OptionChanged", OnOptionChanged, ns.ButtonBag)

	local events = CreateFrame("Frame")
	events:RegisterEvent("PLAYER_LOGIN")
	events:RegisterEvent("ADDON_LOADED")
	events:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_LOGIN" then
			Scan()
			-- Some addons make their button a little after login.
			C_Timer.After(2, Scan)
		else
			ScanSoon()
		end
	end)
end)
