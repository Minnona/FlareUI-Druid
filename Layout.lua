--[[
Portions of this layout integration are adapted from FlareUI.

MIT License

Copyright (c) 2026 Malkkav

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
]]

local _, plugin = ...
local states = setmetatable({}, { __mode = "k" })

local function PowerSize(frame, unitFrames, flare)
    local db = unitFrames.Kit and unitFrames.Kit.GetDb()
    local settings = db and db.units and db.units.player
    if not settings then return end
    local inset = unitFrames.Kit.INSET or 4
    local portraitSpace = 0
    if frame.Portrait and (settings.portrait or "none") ~= "none"
        and not (flare.UFRing and flare.UFRing.Applies(frame)) then
        portraitSpace = (settings.height or 44) - 2 * inset
    end
    return (settings.width or 220) - 2 * inset - portraitSpace, settings.powerHeight or 8
end

function plugin.RestoreManaLayout(frame)
    local state = frame and states[frame]
    if not (state and state.active) then return end
    -- Even native GetPoint()/GetNumPoints() results can be restricted. Restore
    -- FlareUI's known relationships instead of capturing any resolved geometry.
    state.active = false
    local strip, power, health = frame.ShiftMana, frame.Power, frame.Health
    local edge = strip:IsShown() and "TOP" or "BOTTOM"
    power:ClearAllPoints()
    power:SetPoint("BOTTOMLEFT", strip, edge .. "LEFT", 0, 0)
    power:SetPoint("BOTTOMRIGHT", strip, edge .. "RIGHT", 0, 0)
    if power:IsShown() then
        health:SetPoint("BOTTOMRIGHT", power, "TOPRIGHT", 0, 0)
    else
        health:SetPoint("BOTTOMRIGHT", strip, edge .. "RIGHT", 0, 0)
    end
end

function plugin.CollapseManaLayout(frame, unitFrames, flare, amount)
    -- Forever Style uses a separate atlas for its second slot. Its art needs
    -- a different renderer; keep opacity-only behavior for that style.
    if flare.UFRing and flare.UFRing.Plate(frame) then return "plate: opacity only" end
    if not frame.ShiftMana:IsShown() then return "native" end
    local height = unitFrames.ShiftManaHeight(frame)
    if type(height) ~= "number" or height <= 0 then return "invalid height" end
    if not PowerSize(frame, unitFrames, flare) then return "config unavailable" end

    local state = states[frame]
    if not state then
        local proxy = CreateFrame("StatusBar", nil, frame)
        state = { proxy = proxy }
        states[frame] = state
        proxy:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
        proxy:SetOrientation("VERTICAL")
        proxy:SetReverseFill(false)
        proxy:SetMinMaxValues(-1, 1)
        proxy:SetAlpha(0)
        proxy:Show()

        -- Secret anchoring can persist while native layout is being restored.
        -- Both bars have constant dimensions from settings: use those for the
        -- FSR/GCD sparks even during restore, rather than their restricted rect.
        for _, bar in ipairs({ frame.Power, frame.ShiftMana }) do
            local isMana = bar == frame.ShiftMana
            local getWidth, getHeight = bar.GetWidth, bar.GetHeight
            bar.GetWidth = function(self, ...)
                local width = PowerSize(frame, unitFrames, flare)
                if width then return width end
                return getWidth(self, ...)
            end
            bar.GetHeight = function(self, ...)
                if isMana then return unitFrames.ShiftManaHeight(frame) end
                local _, powerHeight = PowerSize(frame, unitFrames, flare)
                if powerHeight then return powerHeight end
                return getHeight(self, ...)
            end
        end
    end

    local proxy = state.proxy
    proxy:ClearAllPoints()
    proxy:SetPoint("BOTTOMLEFT", frame.ShiftMana, "BOTTOMLEFT", 0, 0)
    proxy:SetPoint("BOTTOMRIGHT", frame.ShiftMana, "BOTTOMRIGHT", 0, 0)
    proxy:SetHeight(2 * height)
    -- A -1..1 range keeps the fill nonzero at both possible values. At 0
    -- (full mana) its top is height pixels up; at 1 it is 2*height up.
    -- Anchoring height pixels below that top reserves 0 or height pixels.
    -- The client performs this geometry; Lua never reads the secret value.
    proxy:SetValue(amount)
    local fill = proxy:GetStatusBarTexture()
    state.active = true
    if frame.Power:IsShown() then
        frame.Power:ClearAllPoints()
        frame.Power:SetPoint("BOTTOMLEFT", fill, "TOPLEFT", 0, -height)
        frame.Power:SetPoint("BOTTOMRIGHT", fill, "TOPRIGHT", 0, -height)
        -- The health bar is already anchored above the power bar.
    else
        frame.Health:SetPoint("BOTTOMRIGHT", fill, "TOPRIGHT", 0, -height)
    end
    return "fill anchor"
end
