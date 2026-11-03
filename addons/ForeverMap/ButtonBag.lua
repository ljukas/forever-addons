local ADDON_NAME, ns = ...

-- The collector: finds other addons' minimap buttons, moves them into a strip that folds out from
-- our bag button (UI/BagButton.lua), keeps them there and puts them back.
--   ns.ButtonBag.Found()                  every button found, ignored and hidden ones too, sorted
--                                         by label: { { key = frame name, label, frame } }
--   ns.ButtonBag.SetIgnored(key, ignored) keeps a button out of the bag (or lets it back in) now
--
-- A collected button is reparented into the strip container, so its own shown state is left alone
-- and closing the bag hides it through the parent. Everything it had before (parent, points,
-- strata, level, scale) is saved and restored when it leaves. Blizzard's and protected frames are
-- never touched (Logic/ButtonRules.lua and the checks in Reject). Nothing is moved or hooked while
-- the bag is turned off.
ns.ButtonBag = {}

local SIZE, GAP = 24, 2

-- Blizzard frames whose named children are looked at.
local PARENTS = { "Minimap", "MinimapBackdrop", "MinimapCluster" }

local LIBDBICON_PREFIX = "^LibDBIcon10_"

local container -- the strip, anchored to our bag button and shown while the bag is open
local found = {} -- [name] = { key, label, frame }
-- [frame] = { parent, points, strata, level, scale } for Release to restore, plus key, label, libDBIcon
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

local function IsSecret(...)
	for i = 1, select("#", ...) do
		if issecretvalue(select(i, ...)) then
			return true
		end
	end
	return false
end

-- A hand-edited direction outside the four falls back to DOWN.
local function Direction()
	local direction = ns.Options.Get("buttonBagDirection")
	for _, value in pairs(ns.Options.DIRECTION) do
		if direction == value then
			return direction
		end
	end
	return ns.Options.DIRECTION.DOWN
end

-- The LibDBIcon object name, else the title of the addon that created the frame (when
-- issecurevariable exists and knows), else the frame name.
local function Label(name)
	local object = name:match(LIBDBICON_PREFIX .. "(.+)")
	if object then
		return object
	end
	if issecurevariable then
		local secure, addon = issecurevariable(_G, name)
		if not secure and type(addon) == "string" and C_AddOns.DoesAddOnExist(addon) then
			return C_AddOns.GetAddOnTitle(addon) or name
		end
	end
	return name
end

local function HasHandler(frame, script)
	local has = frame:HasScript(script)
	return not IsSecret(has) and has and frame:GetScript(script) ~= nil
end

-- Why a named, non-forbidden minimap child isn't a candidate, or nil when it is one.
local function Reject(frame, name)
	local verdict = ns.ButtonRules.Verdict(name)
	if verdict ~= "ok" then
		return verdict
	end
	if _G[name] ~= frame then
		return "not its global"
	end
	if frame == ns.BagButton or frame == container then
		return "ours"
	end
	local protected = frame:IsProtected()
	if IsSecret(protected) or protected then
		return "protected"
	end
	if not HasHandler(frame, "OnClick") and not HasHandler(frame, "OnMouseUp") then
		return "not clickable"
	end
	-- Unverified in Forever: without it the name rules alone decide.
	if issecurevariable and issecurevariable(_G, name) then
		return "secure"
	end
	return nil
end

local function ByLabel(a, b)
	if a.label ~= b.label then
		return a.label < b.label
	end
	return a.key < b.key
end

-- Lays the shown collected buttons out along the strip, sorted by label, each SIZE pixels across.
local function Layout()
	local shown = {}
	layingOut = true
	for frame, saved in pairs(collected) do
		-- Taken back by its addon (a foreign SetParent): bring it home.
		if frame:GetParent() ~= container then
			frame:SetParent(container)
		end
		if frame:IsShown() then
			table.insert(shown, { frame = frame, label = saved.label, key = saved.key })
		end
	end
	table.sort(shown, ByLabel)
	local direction = Direction()
	for i, entry in ipairs(shown) do
		local frame = entry.frame
		-- Scaled rather than resized, so its own art and children keep their layout.
		local width = frame:GetWidth()
		local scale = (not IsSecret(width) and width > 0) and SIZE / width or 1
		frame:SetScale(scale)
		local x, y = ns.Strip.Offset(i, direction, ns.Strip.PER_LINE, SIZE, GAP)
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

local function OnForeignMove(frame)
	if collected[frame] and not layingOut then
		if ns.dev.enabled then
			ns.log("BAG", "reanchor", frame:GetName())
		end
		LayoutSoon()
	end
end

local function OnShownChanged(frame)
	if collected[frame] and not layingOut then
		Layout()
	end
end

local function Hook(frame, libDBIcon)
	if hooked[frame] then
		return
	end
	hooked[frame] = true
	hooksecurefunc(frame, "SetPoint", OnForeignMove)
	hooksecurefunc(frame, "SetParent", OnForeignMove)
	hooksecurefunc(frame, "Show", OnShownChanged)
	hooksecurefunc(frame, "Hide", OnShownChanged)
	hooksecurefunc(frame, "SetShown", OnShownChanged)
	-- A hand-made button that moves itself on drag goes back to its slot when the drag ends.
	if not libDBIcon and frame:HasScript("OnDragStop") then
		frame:HookScript("OnDragStop", OnShownChanged)
	end
end

local function Collect(frame, entry)
	if collected[frame] then
		return
	end
	local points = {}
	for i = 1, frame:GetNumPoints() do
		local point = { frame:GetPoint(i) }
		-- An anchor we can't read is one we couldn't restore: leave the frame where it is.
		if IsSecret(unpack(point, 1, 5)) then
			ns.dev:LogOnce(entry.key, "BAG", "skip", "secret anchor", entry.key)
			return
		end
		points[i] = point
	end
	local libDBIcon = entry.key:find(LIBDBICON_PREFIX) ~= nil
	collected[frame] = {
		parent = frame:GetParent(),
		points = points,
		strata = frame:GetFrameStrata(),
		level = frame:GetFrameLevel(),
		scale = frame:GetScale(),
		key = entry.key,
		label = entry.label,
		libDBIcon = libDBIcon,
	}
	layingOut = true
	frame:SetParent(container)
	frame:SetFrameStrata(container:GetFrameStrata())
	frame:SetFrameLevel(container:GetFrameLevel() + 2)
	layingOut = false
	-- No dragging in the strip: a LibDBIcon drag would pull the button out and rewrite its
	-- addon's saved minimapPos.
	if libDBIcon then
		frame:RegisterForDrag()
	end
	Hook(frame, libDBIcon)
end

-- Puts a collected frame back as it was. A no-op for frames not collected.
local function Release(frame)
	local saved = collected[frame]
	if not saved then
		return
	end
	collected[frame] = nil
	layingOut = true
	frame:SetParent(saved.parent)
	frame:SetScale(saved.scale)
	frame:SetFrameStrata(saved.strata)
	frame:SetFrameLevel(saved.level)
	frame:ClearAllPoints()
	for _, point in ipairs(saved.points) do
		frame:SetPoint(unpack(point, 1, 5))
	end
	layingOut = false
	-- A button its player locked in LibDBIcon stays undraggable.
	if saved.libDBIcon and not (frame.db and frame.db.lock) then
		frame:RegisterForDrag("LeftButton")
	end
end

local function Consider(frame, name)
	local entry = found[name]
	if not entry then
		entry = { key = name, label = Label(name), frame = frame }
		found[name] = entry
		ns.dev:LogOnce(name, "BAG", "collect", "ok", name)
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

-- Finds the candidates (always: it only reads) and collects them (only while the bag is on).
function Scan()
	local lib = LibDBIcon()
	if lib then
		if not libDBIconRegistered then
			libDBIconRegistered = true
			lib.RegisterCallback(ns.ButtonBag, "LibDBIcon_IconCreated", ScanSoon)
		end
		for _, object in ipairs(lib:GetButtonList()) do
			local button = lib:GetMinimapButton(object)
			local name = button and button:GetName()
			if name then
				Consider(button, name)
			end
		end
	end
	for _, parentName in ipairs(PARENTS) do
		local parent = _G[parentName]
		for _, frame in ipairs(parent and { parent:GetChildren() } or {}) do
			-- A forbidden frame refuses every other method call, so this comes first.
			local forbidden = frame:IsForbidden()
			local name = not IsSecret(forbidden) and not forbidden and frame:GetName()
			if name then
				local reason = not found[name] and Reject(frame, name)
				if reason then
					ns.dev:LogOnce(name, "BAG", "skip", reason, name)
				else
					Consider(frame, name)
				end
			end
		end
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

-- Runs after UI/BagButton.lua's initializer (TOC order), which creates ns.BagButton.
ns.OnInitialize(function()
	container = CreateFrame("Frame", nil, ns.BagButton)
	container:SetSize(1, 1)
	container:SetPoint("CENTER", ns.BagButton, "CENTER")
	container:SetShown(ns.BagButton:IsOpen())
	ns.callbacks:RegisterCallback("BagToggled", function(_, open)
		container:SetShown(open)
	end, ns.ButtonBag)
	-- Any setting: the bag turned on or off, or the direction changed.
	ns.callbacks:RegisterCallback("OptionChanged", Refresh, ns.ButtonBag)

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
