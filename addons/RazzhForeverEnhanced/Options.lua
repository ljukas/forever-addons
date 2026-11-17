local ADDON_NAME, ns = ...

-- Options > AddOns > Razzh Forever Enhanced: a checkbox per module that enables or disables that
-- addon (applied by the Reload UI button), and each module's own page as a subcategory
-- (RazzhForeverEnhanced.RegisterOptions). ns.log tags: OPTIONS, and TOGGLE (from ns.Modules.SetEnabled).
local L = ns.L

-- Built when this file loads, not on an event, so modules (which load after the core) can call
-- RegisterOptions from their own load handlers.
local category, layout = Settings.RegisterVerticalLayoutCategory(L.TITLE)
category:SetShouldSortAlphabetically(true)

-- Global strings exist only in the running game.
local NEEDS_RELOAD = _G["VIDEO_OPTIONS_NEED_UIRELOAD"] or L.NEEDS_RELOAD

layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(L.MODULES))

local modules = ns.Modules.List()
if #modules == 0 then
	-- Blizzard has no plain-text row an addon page can use, so the line is a section header.
	layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(L.NO_MODULES))
else
	local variables = {}
	for _, module in ipairs(modules) do
		local folder = module.folder
		local variable = "RAZZHFOREVERENHANCED_MODULE_" .. folder:upper()
		variables[#variables + 1] = variable
		-- No default and no commit flag: Defaults must not switch every module back on or reload the UI.
		local setting = Settings.RegisterProxySetting(
			category,
			variable,
			Settings.VarType.Boolean,
			module.name,
			nil,
			function()
				return ns.Modules.IsEnabled(folder)
			end,
			function(value)
				ns.Modules.SetEnabled(folder, value)
			end
		)
		local tooltip = module.notes == "" and NEEDS_RELOAD or module.notes .. "\n\n" .. NEEDS_RELOAD
		Settings.CreateCheckbox(category, setting, tooltip)
	end

	-- ReloadUI only works when called directly inside the click, so the button calls it itself.
	local reload = CreateSettingsButtonInitializer("", _G["RELOADUI"], ReloadUI, L.RELOAD_TOOLTIP, true)
	reload:AddModifyPredicate(ns.Modules.HasPendingChange)
	-- Re-evaluate the button whenever a box changes.
	for _, variable in ipairs(variables) do
		reload:AddEvaluateStateCVar(variable)
	end
	layout:AddInitializer(reload)
end

Settings.RegisterAddOnCategory(category)

-- [addonName] = { category, layout }
local pages = {}

-- The module's own options page, a subcategory of the core's, created on the first call.
function RazzhForeverEnhanced.RegisterOptions(addonName)
	if type(addonName) ~= "string" then
		error(ADDON_NAME .. ".RegisterOptions: addonName must be a string, got " .. type(addonName), 2)
	end
	local module = ns.Modules.Find(addonName)
	if not module then
		error(
			ADDON_NAME
				.. ".RegisterOptions: "
				.. addonName
				.. " is not a module (its TOC must list "
				.. ADDON_NAME
				.. " in ## Dependencies)",
			2
		)
	end
	local page = pages[addonName]
	if not page then
		local subcategory, subLayout = Settings.RegisterVerticalLayoutSubcategory(category, module.name)
		page = { subcategory, subLayout }
		pages[addonName] = page
		ns.log("OPTIONS", "page", addonName)
	end
	return page[1], page[2]
end

-- Opens Options at the module's page, or at the core's when addonName is nil or has no page.
function RazzhForeverEnhanced.OpenOptions(addonName)
	if addonName ~= nil and type(addonName) ~= "string" then
		error(ADDON_NAME .. ".OpenOptions: addonName must be nil or a string, got " .. type(addonName), 2)
	end
	if InCombatLockdown() then
		UIErrorsFrame:AddMessage(_G["ERR_NOT_IN_COMBAT"], 1.0, 0.1, 0.1, 1.0)
		ns.log("OPTIONS", "combat")
		return
	end
	local page = addonName and pages[addonName]
	Settings.OpenToCategory((page and page[1] or category):GetID())
	ns.log("OPTIONS", "open", addonName or "root")
end

-- Named by the TOC's ## AddonCompartmentFunc.
function RazzhForeverEnhanced_OnAddonCompartmentClick()
	RazzhForeverEnhanced.OpenOptions()
end
