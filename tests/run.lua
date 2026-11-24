-- Run with lua5.1. Uses the installed FlareUI's actual visibility/update/layout
-- functions with mocked game widgets; no WoW client or FlareUI files are changed.
-- Usage: lua5.1 tests/run.lua /path/to/FlareUI
local root = (arg[0]:match("^(.*)/tests/[^/]+$") or ".") .. "/"
local flarePath = assert(arg[1] or os.getenv("FLAREUI_PATH"), "Pass the FlareUI source folder as the first argument")
local file = assert(io.open(flarePath .. "/Modules/UnitFrames.lua", "r"))
local native = file:read("*a"):gsub("\r\n", "\n")
file:close()

local function Section(first, last)
    local start = assert(native:find(first, 1, true), first)
    local finish = assert(native:find(last, start + #first, true), last)
    return native:sub(start, finish - 1)
end

local passed = 0
local function Check(value, message)
    assert(value, message)
    passed = passed + 1
end

local function Widget()
    local w = { shown = false, points = {}, pointOrder = {} }
    function w:IsShown() return self.shown end
    function w:Show() self.shown = true end
    function w:Hide() self.shown = false end
    function w:ClearAllPoints() self.points = {}; self.pointOrder = {} end
    function w:SetPoint(point, ...)
        if not self.points[point] then table.insert(self.pointOrder, point) end
        self.points[point] = { ... }
    end
    function w:GetNumPoints() return #self.pointOrder end
    function w:GetPoint(index)
        local bottom = self.points.BOTTOMLEFT or self.points.BOTTOMRIGHT
        if bottom and bottom[1].owner and type(bottom[1].owner.value) == "table" then
            error("Plugin tried to read its restricted layout anchors")
        end
        local point = self.pointOrder[index]
        return point, unpack(self.points[point])
    end
    function w:SetHeight(height) self.height = height end
    function w:GetHeight()
        local point = self.points.BOTTOMLEFT
        if point and point[1].owner and type(point[1].owner.value) == "table" then return point[1].owner.value end
        return self.height or 12
    end
    function w:GetWidth()
        local point = self.points.BOTTOMLEFT
        if point and point[1].owner and type(point[1].owner.value) == "table" then return point[1].owner.value end
        return self.width or 242
    end
    function w:SetMinMaxValues(low, high) self.low, self.high = low, high end
    function w:SetValue(value) self.value = value end
    function w:SetOrientation(value) self.orientation = value end
    function w:SetReverseFill(value) self.reverseFill = value end
    function w:SetStatusBarTexture(value)
        self.fill = Widget()
        self.fill.owner = self
        self.fill.asset = value
    end
    function w:GetStatusBarTexture() return self.fill end
    function w:SetStatusBarColor(...) self.color = { ... } end
    -- Simulate the client's privileged setter accepting a restricted curve
    -- result. Only the mock engine reads engineAlpha; the addon cannot.
    function w:SetAlpha(alpha) self.alpha = type(alpha) == "table" and alpha.engineAlpha or alpha end
    function w:RegisterEvent(event) self.registered[event] = true end
    function w:UnregisterEvent(event) self.registered[event] = nil end
    function w:SetScript(script, callback) self[script] = callback end
    return w
end

-- Privileged mock layout engine: resolve the fill's edge without exposing
-- that geometry to addon Lua. Return just the space reserved for shift mana.
local function ReservedSpace(player)
    local point = player.Power:IsShown() and player.Power.points.BOTTOMLEFT
        or player.Health.points.BOTTOMRIGHT
    local relative, y = point[1], point[4]
    if relative.owner then
        local proxy = relative.owner
        local value = type(proxy.value) == "table" and proxy.value.engineAlpha or proxy.value
        return proxy.height * (value - proxy.low) / (proxy.high - proxy.low) + y
    end
    if relative == player.ShiftMana then
        return (point[2]:find("TOP", 1, true) and player.ShiftMana.height or 0) + y
    end
    return y - 4
end

local nativeFsrShow = Section('holder:SetScript("OnShow", function(self)\n        local height = bar:GetHeight()',
    'holder:SetScript("OnUpdate", MoveFsrSpark)')
local function CheckFsrShow(env, bar)
    local holder = Widget()
    holder.Spark = { SetSize = function(_, width, height)
        assert(type(width) == "number" and type(height) == "number", "FSR sizes must be readable")
    end }
    local chunk = assert(loadstring("local bar, holder = ...;\n" .. nativeFsrShow, "Native FSR OnShow"))
    setfenv(chunk, env)(bar, holder)
    holder:OnShow()
end

local function Setup(class, saved, unsupported)
    local env = setmetatable({}, { __index = _G })
    env._G = env
    env.current, env.maximum, env.powerType = 490, 490, 3
    env.class = class or "DRUID"
    env.db = { shiftMana = true, powerHeight = 12, width = 250 }
    env.FlareUIDruidDB = saved
    env.Enum = { PowerType = { Mana = 0 } }
    env.SlashCmdList = {}
    env.messages = {}
    env.print = function(message) table.insert(env.messages, message) end
    env.UnitClass = function() return "Druid", env.class end
    env.UnitPower = function(unit, power)
        assert(unit == "player" and power == 0, "Must request mana explicitly")
        return env.current
    end
    env.UnitPowerMax = function() return env.maximum end
    env.UnitPowerType = function() return env.powerType end
    env.UnitIsDeadOrGhost = function() return false end
    env.canaccessvalue = function(value)
        return value == nil or (value ~= env.secret and value ~= env.secretAlpha)
    end
    env.hooksecurefunc = function(object, key, callback)
        local original = object[key]
        object[key] = function(...)
            local result = original(...)
            callback(...)
            return result
        end
    end
    env.Enum.LuaCurveType = { Step = 1 }
    env.C_CurveUtil = { CreateCurve = function()
        env.curvesCreated = (env.curvesCreated or 0) + 1
        return {
            points = {},
            SetType = function(curve, value) curve.curveType = value end,
            AddPoint = function(curve, x, y) table.insert(curve.points, { x, y }) end,
        }
    end }
    env.secretAlpha = setmetatable({}, {
        __tostring = function() error("Restricted alpha formatted") end,
        __lt = function() error("Restricted alpha compared") end,
        __le = function() error("Restricted alpha compared") end,
    })
    env.UnitPowerPercent = function(unit, manaType, unmodified, curve)
        assert(unit == "player" and manaType == 0 and unmodified == false)
        assert(curve.curveType == 1 and #curve.points == 2)
        assert(curve.points[1][1] == 0 and curve.points[1][2] == 1)
        assert(curve.points[2][1] == 1 and curve.points[2][2] == 0)
        -- The mock engine knows the real percentage, independently of Lua's
        -- restricted current mana object.
        env.secretAlpha.engineAlpha = (env.enginePercent or 1) < 1 and 1 or 0
        return env.secretAlpha
    end
    env.GetUnitDb = function() return env.db end
    env.IsComboShown = function() return false end
    env.PortraitSpace = function() return 0 end
    env.UpdatePortrait = function() end
    env.UpdateFsrSpark = function() env.sparkUpdates = (env.sparkUpdates or 0) + 1 end
    env.CreateFrame = function(kind)
        local w = Widget()
        w.registered = {}
        if kind == "Frame" then env.events = w end
        return w
    end
    env.FlareUI = {
        UnitFrames = {
            Kit = { GetDb = function() return { units = { player = env.db } } end, INSET = 4 },
            LayoutMirrored = function() return false end,
            PlateSlotText = function() end,
            PlateDropChanged = function() end,
            FillSlots = function() end,
            PowerSource = function() return {} end,
            TextSlots = function() return {} end,
        },
        EditPreviewing = function() return env.preview end,
        SetBarValue = function(bar, value) bar:SetValue(value) end,
        MANA_BLUE = { 0, 0, 1 },
        PowerColor = function() return 0, 0, 1 end,
    }
    local p = { fuiUnit = "player", ShiftMana = Widget(), ShiftManaSeparator = Widget(),
        ShiftManaText = Widget(), ShiftManaTextLeft = Widget(), ShiftManaTextMid = Widget(),
        Health = Widget(), Power = Widget(), Separator = Widget() }
    env.FlareUI_UF_Player = p
    local code = "local ns = FlareUI; local UF = ns.UnitFrames; local INSET = 4; local SEPARATOR_HEIGHT = 8;\n"
        .. Section("UF.SHIFT_MANA_HEIGHT = 5", "-- Forever Style with Mana on Shapeshift:")
        .. Section("local function LayoutBars(f)", "-- the bar, its line and its texts")
        .. Section("function UF.UpdateShiftMana(f)", "-- Shows the strip with the right number of segments")
    setfenv(assert(loadstring(code, "FlareUI native functions")), env)()
    if unsupported then env.FlareUI.UnitFrames.ShiftManaShown = nil end
    env.original = env.FlareUI.UnitFrames.ShiftManaShown
    local plugin = {}
    setfenv(assert(loadfile(root .. "FlareUI_Druid/Layout.lua")), env)("FlareUI_Druid", plugin)
    setfenv(assert(loadfile(root .. "FlareUI_Druid/Core.lua")), env)("FlareUI_Druid", plugin)
    env.events:OnEvent("ADDON_LOADED", "SomeOtherAddon")
    Check(env.FlareUI.UnitFrames.ShiftManaShown == env.original, "Ignore unrelated addon load")
    env.events:OnEvent("ADDON_LOADED", "FlareUI_Druid")
    function env:Update() self.FlareUI.UnitFrames.UpdateShiftMana(self.FlareUI_UF_Player) end
    function env:Shown() return self.FlareUI.UnitFrames.ShiftManaShown(self.FlareUI_UF_Player) end
    function env:Command(command) self.SlashCmdList.FLAREUIDRUID(command) end
    return env, p
end

local e, p = Setup()
Check(e.FlareUIDruidDB.hideFullMana == true, "Enabled by default")
Check(not e:Shown() and not p.ShiftMana:IsShown(), "Full mana hidden at initialization")
Check(not p.ShiftManaSeparator:IsShown(), "No orphaned separator")
e.current = 489
e:Update()
Check(p.ShiftMana:IsShown() and p.ShiftManaSeparator:IsShown(), "One mana missing restores strip and separator")
Check(p.ShiftMana.value == 489 and p.ShiftMana.high == 490, "Native update feeds real mana")
Check(p.Power.points.BOTTOMLEFT[4] == 16, "Power bar makes room for mana")
e.current = 490
e:Update()
Check(not p.ShiftMana:IsShown() and not p.ShiftManaSeparator:IsShown(), "Regeneration to full hides strip and separator")
Check(p.Power.points.BOTTOMLEFT[4] == 4, "Native layout reclaims the space")
e.current = 0
e:Update()
Check(p.ShiftMana:IsShown(), "Empty mana remains visible")
e.current, e.maximum = 490, 500
e:Update()
Check(p.ShiftMana:IsShown(), "Maximum mana increase reveals bar")
e.maximum = 490
e:Update()
Check(not p.ShiftMana:IsShown(), "Maximum mana decrease to current hides bar")
e.powerType = 0
e.current = 100
e:Update()
Check(not p.ShiftMana:IsShown(), "Caster form follows FlareUI")
e.powerType = 3
e:Update()
Check(p.ShiftMana:IsShown(), "Non-mana form restores bar when below full")
e.current = 490
e.preview = true
e:Update()
Check(p.ShiftMana:IsShown(), "Edit Mode preview remains visible at full")
e.preview = false
e.FlareUI.UnitFrames.shiftTest = true
Check(e:Shown(), "FlareUI druidbar test preserved")
e.FlareUI.UnitFrames.shiftTest = false
p.fuiSample = true
Check(e:Shown(), "Sample frames preserved")
p.fuiSample = nil
e.db.shiftMana = false
Check(not e:Shown(), "FlareUI's disabled option respected")
e.db.shiftMana = true
e:Command(" OFF ")
Check(p.ShiftMana:IsShown() and e.FlareUIDruidDB.hideFullMana == false, "Off restores native behavior immediately")
e:Command("on")
Check(not p.ShiftMana:IsShown(), "On hides immediately")
e:Command("status")
e:Command("unknown")
Check(e.messages[#e.messages]:find("/fuidruid on", 1, true), "Unknown command prints help")
e.current = 491
Check(not e:Shown(), "Over-cap values count as full")
e.maximum = 0
Check(e:Shown(), "Zero maximum retains native decision")
e.maximum = -1
Check(e:Shown(), "Invalid negative maximum retains native decision")
e.maximum, e.current = 490, nil
Check(e:Shown(), "Missing current mana retains native decision")
e.current = "490"
Check(e:Shown(), "Non-numeric mana retains native decision")
e.secret = setmetatable({}, { __lt = function() error("Secret compared") end,
    __le = function() error("Secret compared") end })
e.current = e.secret
Check(e:Shown(), "Restricted current mana is never compared")
e:Command("debug")
Check(e.messages[#e.messages - 2]:find("mana=restricted/490", 1, true), "Diagnostics explain restricted mana")
e.current, e.maximum = 490, e.secret
Check(e:Shown(), "Restricted maximum mana is never compared")
e.maximum = 490
e.powerType = 1
Check(not e:Shown(), "Bear/rage form uses mana, not rage")
e.powerType = 3
Check(not e:Shown(), "Cat/energy form uses mana, not energy")
e.powerType = 0
Check(not e:Shown(), "Mana-using forms keep the normal mana bar")

-- The actual native LayoutBars branches into the Forever plate renderer.
-- Mock only the art renderer to check that it sees the same wrapped predicate.
e.powerType = 3
p.Portrait = {}
local secondSlot
e.FlareUI.UFRing = {
    Plate = function() return true end,
    TwoSlots = function() return true end,
    LayoutPlate = function(frame)
        secondSlot = e.FlareUI.UnitFrames.ShiftManaShown(frame)
        if secondSlot then frame.ShiftMana:Show() else frame.ShiftMana:Hide() end
    end,
    Layout = function() end,
}
p.ShiftMana:Show() -- Force a visibility transition to exercise native layout.
e:Update()
Check(secondSlot == false and not p.ShiftMana:IsShown(), "Forever layout sees hidden full-mana decision")
e.current = 489
e:Update()
Check(secondSlot == true and p.ShiftMana:IsShown(), "Forever layout sees below-full decision")
e.FlareUI.UFRing.TwoSlots = function() return false end
Check(not e:Shown(), "Missing Forever art stays hidden")

local off, offPlayer = Setup("DRUID", { hideFullMana = false, future = 42 })
Check(off.FlareUIDruidDB.hideFullMana == false and offPlayer.ShiftMana:IsShown(), "Saved off setting survives reload")
Check(off.FlareUIDruidDB.future == 42, "Unrelated future settings preserved")
for _, class in ipairs({ "WARRIOR", "ROGUE", "MAGE" }) do
    local other = Setup(class)
    Check(other.FlareUI.UnitFrames.ShiftManaShown == other.original, class .. " is not hooked")
    other:Command("status")
    Check(other.messages[#other.messages] == "|cffff7d0aFlareUI Druid:|r Only affects druids.", "Class status explained")
end
local bad = Setup("DRUID", "invalid")
Check(type(bad.FlareUIDruidDB) == "table" and bad.FlareUIDruidDB.hideFullMana, "Malformed saved data repaired")
local old = Setup("DRUID", nil, true)
Check(old.FlareUI.UnitFrames.ShiftManaShown == nil, "Unsupported integration left alone")
Check(old.messages[1]:find("unsupported", 1, true), "Unsupported integration reports a message")
Check(not old.events.registered.PLAYER_ENTERING_WORLD, "Unsupported integration does not register updates")

-- Reproduce the user's live report: restricted current mana, readable max,
-- bear form, no preview. Native visibility must stay shown, while the engine
-- drives the strip, separator, and all mana text opacity without Lua comparisons.
local restricted, rp = Setup()
restricted.secret = {}
restricted.current = restricted.secret
restricted.maximum = 524
restricted.powerType = 1
restricted.enginePercent = 1
for _, region in ipairs({ rp.Power, rp.Health }) do
    region.GetNumPoints = function() error("Restricted GetNumPoints result cannot be used") end
    region.GetPoint = function() error("Restricted GetPoint result cannot be used") end
end
rp.Power.GetWidth = function() return restricted.secret end
rp.Power.GetHeight = function() return restricted.secret end
rp.ShiftMana.GetWidth = function() return restricted.secret end
rp.ShiftMana.GetHeight = function() return restricted.secret end
restricted:Update()
restricted.UpdateFsrSpark = function()
    CheckFsrShow(restricted, rp.Power)
    CheckFsrShow(restricted, rp.ShiftMana)
end
Check(rp.ShiftMana:IsShown() and rp.ShiftMana.alpha == 0, "Restricted full mana is visually hidden")
Check(ReservedSpace(rp) == 0, "Restricted full mana reclaims all reserved space")
Check(rp.Power:GetWidth() == 242 and rp.Power:GetHeight() == 12, "Power spark getters retain constant dimensions")
restricted.db.portrait = "class"
rp.Portrait = {}
restricted:Update()
Check(rp.Power:GetWidth() == 206, "Power width derives the portrait inset from settings")
restricted.db.portrait = "none"
rp.Portrait = nil
restricted:Update()
Check(rp.ShiftManaSeparator.alpha == 0, "Restricted full mana hides separator")
Check(rp.ShiftManaText.alpha == 0 and rp.ShiftManaTextLeft.alpha == 0 and rp.ShiftManaTextMid.alpha == 0,
    "Restricted full mana hides all text slots")
restricted.enginePercent = 0.9999
restricted:Update()
Check(rp.ShiftMana.alpha == 1 and rp.ShiftManaSeparator.alpha == 1, "Any missing mana restores opacity")
Check(ReservedSpace(rp) == 12, "Missing mana reserves exactly one mana-bar height")
Check(rp.ShiftManaText.alpha == 1 and rp.ShiftManaTextLeft.alpha == 1 and rp.ShiftManaTextMid.alpha == 1,
    "Missing mana restores all text slots")
Check(restricted.curvesCreated == 1, "Curve is reused on repeated mana updates")
restricted.enginePercent = 1
restricted:Update()
restricted:Command("off")
Check(rp.ShiftMana.alpha == 1 and rp.ShiftManaSeparator.alpha == 1, "Off restores opacity immediately")
CheckFsrShow(restricted, rp.Power)
CheckFsrShow(restricted, rp.ShiftMana)
Check(true, "Native FSR spark OnShow works while plugin layout is inactive")
restricted.db.width = 260
Check(rp.Power:GetWidth() == 252, "Off-state size getters follow settings changes")
restricted.db.width = 250
Check(rp.Power.points.BOTTOMLEFT[1] == rp.ShiftMana and ReservedSpace(rp) == 12, "Off restores native anchor relationships and space")
restricted:Command("on")
Check(rp.ShiftMana.alpha == 0, "On reapplies restricted-mana opacity immediately")
Check(ReservedSpace(rp) == 0, "On reapplies collapsed space immediately")
restricted:Command("debug")
Check(restricted.messages[#restricted.messages] == "|cffff7d0aFlareUI Druid:|r layout=fill anchor", "Diagnostics confirm fill-anchor layout")
restricted.preview = true
restricted:Update()
Check(rp.ShiftMana.alpha == 1, "Restricted full mana preserves Edit Mode preview")
Check(rp.Power.points.BOTTOMLEFT[1] == rp.ShiftMana and ReservedSpace(rp) == 12, "Preview restores native layout")
restricted.preview = false
restricted.FlareUI.UnitFrames.shiftTest = true
restricted:Update()
Check(rp.ShiftMana.alpha == 1, "Restricted full mana preserves druidbar test")
restricted.FlareUI.UnitFrames.shiftTest = false
restricted:Update()
restricted.current = 523
restricted:Update()
Check(rp.ShiftMana.alpha == 1, "Readable mana clears previous curve opacity")
Check(rp.Power.points.BOTTOMLEFT[1] == rp.ShiftMana, "Readable mana restores native anchor relationships")
restricted.current = restricted.secret
restricted.powerType = 0
restricted:Update()
Check(not rp.ShiftMana:IsShown() and ReservedSpace(rp) == 0, "Caster form restores native no-strip layout")
restricted.powerType = 1
restricted:Update()
Check(ReservedSpace(rp) == 0, "Returning to bear at full mana collapses the slot")
restricted.db.powerHeight = 0
rp.ShiftMana:Hide() -- Force native layout to apply the changed Power Height.
restricted:Update()
Check(not rp.Power:IsShown() and ReservedSpace(rp) == 0, "Power-off layout expands health to the bottom at full mana")
restricted.enginePercent = 0.8
restricted:Update()
Check(ReservedSpace(rp) == 5, "Power-off layout reserves the native thin strip below full")
restricted:Command("off")
Check(rp.Health.points.BOTTOMRIGHT[1] == rp.ShiftMana and ReservedSpace(rp) == 5, "Power-off layout restores native health anchor relationships")
restricted:Command("on")
restricted.FlareUI.UFRing = { Plate = function() return true end, TwoSlots = function() return true end }
restricted:Update()
restricted:Command("debug")
Check(restricted.messages[#restricted.messages]:find("plate: opacity only", 1, true), "Plate style explicitly falls back to opacity")
restricted.FlareUI.UFRing = nil
restricted.enginePercent = 1
restricted.current = restricted.secret
restricted.UnitPowerPercent = function() error("Unavailable curve evaluation") end
restricted:Update()
Check(rp.ShiftMana.alpha == 1, "Curve errors safely leave the bar visible")
restricted.UnitPowerPercent = nil
restricted:Update()
Check(rp.ShiftMana.alpha == 1, "Missing curve API safely leaves the bar visible")
e.events:OnEvent("PLAYER_ENTERING_WORLD")
Check(not e.events.registered.ADDON_LOADED, "Addon initialization listener removed")
print(("Passed %d checks using FlareUI's native visibility, update, and layout functions."):format(passed))
