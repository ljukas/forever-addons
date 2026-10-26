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

-- Frames created by Blizzard XML.

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

---@class MapCanvasDataProviderMixin
---@field GetMap fun(self: MapCanvasDataProviderMixin): MapCanvasFrame

---@class MapCanvasPinMixin : Frame
---@field SetPosition fun(self: MapCanvasPinMixin, normalizedX: number, normalizedY: number, insetIndex: number?)
---@field SetScalingLimits fun(self: MapCanvasPinMixin, scaleFactor: number, startScale: number?, endScale: number?)
---@field UseFrameLevelType fun(self: MapCanvasPinMixin, pinFrameLevelType: string, index: number?)

-- Blizzard_UnitFrame/Mainline/TargetFrame.xml: TargetFrame and FocusFrame (TargetFrameTemplate).
-- Only the members our addons use.

---@class StatusBarOverlaySegment : Frame
---@field FillMask MaskTexture

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
