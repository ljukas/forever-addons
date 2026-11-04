local ADDON_NAME, ns = ...

-- Small helpers for the button bag's collector (ButtonBag.lua), kept apart so that file stays about
-- moving buttons. Unlike the other Logic files these read the client (frames, settings, libraries),
-- but none of them changes anything.
--   IsSecret(...)               whether any argument is a secret value
--   Direction()                 the bag's direction setting, DOWN when hand-edited to something else
--   Label(name)                 what the ignore menu calls a button
--   Name(frame)                 the frame's name, nil when it has none or it is secret
--   HasHandler(frame, script)   whether the frame has a handler for `script`
--   IsHereBeDragonsPin(frame)   whether HereBeDragons-Pins placed the frame on the minimap
--   RingDistance(frame)         how far its center is from Minimap's, in minimap radii, or nil and why
--   RejectLibDBIcon(frame)      why a LibDBIcon button must be left alone, or nil
--   ByLabel(a, b)               sort order of { key, label } entries
ns.ButtonBagHelpers = {}
local H = ns.ButtonBagHelpers

H.LIBDBICON_PREFIX = "^LibDBIcon10_"

function H.IsSecret(...)
	for i = 1, select("#", ...) do
		if issecretvalue(select(i, ...)) then
			return true
		end
	end
	return false
end

-- A hand-edited direction outside the four falls back to DOWN.
function H.Direction()
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
function H.Label(name)
	local object = name:match(H.LIBDBICON_PREFIX .. "(.+)")
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
function H.Name(frame)
	local name = frame:GetName()
	if H.IsSecret(name) then
		return nil
	end
	return name
end

function H.HasHandler(frame, script)
	local has = frame:HasScript(script)
	return not H.IsSecret(has) and has and frame:GetScript(script) ~= nil
end

-- `minimapPins` and `activeMinimapPins` are HereBeDragons-Pins-2.0's [icon] tables (assumed from
-- the library's source, not checkable here), read only when present.
function H.IsHereBeDragonsPin(frame)
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
function H.RingDistance(frame)
	local x, y = frame:GetCenter()
	local centerX, centerY = Minimap:GetCenter()
	local scale, minimapScale, width = frame:GetEffectiveScale(), Minimap:GetEffectiveScale(), Minimap:GetWidth()
	if H.IsSecret(x, y, centerX, centerY, scale, minimapScale, width) then
		return nil, "secret"
	end
	if not (x and centerX) or width <= 0 then
		return nil, "not placed yet"
	end
	-- GetCenter is in each frame's own scaled units: compare both in Minimap's.
	scale = scale / minimapScale
	return ns.ButtonRules.RingDistance(x * scale, y * scale, centerX, centerY, width / 2)
end

-- Its name and place are LibDBIcon's, so only the checks that keep us off frames we may not touch
-- apply.
function H.RejectLibDBIcon(frame)
	local forbidden = frame:IsForbidden()
	if H.IsSecret(forbidden) or forbidden then
		return "forbidden"
	end
	local protected = frame:IsProtected()
	if H.IsSecret(protected) or protected then
		return "protected"
	end
	return nil
end

function H.ByLabel(a, b)
	if a.label ~= b.label then
		return a.label < b.label
	end
	return a.key < b.key
end
