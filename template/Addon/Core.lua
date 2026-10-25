local ADDON_NAME, ns = ...

-- Dev-only logging: lands in ForeverDev's on-disk log (scripts/devlog.sh) when
-- ForeverDev is loaded, and is a no-op for players.
function ns.log(...)
	if ForeverDev_Log then
		ForeverDev_Log(ADDON_NAME, ...)
	end
end

local defaults = {}

EventUtil.ContinueOnAddOnLoaded(ADDON_NAME, function()
	__ADDON__DB = __ADDON__DB or CopyTable(defaults)
	ns.db = __ADDON__DB
	ns.log("loaded")
end)
