local ADDON_NAME, ns = ...

-- The collector: finds other addons' minimap buttons, moves them into a strip that folds out from
-- our bag button (UI/BagButton.lua), keeps them there and puts them back.
--   ns.ButtonBag.Found()                  every button found, ignored and hidden ones too, sorted
--                                         by label: { { key = frame name, label, frame } }
--   ns.ButtonBag.SetIgnored(key, ignored) keeps a button out of the bag (or lets it back in) now
--
-- A collected button is reparented into the strip container, so its own shown state is left alone
-- and closing the bag hides it through the parent. Its parent, strata, level and scale are saved
-- and restored when it leaves. Its anchors are those its addon last gave it (recorded while it is
-- in the bag); a LibDBIcon button is placed by LibDBIcon itself. Blizzard's and protected frames are
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

-- The frame's name, or nil when it has none or it is secret (a frame we can't name is left alone).
local function Name(frame)
	local name = frame:GetName()
	if IsSecret(name) then
		return nil
	end
	return name
end

local function HasHandler(frame, script)
	local has = frame:HasScript(script)
	return not IsSecret(has) and has and frame:GetScript(script) ~= nil
end

-- Whether HereBeDragons-Pins placed this frame on the minimap. `minimapPins` and
-- `activeMinimapPins` are the library's [icon] tables (assumed from HereBeDragons-Pins-2.0's source,
-- not checkable here), read only when present.
local function IsHereBeDragonsPin(frame)
	local pins = LibStub and LibStub("HereBeDragons-Pins-2.0", true)
	if not pins then
		return false
	end
	for _, field in ipairs({ "minimapPins", "activeMinimapPins" }) do
		if type(pins[field]) == "table" and pins[field][frame] ~= nil then
			return true
		end
	end
	return false
end

-- How far the frame's center is from Minimap's, in minimap radii (Logic/ButtonRules.lua), or nil
-- and why not: "secret", or "not placed yet" for a frame not laid out (checked again next scan).
local function RingDistance(frame)
	local x, y = frame:GetCenter()
	local centerX, centerY = Minimap:GetCenter()
	local scale, minimapScale, width = frame:GetEffectiveScale(), Minimap:GetEffectiveScale(), Minimap:GetWidth()
	if IsSecret(x, y, centerX, centerY, scale, minimapScale, width) then
		return nil, "secret"
	end
	if not (x and centerX) or width <= 0 then
		return nil, "not placed yet"
	end
	-- GetCenter is in each frame's own scaled units: compare both in Minimap's.
	scale = scale / minimapScale
	return ns.ButtonRules.RingDistance(x * scale, y * scale, centerX, centerY, width / 2)
end

-- Why a named, non-forbidden minimap child isn't a candidate, or nil when it is one, then its
-- distance from the ring (or why there is none) for the log.
local function Reject(frame, name)
	local distance, why = RingDistance(frame)
	local ring = distance and string.format("%.2f", distance) or why
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
	if IsHereBeDragonsPin(frame) then
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

-- Why a LibDBIcon button must be left alone, or nil. Its name and place are LibDBIcon's, so only
-- the checks that keep us off frames we may not touch apply.
local function RejectLibDBIcon(frame)
	local forbidden = frame:IsForbidden()
	if IsSecret(forbidden) or forbidden then
		return "forbidden"
	end
	local protected = frame:IsProtected()
	if IsSecret(protected) or protected then
		return "protected"
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

-- The addon placing its own button while it is in the bag: remembered, so Release puts it where
-- the addon last wanted it rather than where it was when collected.
local function OnForeignSetPoint(frame, ...)
	local saved = collected[frame]
	if saved and not layingOut then
		table.insert(saved.points, { n = select("#", ...), ... })
	end
	OnForeignMove(frame)
end

local function OnForeignClearAllPoints(frame)
	local saved = collected[frame]
	if saved and not layingOut then
		wipe(saved.points)
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
	hooksecurefunc(frame, "SetPoint", OnForeignSetPoint)
	hooksecurefunc(frame, "ClearAllPoints", OnForeignClearAllPoints)
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
		point.n = 5
		points[i] = point
	end
	-- Nor a parent, strata, level or scale we can't read.
	local parent, scale = frame:GetParent(), frame:GetScale()
	local strata, level = frame:GetFrameStrata(), frame:GetFrameLevel()
	if IsSecret(parent, strata, level, scale) then
		ns.dev:LogOnce(entry.key, "BAG", "skip", "secret", entry.key)
		return
	end
	local libDBIcon = entry.key:find(LIBDBICON_PREFIX) ~= nil
	collected[frame] = {
		parent = parent,
		points = points,
		strata = strata,
		level = level,
		scale = scale,
		key = entry.key,
		label = entry.label,
		libDBIcon = libDBIcon,
		object = libDBIcon and entry.key:match(LIBDBICON_PREFIX .. "(.+)") or nil,
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
	local lib = saved.libDBIcon and LibDBIcon()
	if lib then
		-- LibDBIcon locks a button by clearing its drag scripts, not its drag registration, so the
		-- registration always comes back. Refresh then places the button from its own minimapPos
		-- and applies its hide and lock settings.
		frame:RegisterForDrag("LeftButton")
		lib:Refresh(saved.object)
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
	end
	layingOut = false
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
			local reason = button and RejectLibDBIcon(button)
			local name = button and not reason and Name(button)
			if reason then
				ns.dev:LogOnce(object, "BAG", "skip", reason, object)
			elseif name then
				Consider(button, name)
			end
		end
	end
	for _, parentName in ipairs(PARENTS) do
		local parent = _G[parentName]
		for _, frame in ipairs(parent and { parent:GetChildren() } or {}) do
			-- A forbidden frame refuses every other method call, so this comes first.
			local forbidden = frame:IsForbidden()
			local name = not IsSecret(forbidden) and not forbidden and Name(frame)
			if name then
				local reason, ring
				if not found[name] then
					reason, ring = Reject(frame, name)
				end
				if reason then
					ns.dev:LogOnce(name, "BAG", "skip", reason, name, "ring", ring)
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
