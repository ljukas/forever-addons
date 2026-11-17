local ADDON_NAME, ns = ...

-- Finds the modules (the addons whose TOC lists this core in ## Dependencies) from the client's
-- addon list, so the core never holds a list of them, and reads or changes whether each is
-- enabled. ns.log tags: MODULES (what was found, probes at login), TOGGLE (SetEnabled).
local Modules = {}
ns.Modules = Modules

local list, byFolder

-- The title without colour codes and without the module prefix; a title that doesn't start with the
-- prefix comes back unchanged apart from the removed codes. Pure.
function Modules.ShortName(title)
	title = title:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	local prefix = ns.L.MODULE_PREFIX
	if title:sub(1, #prefix) == prefix then
		return title:sub(#prefix + 1)
	end
	return title
end

-- Whether the array of folder names `dependencies` contains `coreName`. Pure.
function Modules.DependsOn(dependencies, coreName)
	for _, dependency in ipairs(dependencies) do
		if dependency == coreName then
			return true
		end
	end
	return false
end

-- { { folder, name, notes }, ... } sorted by name, built on first use and cached.
function Modules.List()
	if list then
		return list
	end
	list, byFolder = {}, {}
	for i = 1, C_AddOns.GetNumAddOns() do
		if Modules.DependsOn({ C_AddOns.GetAddOnDependencies(i) }, ADDON_NAME) then
			local folder = C_AddOns.GetAddOnName(i)
			local title = C_AddOns.GetAddOnMetadata(i, "Title")
			if not title or title == "" then
				title = folder
			end
			local entry = {
				folder = folder,
				name = Modules.ShortName(title),
				notes = C_AddOns.GetAddOnMetadata(i, "Notes") or "",
			}
			list[#list + 1] = entry
			byFolder[folder] = entry
		end
	end
	table.sort(list, function(a, b)
		return a.name < b.name
	end)
	return list
end

function Modules.Find(folder)
	Modules.List()
	return byFolder[folder]
end

function Modules.IsLoaded(folder)
	local _, loaded = C_AddOns.IsAddOnLoaded(folder)
	return loaded and true or false
end

-- The enable state is per character; the GUID is the key, the name the fallback when it is secret.
local function Character()
	local guid = UnitGUID("player")
	if issecretvalue(guid) then
		return UnitName("player")
	end
	return guid
end

function Modules.IsEnabled(folder)
	return C_AddOns.GetAddOnEnableState(folder, Character()) ~= Enum.AddOnEnableState.None
end

-- For all characters (no character argument).
function Modules.SetEnabled(folder, enabled)
	if enabled then
		C_AddOns.EnableAddOn(folder)
	else
		C_AddOns.DisableAddOn(folder)
	end
	-- Unsaved changes are thrown away when the AddOns list closes without saving (AddonList.lua:674-683).
	C_AddOns.SaveAddOns()
	ns.log("TOGGLE", folder, enabled)
end

-- Whether some module's enabled state differs from whether it is loaded, so a reload would change it.
function Modules.HasPendingChange()
	for _, entry in ipairs(Modules.List()) do
		if Modules.IsEnabled(entry.folder) ~= Modules.IsLoaded(entry.folder) then
			return true
		end
	end
	return false
end

EventUtil.RegisterOnceFrameEventAndCallback("PLAYER_LOGIN", function()
	if not ns.dev.enabled then
		return
	end
	for _, entry in ipairs(Modules.List()) do
		ns.log("MODULES", entry.folder, entry.name, Modules.IsLoaded(entry.folder), Modules.IsEnabled(entry.folder))
	end
	ns.log("MODULES", "GUID secret", issecretvalue(UnitGUID("player")))
end)
