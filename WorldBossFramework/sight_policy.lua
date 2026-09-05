-- Per-boss response preset. No shared species preset or skill data is mutated.
local Sight = {}
local fields = {"Discover_Player","Discover_Greater","Discover_Equal","Discover_Smaller",
    "Damaged_Player","Damaged_Greater","Damaged_Equal","Damaged_Smaller"}
local NAME="WorldBossFramework_PlayerSight"

function Sight.apply(sensor, host)
    if not host.valid(sensor) then return false,"sensor_unavailable" end
    local original=sensor.AIResponsePreset
    if not host.valid(original) then return false,"response_preset_unavailable" end
    -- Reuse only our own sensor-owned preset, never a species singleton.
    local reuse = original:GetFName():ToString()==NAME
        and original:GetOuter():GetAddress()==sensor:GetAddress()
    local values={}
    for _,field in ipairs(fields) do
        local value=tonumber(original[field])
        if not value or value%1~=0 or value<0 or value>4 then return false,"invalid_response:" .. field end
        values[field]=value
    end
    values.Discover_Player=4 -- EPalAIResponseType::Battle_Anyway
    values.Damaged_Player=4
    local preset=original
    if not reuse then
        local cls=host.find_class("/Script/Pal.PalAIResponsePreset")
        if not host.valid(cls) then return false,"response_class_unavailable" end
        -- Outer + sensor.AIResponsePreset UPROPERTY provide engine ownership;
        -- this module does not retain the object in a Lua table.
        preset=host.construct(cls,sensor,host.fname(NAME))
        if not host.valid(preset) then return false,"response_allocation_failed" end
    end
    for _,field in ipairs(fields) do preset[field]=values[field] end
    for _,field in ipairs(fields) do
        if tonumber(preset[field])~=values[field] then return false,"response_readback_failed:" .. field end
    end
    if not reuse then sensor.AIResponsePreset=preset end
    local assigned=sensor.AIResponsePreset
    if not host.valid(assigned) or assigned:GetAddress()~=preset:GetAddress() then
        return false,"response_assignment_failed"
    end
    return true,"player_sight=Battle_Anyway player_damage=Battle_Anyway other_responses=preserved"
end
return Sight
