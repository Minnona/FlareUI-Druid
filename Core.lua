local ADDON_NAME, plugin = ...
local events = CreateFrame("Frame")
local flare, unitFrames
local installed = false
local installedShown
local canRead = canaccessvalue or function() return true end
local manaCurve
local opacityMode = "normal"
local layoutMode = "native"
local manaTextKeys = { "ShiftManaText", "ShiftManaTextLeft", "ShiftManaTextMid" }

local function Say(message)
    print("|cffff7d0aFlareUI Druid:|r " .. message)
end

local function ApplyManaOpacity(frame)
    if not (frame and frame.fuiUnit == "player" and frame.ShiftMana) then return end
    local alpha = 1
    opacityMode = "normal"
    layoutMode = "native"
    if FlareUIDruidDB.hideFullMana and not frame.fuiSample and not frame.shiftTestOnly
        and not unitFrames.shiftTest and not (flare.EditPreviewing and flare.EditPreviewing()) then
        local manaType = Enum.PowerType.Mana
        local current = UnitPower("player", manaType)
        local maximum = UnitPowerMax("player", manaType)
        if not canRead(current) or not canRead(maximum) then
            -- The client can evaluate a curve and feed its restricted result
            -- directly to SetAlpha. Lua must never compare that result.
            -- Same supported path as FlareUI's Missing Mana frame fading.
            if UnitPowerPercent and C_CurveUtil and C_CurveUtil.CreateCurve
                and Enum.LuaCurveType and Enum.LuaCurveType.Step then
                if not manaCurve then
                    manaCurve = C_CurveUtil.CreateCurve()
                    manaCurve:SetType(Enum.LuaCurveType.Step)
                    manaCurve:AddPoint(0, 1)
                    manaCurve:AddPoint(1, 0)
                end
                local ok, value = pcall(UnitPowerPercent, "player", manaType, false, manaCurve)
                if ok and (not canRead(value) or type(value) == "number") then
                    alpha = value
                    opacityMode = "mana curve"
                    if frame.ShiftMana:IsShown() then
                        local layoutOK, result = pcall(plugin.CollapseManaLayout, frame, unitFrames, flare, value)
                        if layoutOK then
                            layoutMode = result
                        else
                            plugin.RestoreManaLayout(frame)
                            layoutMode = "fallback: " .. tostring(result)
                        end
                    end
                else
                    opacityMode = "mana curve unavailable"
                end
            else
                opacityMode = "mana curve unavailable"
            end
        end
    end
    -- Text can live on FlareUI's separate mouseover/plate layers, so fade
    -- those slots too. The five-second-rule spark inherits the bar's alpha.
    frame.ShiftMana:SetAlpha(alpha)
    if frame.ShiftManaSeparator then frame.ShiftManaSeparator:SetAlpha(alpha) end
    for _, key in ipairs(manaTextKeys) do
        if frame[key] then frame[key]:SetAlpha(alpha) end
    end
end

local function RefreshMana()
    local player = _G.FlareUI_UF_Player
    if installed and player and player.ShiftMana then
        -- FlareUI updates the bar, separator, text, and layout together. Its
        -- UpdateShiftMana path changes only unprotected children, even in combat.
        unitFrames.UpdateShiftMana(player)
    end
end

local function Install()
    local _, class = UnitClass("player")
    if class ~= "DRUID" then return end

    flare = _G.FlareUI
    unitFrames = flare and flare.UnitFrames
    if not (unitFrames and type(unitFrames.ShiftManaShown) == "function"
        and type(unitFrames.UpdateShiftMana) == "function") then
        Say("This FlareUI version is unsupported; the mana bar was left alone.")
        return
    end

    -- This predicate is shared by all FlareUI frame styles. A post-hook cannot
    -- change its result, so wrap it in memory; no FlareUI files or settings change.
    local originalShown = unitFrames.ShiftManaShown
    unitFrames.ShiftManaShown = function(frame, ...)
        local shown = originalShown(frame, ...)
        if not shown or not FlareUIDruidDB.hideFullMana then return shown end
        if frame.fuiUnit ~= "player" or frame.fuiSample or frame.shiftTestOnly then return shown end
        if unitFrames.shiftTest or (flare.EditPreviewing and flare.EditPreviewing()) then return shown end

        local manaType = Enum.PowerType.Mana
        local current = UnitPower("player", manaType)
        local maximum = UnitPowerMax("player", manaType)
        -- If the client restricts these values, retain FlareUI's own decision.
        if not canRead(current) or not canRead(maximum) then return shown end
        if type(current) ~= "number" or type(maximum) ~= "number" or maximum <= 0 then return shown end
        if current >= maximum then return false end
        return shown
    end
    installed = true
    installedShown = unitFrames.ShiftManaShown
    local originalUpdate = unitFrames.UpdateShiftMana
    unitFrames.UpdateShiftMana = function(frame, ...)
        -- Restore constant anchors before native code reads or lays out bars.
        plugin.RestoreManaLayout(frame)
        originalUpdate(frame, ...)
        ApplyManaOpacity(frame)
    end
    -- FlareUI already updates this predicate on mana ticks, maximum mana
    -- changes, form changes, profile refreshes, and Edit Mode transitions.
end

SLASH_FLAREUIDRUID1 = "/fuidruid"
SlashCmdList.FLAREUIDRUID = function(message)
    local command = (message or ""):match("^%s*(.-)%s*$"):lower()
    if command == "debug" then
        local function Value(value)
            if not canRead(value) then return "restricted" end
            return tostring(value)
        end
        local frame = _G.FlareUI_UF_Player
        Say("Debug 0.1.7: installed=" .. tostring(installed)
            .. ", hook=" .. tostring(installed and unitFrames.ShiftManaShown == installedShown)
            .. ", frame=" .. tostring(frame ~= nil))
        Say("mana=" .. Value(UnitPower("player", Enum.PowerType.Mana))
            .. "/" .. Value(UnitPowerMax("player", Enum.PowerType.Mana))
            .. ", power=" .. Value(UnitPowerType("player")))
        Say("preview=" .. tostring(flare and flare.EditPreviewing and flare.EditPreviewing() or false)
            .. ", test=" .. tostring(unitFrames and unitFrames.shiftTest or false)
            .. ", sample=" .. tostring(frame and frame.fuiSample or false)
            .. ", bar=" .. tostring(frame and frame.ShiftMana and frame.ShiftMana:IsShown() or false)
            .. ", opacity=" .. opacityMode)
        Say("layout=" .. layoutMode)
        return
    end
    if command == "on" or command == "off" then
        FlareUIDruidDB.hideFullMana = command == "on"
        RefreshMana()
    elseif command ~= "" and command ~= "status" then
        Say("/fuidruid on | off | status | debug")
        return
    end
    Say("Hide shapeshift mana when full: " .. (FlareUIDruidDB.hideFullMana and "on" or "off") .. ".")
    local _, class = UnitClass("player")
    if class ~= "DRUID" then
        Say("Only affects druids.")
    elseif not installed then
        Say("Integration unavailable for this FlareUI version.")
    end
end

events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, addon)
    if event == "ADDON_LOADED" then
        if addon ~= ADDON_NAME then return end
        self:UnregisterEvent("ADDON_LOADED")
        if type(FlareUIDruidDB) ~= "table" then FlareUIDruidDB = {} end
        if type(FlareUIDruidDB.hideFullMana) ~= "boolean" then
            FlareUIDruidDB.hideFullMana = true
        end
        -- RequiredDeps loads FlareUI first. Install before its PLAYER_LOGIN
        -- initialization so the first player-frame layout uses our predicate.
        Install()
        if installed then
            self:RegisterEvent("PLAYER_ENTERING_WORLD")
            RefreshMana()
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        RefreshMana()
    end
end)
