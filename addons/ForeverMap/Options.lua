local ADDON_NAME, ns = ...

-- ForeverMapDB.settings and their defaults. A value not saved yet reads as its default, so code
-- that runs before the options panel registers its settings never sees nil.
ns.Options = {}

ns.Options.DEFAULTS = {
	showNodeIcons = true,
	nodeIconSize = 9, -- an estimate until launch: small enough to leave the up/down arrows visible
}

function ns.Options.Get(key)
	local value = ns.db and ns.db.settings[key]
	if value == nil then
		return ns.Options.DEFAULTS[key]
	end
	return value
end
