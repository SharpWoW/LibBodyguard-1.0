--[[
    Copyright (c) 2014 by Adam Hellberg.

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in
    all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
    THE SOFTWARE.
]]

local MAJOR = "LibBodyguard-1.0"
local MINOR = 1

local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

local band, bor = bit.band, bit.bor

local BODYGUARD_FLAGS = bor(COMBATLOG_OBJECT_TYPE_GUARDIAN,
                            COMBATLOG_OBJECT_CONTROL_PLAYER,
                            COMBATLOG_OBJECT_REACTION_FRIENDLY,
                            COMBATLOG_OBJECT_AFFILIATION_MINE)

local reputation_spells = {
    [174225] = true, [174699] = true, [174685] = true, [174673] = true, [174692] = true, [174697] = true, [174232] = true,
    [174674] = true, [174689] = true, [174642] = true, [174638] = true, [174651] = true, [174663] = true, [174238] = true,
    [174234] = true, [174659] = true, [174645] = true, [174649] = true, [174639] = true, [174695] = true, [174653] = true,
    [174683] = true, [174660] = true, [174235] = true, [174703] = true, [174700] = true, [174647] = true, [174657] = true,
    [174693] = true, [174658] = true, [174640] = true, [174666] = true, [174667] = true, [174670] = true, [174668] = true,
    [174675] = true, [174224] = true, [174677] = true, [174680] = true, [174180] = true, [174701] = true, [174681] = true,
    [174203] = true, [174228] = true, [174687] = true, [174236] = true, [174655] = true, [174676] = true, [174652] = true,
    [174656] = true, [174202] = true, [174230] = true, [174694] = true, [174698] = true, [174237] = true, [174679] = true,
    [174199] = true, [174688] = true, [174702] = true, [174646] = true, [174654] = true, [174229] = true, [174669] = true,
    [174671] = true, [174181] = true, [174182] = true, [174672] = true, [174696] = true, [174682] = true, [174200] = true,
    [174201] = true, [174231] = true, [174678] = true, [174686] = true, [174684] = true, [174233] = true, [174187] = true,
    [174661] = true, [174641] = true, [174648] = true, [174179] = true, [174227] = true
}

-- Valid barracks IDs, 27 = lvl 2 barracks, 28 = lvl 3 barracks
local barracks_ids = {[27] = true, [28] = true}

lib.Status = {
    Inactive = 0,
    Active = 1,
    Unknown = 2
}

local bodyguard = {}

local function ResetBodyguard()
    bodyguard.name = nil
    bodyguard.level = 0
    bodyguard.health = 0
    bodyguard.max_health = 0
    bodyguard.npc_id = 0
    bodyguard.follower_id = 0
    bodyguard.last_known_guid = nil
    bodyguard.status = lib.Status.Unknown
    bodyguard.loaded_from_building = false
end

ResetBodyguard()

local callbacks = {
    guid = {},
    name = {},
    level = {},
    health = {},
    status = {}
}

local function RunCallback(cb_type, ...)
    for func, enabled in pairs(callbacks[cb_type]) do
        if enabled then pcall(func, lib, ...) end
    end
end

local frame = CreateFrame("Frame")

local events = {}

local function UpdateFromBuildings()
    ResetBodyguard()
    bodyguard.loaded_from_building = true
    local buildings = C_Garrison.GetBuildings()
    for i = 1, #buildings do
        local building = buildings[i]
        local building_id = building.buildingID
        local plot_id = building.plotID
        if barracks_ids[building_id] then
            local name, level, quality, displayID, followerID, garrFollowerID, status, portraitIconID = C_Garrison.GetFollowerInfoForBuilding(plot_id)
            if not name then
                bodyguard.status = lib.Status.Inactive
                RunCallback("status", bodyguard.status)
                return
            end
            bodyguard.name = name
            bodyguard.level = level
            bodyguard.follower_id = type(garrFollowerID) == "string" and tonumber(garrFollowerID, 16) or garrFollowerID
            RunCallback("name", bodyguard.name)
            RunCallback("level", bodyguard.level)
            break
        end
    end
end

local function UpdateFromUnit(unit)
    local name = UnitName(unit)
    if name ~= bodyguard.name then return end
    bodyguard.last_known_guid = UnitGUID(unit)
    bodyguard.health = UnitHealth(unit)
    bodyguard.max_health = UnitHealthMax(unit)
    RunCallback("guid", bodyguard.last_known_guid)
    RunCallback("health", bodyguard.health, bodyguard.max_health)
end

function events.GARRISON_BUILDINGS_SWAPPED()
    UpdateFromBuildings()
end

function events.GARRISON_BUILDING_ACTIVATED()
    UpdateFromBuildings()
end

function events.GARRISON_BUILDING_UPDATE(buildingID)
    if barracks_ids[buildingID] then UpdateFromBuildings() end
end

function events.GARRISON_FOLLOWER_REMOVED()
    UpdateFromBuildings()
end

function events.GARRISON_UPDATE()
    UpdateFromBuildings()
end

function events.PLAYER_TARGET_CHANGED(cause)
    if not bodyguard.name then return end
    if cause ~= "LeftButton" and cause ~= "up" then return end
    UpdateFromUnit("target")
end

function events.UPDATE_MOUSEOVER_UNIT()
    if not bodyguard.name then return end
    UpdateFromUnit("mouseover")
end

-- We listen to CLEU to find out when the bodyguard is damaged or healed
function events.COMBAT_LOG_EVENT_UNFILTERED(timestamp, event, hideCaster, sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID, destName, destFlags, destRaidFlags, ...)
    -- First find out if the destination (damaged or healed) is the player's bodyguard
    if not bodyguard.name or (not sourceName and not destName) then return end
    local args = {...} -- Box the varargs
    if event == "SPELL_CAST_SUCCESS" and sourceName == bodyguard.name then -- Check for the reputation check spell
        local isBodyguard = band(sourceFlags, BODYGUARD_FLAGS) == BODYGUARD_FLAGS
        if not isBodyguard then return end
        -- With a SPELL_* event, the first vararg is spell id
        local spell_id = args[1]
        if not reputation_spells[spell_id] then return end
        bodyguard.last_known_guid = sourceGUID
        bodyguard.status = lib.Status.Active
        RunCallback("guid", bodyguard.last_known_guid)
        RunCallback("status", bodyguard.status)
    elseif destName == bodyguard.name then
        local isBodyguard = band(destFlags, BODYGUARD_FLAGS) == BODYGUARD_FLAGS
        if not isBodyguard then return end
        local prefix, suffix = event:match("^([A-Z_]+)_([A-Z]+)$")

        local amount_idx = 1

        if prefix:match("^SPELL") then
            amount_idx = 4
        elseif prefix == "ENVIRONMENTAL" then
            amount_idx = 2
        end

        local amount = args[amount_idx]

        local changed = false

        if suffix == "DAMAGE" then
            bodyguard.health = bodyguard.health - amount
            changed = true
        elseif suffix == "HEAL" then
            bodyguard.health = bodyguard.health + amount
            changed = true
        elseif suffix == "INSTAKILL" then
            bodyguard.health = 0
            changed = true
        end

        if changed then
            RunCallback("health", bodyguard.health, bodyguard.max_health)
            if bodyguard.health <= 0 then
                bodyguard.health = 0
                bodyguard.status = lib.Status.Unknown
                RunCallback("status", bodyguard.status)
            end
        end
    end
end

frame:SetScript("OnEvent", function(f, e, ...)
    if events[e] then events[e](...) end
end)

for k, _ in pairs(events) do
    frame:RegisterEvent(k)
end

-- Public API

function lib:Exists()
    return bodyguard.name and bodyguard.loaded_from_building
end

function lib:UpdateFromBuilding()
    UpdateBodyguardFromBuildings()
end

function lib:GetInfo()
    return setmetatable({}, {__index = function(t, k) return bodyguard[k] end, __metatable = 'Forbidden'})
end

-- NOTE: This is not 100% reliable, GUID may change
function lib:GetGUID()
    return bodyguard.last_known_guid
end

function lib:GetStatus()
    return bodyguard.status
end

function lib:GetName()
    return bodyguard.name
end

function lib:GetLevel()
    return bodyguard.level
end

--- Returns bodyguard health
-- @return Current (predicted) health of the player's bodyguard.
function lib:GetHealth()
    return bodyguard.health
end

function lib:GetMaxHealth()
    return bodyguard.max_health
end

function lib:IsAlive()
    return self:GetHealth() > 0
end

function lib:RegisterCallback(cb_type, cb_func)
    if not callbacks[cb_type] then error("Invalid callback type: " .. tostring(cb_type)) end
    if callbacks[cb_type][cb_func] then return end -- Silent fail if that callback func is already registered
    callbacks[cb_type][cb_func] = true
end

function lib:UnregisterCallback(cb_type, cb_func)
    if not callbacks[cb_type] then error("Invalid callback type: " .. tostring(cb_type)) end
    callbacks[cb_type][cb_func] = nil
end
