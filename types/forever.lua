---@meta
-- LuaLS annotations for Forever-only APIs that Ketho's Mainline-based annotations
-- (.cache/wow-api) don't cover. Confirm each signature against the generated docs in
-- .cache/wow-ui-source/Interface/AddOns/Blizzard_APIDocumentationGenerated first.

-- C_SkillInfo: Blizzard_APIDocumentationGenerated/SkillInfoDocumentation.lua

---@class SkillLineAttributes
---@field skillID number
---@field name string
---@field isHeader boolean
---@field isCollapsed boolean
---@field rank number
---@field tempPoints number
---@field modifier number
---@field maxRank number
---@field isAbandonable boolean
---@field stepCost number
---@field rankCost number
---@field minLevel number
---@field costType number
---@field parentSkillLineID number
---@field skillLineCategoryID number
---@field description string

C_SkillInfo = {}

---@return number numSkillLines
function C_SkillInfo.GetNumSkillLines() end

---@param index number
---@return SkillLineAttributes?
function C_SkillInfo.GetSkillLineInfo(index) end

---@param ID number
---@return SkillLineAttributes?
function C_SkillInfo.GetSkillLineInfoByID(ID) end

-- Global strings used by Forever's UI source (they live in the client, not the source).

-- "Requires %s (%d)"; Blizzard_TrainerUI formats it with a skill name and rank.
---@type string
TRAINER_REQ_SKILL_RANK = ""

-- "%d sec"; Blizzard_AuctionHouseUI formats it with whole seconds.
---@type string
INT_SPELL_DURATION_SEC = ""

-- "Level %d"; Blizzard_StableUI/Camelot/Blizzard_StableUI formats it with a pet's level.
---@type string
UNIT_LEVEL_TEMPLATE = ""

-- Blizzard_StatusTrackingBar/Mainline/ExpBarOverrides formats it with the
-- player's XP, the XP the level needs and the percent, as the experience bar tooltip's title.
---@type string
XP_TEXT = ""

-- Frames created by Blizzard XML.

-- The frame the 3D world renders in, created by the client; the mouse focus while the cursor is over
-- the world. Used by Blizzard_ActionStatus/Mainline/ActionStatus.lua.
---@type Frame
WorldFrame = {}

-- Blizzard_WorldMap/Blizzard_WorldMap.xml, a MapCanvasFrameTemplate.
---@class WorldMapFrame : MapCanvasFrame
---@field AddDataProvider fun(self: WorldMapFrame, dataProvider: table)
---@field AddOverlayFrame fun(self: WorldMapFrame, templateName: string, templateType: string, anchorPoint: string?, relativeFrame: Frame?, relativePoint: string?, offsetX: number?, offsetY: number?): Frame
---@field GetCanvasContainer fun(self: WorldMapFrame): Frame
---@field WorldMapTrackingPinButton Button?
WorldMapFrame = {}

-- Blizzard map canvas mixins (Blizzard_MapCanvas), which Ketho's annotations leave
-- untyped. Only the members our addons use.

---@class MapCanvasFrame : Frame
---@field GetMapID fun(self: MapCanvasFrame): number
---@field AcquirePin fun(self: MapCanvasFrame, pinTemplate: string, ...): MapCanvasPinMixin
---@field RemoveAllPinsByTemplate fun(self: MapCanvasFrame, pinTemplate: string)
---@field EnumeratePinsByTemplate fun(self: MapCanvasFrame, pinTemplate: string): fun(): Frame
---@field GetCanvas fun(self: MapCanvasFrame): Frame
---@field GetCanvasScale fun(self: MapCanvasFrame): number
---@field GetGlobalPinScale fun(self: MapCanvasFrame): number
---@field HasZoomLevels fun(self: MapCanvasFrame): boolean
---@field GetScaleForMinZoom fun(self: MapCanvasFrame): number
---@field GetScaleForMaxZoom fun(self: MapCanvasFrame): number

---@class MapCanvasDataProviderMixin
---@field GetMap fun(self: MapCanvasDataProviderMixin): MapCanvasFrame

---@class MapCanvasPinMixin : Frame
---@field SetPosition fun(self: MapCanvasPinMixin, normalizedX: number, normalizedY: number, insetIndex: number?)
---@field SetScalingLimits fun(self: MapCanvasPinMixin, scaleFactor: number, startScale: number?, endScale: number?)
---@field UseFrameLevelType fun(self: MapCanvasPinMixin, pinFrameLevelType: string, index: number?)
---@field ApplyCurrentScale fun(self: MapCanvasPinMixin)

-- Blizzard_UnitFrame/Mainline/TargetFrame.xml: TargetFrame and FocusFrame (TargetFrameTemplate).
-- Only the members our addons use.

---@class StatusBarOverlaySegment : Frame
---@field FillMask MaskTexture
---@field fillAtlas string? the unit frame's segment atlas, from its *BarSegmentTemplate KeyValue

---@class TargetFrameHealthBar : StatusBar
---@field MyHealPredictionBar StatusBarOverlaySegment
---@field OtherHealPredictionBar StatusBarOverlaySegment

---@class TargetFrameHealthBarsContainer : Frame
---@field HealthBar TargetFrameHealthBar
---@field HealthBarMask MaskTexture

---@class TargetFrameContentMain : Frame
---@field HealthBarsContainer TargetFrameHealthBarsContainer

---@class TargetFrameContent : Frame
---@field TargetFrameContentMain TargetFrameContentMain

---@class TargetFrame : Button
---@field TargetFrameContent TargetFrameContent
---@field UpdateHealthBarVisuals fun(self: TargetFrame)
TargetFrame = {}

---@class FocusFrame : TargetFrame
FocusFrame = {}

-- Blizzard_UnitFrame/Mainline/PlayerFrame.xml and PlayerFrame.lua: the player frame's health bar
-- has the target frame's layout under PlayerFrameContent.PlayerFrameContentMain. unit is
-- "vehicle" while the player is in one (PlayerFrame_ToVehicleArt).

---@class PlayerFrame : Button
---@field unit string
PlayerFrame = {}

---@return TargetFrameHealthBarsContainer
function PlayerFrame_GetHealthBarContainer() end

-- Overridden by Camelot/PlayerFrame.lua; hooked by name.
function PlayerFrame_UpdateHealthBarVisuals() end

-- Minimap: Blizzard_APIDocumentationGenerated/MinimapFrameAPIDocumentation.lua. Ketho's
-- Retail-based annotations lack these two (and list SetBlipTexture, which Forever doesn't have).

---Moves the minimap's mouseover to a point in screen coordinates (needs the soft cursor on).
---@param pointX number
---@param pointY number
function Minimap:UpdateMouseoverAtPoint(pointX, pointY) end

---@param usingSoftCursor boolean
function Minimap:SetUsingSoftCursor(usingSoftCursor) end

---@param scale number
function Minimap:SetIconScale(scale) end

-- Blizzard_Minimap/Mainline/Minimap.xml: the minimap's parent and the frame its buttons sit in, and
-- the Edit Mode minimap system (EditModeMinimapSystemMixin,
-- Blizzard_EditMode/Shared/EditModeSystemTemplates.lua). Only the members our addons use.

---@class MinimapCluster : Frame
---@field GetSettingValue fun(self: MinimapCluster, setting: number, useRawValue: boolean?): number
MinimapCluster = {}

-- Blizzard_APIDocumentationGenerated/EditModeManagerConstantsDocumentation.lua. Ketho's
-- annotations stop at Size.
---@diagnostic disable-next-line: inject-field
Enum.EditModeMinimapSetting.IconScale = 3

-- Blizzard_APIDocumentationGenerated/TooltipInfoSharedDocumentation.lua. Ketho's annotations stop
-- before the unit line types.
---@diagnostic disable-next-line: inject-field
Enum.TooltipDataLineType.UnitLevel = 47

-- Not Blizzard's: an addon convention. An addon that reshapes the minimap defines it to return the
-- shape ("ROUND", "SQUARE", "CORNER-TOPLEFT", ...); nil when no addon does.
---@type (fun(): string)?
GetMinimapShape = nil

-- Frames from Forever's own UI source (Blizzard_UnitFrame/Camelot/).

-- Combo points around the target portrait (Camelot/ComboFrame.xml, ComboFrame.lua).
---@type Frame
ComboFrame = nil

-- PetActionBar: the pet bar frame, Blizzard_ActionBar/Mainline/PetActionBar.xml.
---@type Frame
PetActionBar = {}

-- ActionBarButtonRangeCheckFrame: routes ACTION_RANGE_CHECK_UPDATE to action buttons,
-- Blizzard_ActionBar/Shared/ActionButtonComponentTemplate.xml and ActionButton.lua.
---@class ActionBarButtonRangeCheckFrame : Frame
---@field actions table<number, table<Button, Button>>
---@field RegisterFrame fun(self: ActionBarButtonRangeCheckFrame, action: number, frame: Button)
---@field UnregisterFrame fun(self: ActionBarButtonRangeCheckFrame, action: number, frame: Button)
ActionBarButtonRangeCheckFrame = {}

-- GameTooltipTemplate's unit health bar: Blizzard_GameTooltip/Mainline/GameTooltip.xml
-- (<StatusBar parentKey="StatusBar" name="$parentStatusBar" ...>).

---@class GameTooltip
---@field StatusBar StatusBar

-- Blizzard_Professions/Camelot/Blizzard_ProfessionsFrame.xml (load-on-demand). Only the members
-- our addons use: the crafting page's recipe list and schematic form
-- (Blizzard_ProfessionsTemplates/Blizzard_ProfessionsRecipeSchematicForm.lua).

---@class ProfessionsRecipeSchematicForm : Frame
---@field Reagents Frame
---@field OptionalReagents Frame
---@field Init fun(self: ProfessionsRecipeSchematicForm, recipeInfo: table, isRecraftOverride: boolean?)
---@field GetRecipeInfo fun(self: ProfessionsRecipeSchematicForm): table?

---@class ProfessionsCraftingPage : Frame
---@field SchematicForm ProfessionsRecipeSchematicForm
---@field RecipeList Frame|{ ScrollBox: table }

---@class ProfessionsFrame : Frame
---@field CraftingPage ProfessionsCraftingPage
---@type ProfessionsFrame?
ProfessionsFrame = nil
