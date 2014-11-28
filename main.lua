local MAJOR = "LibBodyguard-1.0"
local MINOR = 1

local band, bor = bit.band, bit.bor

local BODYGUARD_FLAGS = bor(COMBATLOG_OBJECT_TYPE_GUARDIAN,
                            COMBATLOG_OBJECT_CONTROL_PLAYER,
                            COMBATLOG_OBJECT_REACTION_FRIENDLY,
                            COMBATLOG_OBJECT_AFFILIATION_MINE)

local lib
if LibStub then
    lib = LibStub:NewLibrary(MAJOR, MINOR)
    if not lib then return end
else
    lib = {}
end

local bodyguard = {
    health = 0,
    max_health = 0
}

local frame = CreateFrame("Frame")

local events = {}

function events.PLAYER_TARGET_CHANGED(cause)
    if cause ~= "LeftButton" and cause ~= "up" then return end
    
end

-- We listen to CLEU to find out when the bodyguard is damaged or healed
function events.COMBAT_LOG_EVENT_UNFILTERED(timestamp, event, hideCaster, sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID, destName, destFlags, destRaidFlags, ...)
    -- First find out if the destination (damaged or healed) is the player's bodyguard
    local isBodyguard = band(destFlags, BODYGUARD_FLAGS) == BODYGUARD_FLAGS
end

frame:SetScript("OnEvent", function(f, e, ...)
    if events[e] then events[e](...) end
end)

for k, _ in pairs(events) do
    frame:RegisterEvent(k)
end

-- Public functions

function lib:GetName()
    return bodyguard.name
end

--- Returns bodyguard health
-- @return Current (predicted) health of the player's bodyguard.
function lib:GetHealth()
    return bodyguard.health
end

return lib
