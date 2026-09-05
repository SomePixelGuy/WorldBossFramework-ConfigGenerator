-- Guarded UE4SS/PalSchema bridge for WorldBossFramework.
-- Transient UObject references are never retained between operations.

local injected = rawget(_G, "__WORLD_BOSS_FRAMEWORK_NATIVE_TEST")
if type(injected) == "table" then return injected end

local source = (debug.getinfo(1, "S").source or ""):gsub("^@", "")
local mod_directory = source:match("^(.*[\\/])[^\\/]-$")
if not mod_directory then error("WorldBossFramework native bridge could not resolve its directory") end
local WazaIds = assert(loadfile(mod_directory .. "waza_ids.lua", "t", _ENV))()

local SightPolicy = assert(loadfile(mod_directory .. "sight_policy.lua", "t", _ENV))()
local Native = {}
local ZERO_GUID = string.rep("0", 32)
local SPAWNER_CLASS = "BP_PalSpawner_Standard_C"
local SPAWNER_NOTIFY_CLASS = "/Game/Pal/Blueprint/Spawner/BP_PalSpawner_Standard.BP_PalSpawner_Standard_C"
local GUARD_FLAG = "WorldBossFramework"
local death_hook_callback
local death_hook_registered = false
local capture_hook_callback
local capture_hook_registered = false
local spawner_guard_callback
local spawner_guard_registered = false
local spawner_guard_pending = false
local spawner_guard_prefix = "WorldBossFramework_"
local spawner_guard_reporter
local spawner_placements = {}
local resolved_spawners = {}
local relock_generations = {}
local Dispatcher = assert(loadfile(mod_directory .. "dispatcher.lua", "t", _ENV))()
-- Match Palladium's proven split: an async loop owns wall-clock wakeups, and
-- every Unreal operation runs inside a short-lived game-thread submission.
local function start_async_clock(interval_ms, wake)
    if type(LoopAsync) ~= "function" then return nil, "LoopAsync unavailable" end
    if type(ExecuteInGameThread) ~= "function" then
        return nil, "ExecuteInGameThread unavailable"
    end
    local ok, detail = pcall(LoopAsync, interval_ms, function()
        local woke, wake_error = pcall(wake)
        if not woke then
            print("[WorldBossFramework] dispatcher async wake failed: " .. tostring(wake_error))
        end
        return false
    end)
    if not ok then return nil, tostring(detail) end
    return 1, "registered"
end

local function submit_game(callback)
    if type(ExecuteInGameThread) ~= "function" then
        return false, "ExecuteInGameThread unavailable"
    end
    local ok, detail = pcall(ExecuteInGameThread, callback)
    if not ok then return false, tostring(detail) end
    return true, "submitted"
end

local dispatcher = Dispatcher.new(start_async_clock, submit_game, function(message)
    print("[WorldBossFramework] dispatcher: " .. tostring(message))
end)
local game_call = dispatcher.call
local last_dispatch_warning = 0
local last_dispatch_timeouts = 0
local last_dispatch_submit_failures = 0
Native.on_game_thread = function(callback)
    local status, now = dispatcher.status(), os.time()
    if (not status.ready or status.timeouts > last_dispatch_timeouts
        or status.submit_failures > last_dispatch_submit_failures)
        and now-last_dispatch_warning>=30 then
        last_dispatch_warning=now
        last_dispatch_timeouts=status.timeouts
        last_dispatch_submit_failures=status.submit_failures
        print("[WorldBossFramework] dispatcher degraded: " .. tostring(status.error or "game callback incomplete") ..
            "; pending=" .. tostring(status.pending) .. "; in_flight=" .. tostring(status.in_flight) ..
            "; timeouts=" .. tostring(status.timeouts) .. "; submit_failures=" .. tostring(status.submit_failures))
    end
    return dispatcher.schedule(1, callback)
end
Native.dispatcher_status = dispatcher.status
if not dispatcher.status().ready then
    print("[WorldBossFramework] startup blocked: " .. tostring(dispatcher.status().error))
end

local function make_fname(value)
    local constructor = FName
    if constructor == nil then return nil, "FName constructor unavailable" end
    local ok, name = pcall(function() return constructor(tostring(value or "None")) end)
    if not ok then return nil, tostring(name) end
    return name, nil
end

local function valid(object)
    if object == nil then return false end
    local ok, answer = pcall(function() return object:IsValid() end)
    return ok and answer == true
end

local function member(object, name)
    if object == nil then return nil end
    local ok, value = pcall(function() return object[name] end)
    if not ok then return nil end
    return value
end

local function unwrap(value)
    -- Only UE4SS hook-parameter wrappers implement the extraction we need.
    -- GUIDs, vectors, fixed-point structs and UObjects are already values.
    -- `type` is a registered UE4SS method; do not test for `get` by looking it up.
    if type(value) ~= "userdata" then return value end
    local typed, kind = pcall(function() return value:type() end)
    if not typed or (kind ~= "RemoteUnrealParam" and kind ~= "LocalUnrealParam") then
        return value
    end
    local ok, inner = pcall(function() return value:get() end)
    if ok then return inner end -- Preserve legitimate false/nil parameter values.
    return nil
end

local function hex32(word)
    return string.format("%08X", (tonumber(word) or 0) % 0x100000000)
end

local function guid_hex(guid)
    guid = unwrap(guid)
    if guid == nil then return "" end
    local ok, value = pcall(function()
        return hex32(guid.A) .. hex32(guid.B) .. hex32(guid.C) .. hex32(guid.D)
    end)
    if not ok or value == ZERO_GUID then return "" end
    return value
end

local function instance_id(value)
    value = unwrap(value)
    return value and guid_hex(member(value, "InstanceId")) or ""
end

local function text_of(value)
    value = unwrap(value)
    if value == nil then return nil end
    if type(value) == "string" then return value end
    local fn = member(value, "ToString")
    if fn ~= nil then
        local ok, text = pcall(function() return fn(value) end)
        if ok and text ~= nil then return tostring(unwrap(text)) end
    end
    local text = tostring(value)
    if text:match("^FNameUserdata:") or text:match("^FString:") then return nil end
    return text
end

local function object_name(object)
    object = unwrap(object)
    if not valid(object) then return "none" end
    for _, method in ipairs({ "GetFullName", "GetPathName", "GetName" }) do
        local fn = member(object, method)
        if fn ~= nil then
            local ok, value = pcall(function() return fn(object) end)
            if ok and value ~= nil then return tostring(unwrap(value)) end
        end
    end
    return tostring(object)
end

local function class_name(object)
    object = unwrap(object)
    if not valid(object) then return "none" end
    local fn = member(object, "GetClass")
    if fn ~= nil then
        local ok, class = pcall(function() return fn(object) end)
        if ok and valid(class) then return object_name(class) end
    end
    return object_name(object)
end

local function call(object, method, ...)
    if not valid(object) then return false, nil end
    local fn = member(object, method)
    if fn == nil then return false, nil end
    local args = { ... }
    local ok, value = pcall(function() return fn(object, table.unpack(args)) end)
    return ok, ok and unwrap(value) or value
end

local function call_number(object, method)
    local ok, value = call(object, method)
    if not ok then return nil end
    return tonumber(value) or tonumber(member(value, "Value")) or tonumber(member(value, "RawValue"))
end

local function call_boolean(object, method)
    local ok, value = call(object, method)
    if not ok or type(value) ~= "boolean" then return nil end
    return value
end

local function vector(value)
    value = unwrap(value)
    local x, y, z = member(value, "X"), member(value, "Y"), member(value, "Z")
    if type(x) ~= "number" then return nil end
    return { x = x, y = tonumber(y) or 0, z = tonumber(z) or 0 }
end

local function call_vector(object, method)
    local ok, value = call(object, method)
    return ok and vector(value) or nil
end

local function value_number(value)
    value = unwrap(value)
    return tonumber(value) or tonumber(member(value, "Value")) or tonumber(member(value, "RawValue"))
end

local function list_values(value, converter)
    value = unwrap(value)
    if value == nil then return {} end
    local count_ok, count = pcall(function() return #value end)
    if not count_ok then return {} end
    local out = {}
    for index = 1, count do
        local ok, item = pcall(function() return value[index] end)
        if ok then
            item = unwrap(item)
            local converted = converter and converter(item) or item
            if converted ~= nil then out[#out + 1] = converted end
        end
    end
    return out
end

local function joined(values)
    return #values > 0 and table.concat(values, ",") or "none"
end

local function set_member(object, name, value)
    if not valid(object) then return false, "invalid_object" end
    local ok, err = pcall(function() object[name] = value end)
    return ok, ok and nil or tostring(err)
end

local function pal_parameter(character)
    local component = member(character, "CharacterParameterComponent")
    if not valid(component) then return nil, nil end
    local parameter = member(component, "IndividualParameter")
    if not valid(parameter) then
        local ok, value = call(component, "GetIndividualParameter")
        if ok and valid(value) then parameter = value end
    end
    return valid(parameter) and parameter or nil, component
end

local function pal_id(parameter)
    local individual = member(parameter, "IndividualId")
    return individual and instance_id(individual) or ""
end

local function state_uid(state)
    return guid_hex(member(state, "PlayerUId"))
end

local function find_state(uid)
    local ok, states = pcall(FindAllOf, "PalPlayerState")
    if not ok or type(states) ~= "table" then return nil end
    local wanted = tostring(uid or ""):upper()
    for _, state in ipairs(states) do
        if valid(state) and state_uid(state) == wanted then return state end
    end
    return nil
end

local function controller_of_state(state)
    if not valid(state) then return nil end
    local ok, controller = call(state, "GetPlayerController")
    return ok and valid(controller) and controller or nil
end

local function pawn_of_controller(controller)
    if not valid(controller) then return nil end
    local pawn = member(controller, "Pawn") or member(controller, "AcknowledgedPawn")
    if not valid(pawn) then
        local ok, value = call(controller, "GetPawn")
        if ok and valid(value) then pawn = value end
    end
    return valid(pawn) and pawn or nil
end

local function horizontal_distance(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return nil end
    local ax, ay = tonumber(a.x or a.X), tonumber(a.y or a.Y)
    local bx, by = tonumber(b.x or b.X), tonumber(b.y or b.Y)
    if not ax or not ay or not bx or not by then return nil end
    local dx, dy = ax - bx, ay - by
    return math.sqrt(dx * dx + dy * dy)
end

local function utility()
    if type(StaticFindObject) ~= "function" then return nil end
    local ok, object = pcall(StaticFindObject, "/Script/Pal.Default__PalUtility")
    return ok and valid(object) and object or nil
end

local function character_manager(context)
    local util = utility()
    if not util or not valid(context) then return nil, util end
    local ok, manager = call(util, "GetCharacterManager", context)
    return ok and valid(manager) and manager or nil, util
end

local function loaded_pals()
    local ok, characters = pcall(FindAllOf, "PalCharacter")
    if not ok or type(characters) ~= "table" then return {} end
    local out = {}
    for _, character in ipairs(characters) do
        if valid(character) and not valid(member(character, "PlayerState")) then
            local parameter, component = pal_parameter(character)
            local save = parameter and member(parameter, "SaveParameter") or nil
            local species = save and text_of(member(save, "CharacterID")) or nil
            local id = parameter and pal_id(parameter) or ""
            if species and species ~= "None" and id ~= "" then
                out[#out + 1] = {
                    id = id,
                    species = species,
                    level = tonumber(member(save, "Level")) or 0,
                    rare = member(save, "IsRarePal") == true,
                    character = character,
                    parameter = parameter,
                    parameter_component = component,
                    save = save,
                }
            end
        end
    end
    return out
end

local function find_pal(id)
    id = tostring(id or ""):upper()
    for _, pal in ipairs(loaded_pals()) do
        if pal.id == id then return pal end
    end
    return nil
end

local function controller_of_character(character)
    local controller = member(character, "Controller")
    if not valid(controller) then
        local ok, value = call(character, "GetController")
        if ok then controller = value end
    end
    if not valid(controller) then
        local ok, value = call(character, "GetAIController")
        if ok then controller = value end
    end
    return valid(controller) and controller or nil
end

local function handle_of(character, parameter, manager, util)
    local component = member(character, "CharacterParameterComponent")
    local handle = valid(component) and member(component, "IndividualHandle") or nil
    if not valid(handle) then handle = member(parameter, "IndividualHandle") end
    if not valid(handle) and util then
        local ok, value = call(util, "GetIndividualCharacterHandleByActor", character)
        if ok then handle = value end
    end
    if not valid(handle) and manager then
        local ok, value = call(manager, "GetIndividualHandleFromCharacterParameter", parameter)
        if ok then handle = value end
    end
    return valid(handle) and handle or nil
end

local function dead_state(character)
    if not valid(character) then return true, "not_loaded" end
    for _, field in ipairs({ "bIsDead", "IsDeadFlag", "DeadFlag" }) do
        local value = member(character, field)
        if type(value) == "boolean" then return value, "field:" .. field end
    end
    for _, method in ipairs({ "IsDead", "IsDeadCharacter", "GetIsDead" }) do
        local value = call_boolean(character, method)
        if value ~= nil then return value, "method:" .. method end
    end
    return false, "loaded"
end

local function component_state(character, name)
    return valid(member(character, name))
end

local function detail(pal)
    if not pal then return nil end
    local character, parameter, save = pal.character, pal.parameter, pal.save
    local controller = controller_of_character(character)
    local manager, util = character_manager(character)
    local handle = handle_of(character, parameter, manager, util)
    local static = member(character, "StaticCharacterParameterComponent")
    local parameter_component = pal.parameter_component
    local mirror = member(parameter, "SaveParameterMirror")
    local dead, dead_source = dead_state(character)
    local spawned_type = valid(static) and call_number(static, "GetSpawnedCharacterType") or nil
    local uncapturable = call_boolean(parameter, "IsUncapturable")
    if uncapturable == nil then uncapturable = member(parameter, "bIsUncapturable") end
    local static_predator = valid(static) and call_boolean(static, "IsPredatorBossPal") or nil
    local passive_skills = {}
    local passive_ok, passive_value = call(parameter, "GetPassiveSkillList")
    if passive_ok then passive_skills = list_values(passive_value, text_of) end
    local equip_waza = {}
    local equip_ok, equip_value = call(parameter, "GetEquipWaza")
    if equip_ok then
        equip_waza = list_values(equip_value, function(value)
            local numeric = value_number(value)
            return numeric and ((WazaIds.name(numeric) or "unknown") .. ":" .. tostring(numeric)) or text_of(value)
        end)
    end
    local group = ""
    local group_ok, group_value = call(parameter, "GetGroupId")
    if group_ok then group = guid_hex(group_value) end
    local owner_uid = guid_hex(member(save, "OwnerPlayerUId"))

    local pawn = controller and member(controller, "Pawn") or nil
    if not valid(pawn) and controller then
        local ok, value = call(controller, "GetPawn")
        if ok then pawn = value end
    end
    local actor_name, pawn_name = object_name(character), object_name(pawn)
    local possession_matches = valid(controller) and valid(pawn)
        and (pawn == character or pawn_name == actor_name)

    local handle_id = ""
    if handle then
        local ok, value = call(handle, "GetIndividualID")
        if ok then handle_id = instance_id(value) end
    end

    local action_component = controller and (member(controller, "ActionComponent")
        or member(controller, "PalActionComponent")) or nil
    local brain = controller and member(controller, "BrainComponent") or nil
    local blackboard = controller and member(controller, "Blackboard") or nil
    local perception = controller and member(controller, "PerceptionComponent") or nil
    local target = controller and (member(controller, "TargetActor")
        or member(controller, "TargetCharacter") or member(controller, "BattleTarget")) or nil

    local controller_class = class_name(controller)
    local issues = {}
    if not valid(parameter) then issues[#issues + 1] = "individual_parameter" end
    if not handle then issues[#issues + 1] = "individual_handle" end
    if handle_id == "" or handle_id ~= pal.id then issues[#issues + 1] = "handle_id" end
    if not controller then issues[#issues + 1] = "controller" end
    if controller and not controller_class:find("MonsterAIController", 1, true) then
        issues[#issues + 1] = "non_monster_controller"
    end
    if controller and not possession_matches then issues[#issues + 1] = "possession" end
    if spawned_type ~= 2 and spawned_type ~= 8 then issues[#issues + 1] = "spawned_type" end
    if group == "" then issues[#issues + 1] = "group" end
    if not component_state(character, "CharacterMovement") then issues[#issues + 1] = "movement" end

    local hp_ok, hp_value = call(parameter_component, "GetHP")
    local max_hp_ok, max_hp_value = call(parameter_component, "GetMaxHP")
    return {
        id = pal.id, species = pal.species, level = pal.level,
        rank = tonumber(member(save, "Rank")), rare = pal.rare,
        actor = actor_name, class = class_name(character),
        position = call_vector(character, "K2_GetActorLocation"),
        rotation = call_vector(character, "K2_GetActorRotation"),
        scale = call_vector(character, "GetActorScale3D"),
        authority = call_boolean(character, "HasAuthority"),
        local_role = call_number(character, "GetLocalRole"),
        remote_role = call_number(character, "GetRemoteRole"),
        replicates = member(character, "bReplicates"), hidden = member(character, "bHidden"),
        battle_mode = member(character, "bIsBattleMode"), dead = dead, dead_source = dead_source,

        controller = object_name(controller), controller_class = controller_class,
        has_controller = controller ~= nil, controller_pawn = pawn_name,
        possession_matches = possession_matches,
        controller_state = text_of(member(controller, "StateName")) or "unavailable",
        controller_battle_mode = member(controller, "bIsBattleMode"),
        controller_target = object_name(target),
        has_play_default_action = member(controller, "PlayDefaultAction") ~= nil,
        has_action_component = valid(action_component), has_brain_component = valid(brain),
        has_blackboard = valid(blackboard), has_perception = valid(perception),

        parameter = object_name(parameter), parameter_class = class_name(parameter),
        parameter_component = object_name(parameter_component), handle = object_name(handle),
        handle_class = class_name(handle), handle_id = handle_id ~= "" and handle_id or "none",
        group = group ~= "" and group or "none", owner_uid = owner_uid ~= "" and owner_uid or "none",
        spawned_type = spawned_type, uncapturable = uncapturable,
        is_predator = member(parameter_component, "IsPredator"), static_predator = static_predator,
        save_character = text_of(member(save, "CharacterID")) or "unavailable",
        mirror_character = text_of(member(mirror, "CharacterID")) or "unavailable",
        mirror_level = tonumber(member(mirror, "Level")),

        hp = hp_ok and value_number(hp_value) or nil,
        max_hp = max_hp_ok and value_number(max_hp_value) or nil,
        hp_rate = call_number(parameter_component, "GetHPRate"),
        melee_attack = call_number(parameter, "GetMeleeAttack"),
        melee_attack_buffed = call_number(parameter, "GetMeleeAttack_withBuff"),
        shot_attack = call_number(parameter, "GetShotAttack"),
        shot_attack_buffed = call_number(parameter, "GetShotAttack_withBuff"),
        defense = call_number(parameter, "GetDefense"),
        defense_buffed = call_number(parameter, "GetDefense_withBuff"),
        talent_hp = tonumber(member(save, "Talent_HP")),
        talent_melee = tonumber(member(save, "Talent_Melee")),
        talent_shot = tonumber(member(save, "Talent_Shot")),
        talent_defense = tonumber(member(save, "Talent_Defense")),
        enemy_hp_rate = tonumber(member(parameter_component, "AdditionalEnemyMaxHPRate")),
        enemy_receive_rate = tonumber(member(parameter_component, "AdditionalEnemyReceiveDamageRate")),
        enemy_inflict_rate = tonumber(member(parameter_component, "AdditionalEnemyInflictDamageRate")),
        passive_skills = joined(passive_skills), equip_waza = joined(equip_waza),

        has_parameter_component = valid(parameter_component), has_static_component = valid(static),
        has_status_component = component_state(character, "StatusComponent"),
        has_movement_component = component_state(character, "CharacterMovement"),
        has_capsule_component = component_state(character, "CapsuleComponent"),
        has_mesh = component_state(character, "Mesh"),
        has_root_component = component_state(character, "RootComponent"),

        wiring_status = #issues == 0 and "complete" or "partial",
        wiring_issues = #issues == 0 and "none" or table.concat(issues, ","),
    }
end

local function all_spawners()
    local ok, spawners = pcall(FindAllOf, SPAWNER_CLASS)
    if not ok or type(spawners) ~= "table" then return {} end
    local out = {}
    for _, spawner in ipairs(spawners) do
        if valid(spawner) then out[#out + 1] = spawner end
    end
    return out
end

local function get_spawner_name(spawner)
    local ok, value = call(spawner, "GetSpawnerName")
    local name = ok and text_of(value) or text_of(member(spawner, "SpawnerName"))
    return name and tostring(name) or ""
end

local function find_spawner(name)
    local wanted = tostring(name or ""):lower()
    for _, spawner in ipairs(all_spawners()) do
        if get_spawner_name(spawner):lower() == wanted then return spawner end
    end
    return nil
end

local function spawner_pal_summary(spawner)
    local result = {}
    local ok = pcall(function()
        local groups = spawner.SpawnGroupList
        for i = 1, #groups do
            local pals = groups[i].PalList
            for j = 1, #pals do
                local tribe = pals[j]
                local id = text_of(member(member(tribe, "PalId"), "Key"))
                    or text_of(member(tribe, "PalId")) or "None"
                result[#result + 1] = string.format("%s:%s-%s:%s-%s", id,
                    tostring(member(tribe, "Level") or "?"), tostring(member(tribe, "Level_Max") or "?"),
                    tostring(member(tribe, "Num") or "?"), tostring(member(tribe, "Num_Max") or "?"))
            end
        end
    end)
    if not ok then return "unreadable" end
    return #result > 0 and table.concat(result, ",") or "empty"
end

local function placement_for(name)
    return spawner_placements[tostring(name or ""):lower()]
end

local function default_object(path)
    if type(StaticFindObject) ~= "function" then return nil end
    local ok, object = pcall(StaticFindObject, path)
    object = ok and unwrap(object) or nil
    return valid(object) and object or nil
end

local function ground_surface(spawner, placement)
    local kismet = default_object("/Script/Engine.Default__KismetSystemLibrary")
    local util = default_object("/Script/Pal.Default__PalUtility")
    if not kismet then return nil, "KismetSystemLibrary unavailable" end
    if not util then return nil, "PalUtility unavailable" end
    local channel_ok, trace_channel = call(util, "ConvertToTraceTypeQuery", 3)
    if not channel_ok or trace_channel == nil then return nil, "ground trace channel unavailable" end

    local start = { X = placement.world_x, Y = placement.world_y, Z = 200000.0 }
    local finish = { X = placement.world_x, Y = placement.world_y, Z = -200000.0 }
    local hit, hidden = {}, { R = 0.0, G = 0.0, B = 0.0, A = 0.0 }
    local ok, was_hit = pcall(function()
        return kismet:LineTraceSingle(spawner, start, finish, trace_channel, false,
            { spawner }, 0, hit, true, hidden, hidden, 0.0)
    end)
    if not ok then return nil, "LineTraceSingle failed: " .. tostring(was_hit) end
    if unwrap(was_hit) ~= true then return nil, "ground trace did not hit" end
    local impact = vector(member(hit, "ImpactPoint") or member(hit, "Location"))
    if not impact then return nil, "ground trace returned no impact point" end
    return impact, nil
end

local function ensure_spawner_grounded(spawner)
    local name = get_spawner_name(spawner)
    local placement = placement_for(name)
    if not placement then return false, "no configured placement for " .. tostring(name) end
    local key = name:lower()
    local current = call_vector(spawner, "K2_GetActorLocation")
    local previous = resolved_spawners[key]
    if current and previous and previous.ground_resolved == true
        and math.abs(current.x - previous.world_x) <= 5
        and math.abs(current.y - previous.world_y) <= 5
        and math.abs(current.z - previous.resolved_z) <= 5 then
        return true, previous
    end

    local impact, trace_error = ground_surface(spawner, placement)
    if not impact then
        resolved_spawners[key] = {
            ground_resolved = false, ground_error = trace_error,
            map_x = placement.map_x, map_y = placement.map_y,
            world_x = placement.world_x, world_y = placement.world_y,
            clearance = placement.clearance,
        }
        return false, trace_error
    end

    local target = {
        X = placement.world_x,
        Y = placement.world_y,
        Z = impact.z + placement.clearance,
    }
    local move_hit = {}
    local moved, move_result = call(spawner, "K2_SetActorLocation", target, false, move_hit, true)
    if not moved or move_result == false then
        local rotation_ok, rotation = call(spawner, "K2_GetActorRotation")
        if not rotation_ok then rotation = { Pitch = 0.0, Yaw = 0.0, Roll = 0.0 } end
        moved, move_result = call(spawner, "K2_TeleportTo", target, rotation)
    end
    if not moved or move_result == false then
        local why = "spawner relocation failed: " .. tostring(move_result)
        resolved_spawners[key] = {
            ground_resolved = false, ground_error = why,
            map_x = placement.map_x, map_y = placement.map_y,
            world_x = placement.world_x, world_y = placement.world_y,
            ground_z = impact.z, clearance = placement.clearance,
        }
        return false, why
    end

    local verified = call_vector(spawner, "K2_GetActorLocation")
    if not verified or math.abs(verified.x - target.X) > 5
        or math.abs(verified.y - target.Y) > 5 or math.abs(verified.z - target.Z) > 5 then
        local why = "spawner relocation verification failed"
        resolved_spawners[key] = {
            ground_resolved = false, ground_error = why,
            map_x = placement.map_x, map_y = placement.map_y,
            world_x = placement.world_x, world_y = placement.world_y,
            ground_z = impact.z, clearance = placement.clearance,
        }
        return false, why
    end

    local result = {
        ground_resolved = true, ground_error = nil,
        map_x = placement.map_x, map_y = placement.map_y,
        world_x = placement.world_x, world_y = placement.world_y,
        ground_z = impact.z, resolved_z = target.Z,
        clearance = placement.clearance,
    }
    resolved_spawners[key] = result
    return true, result
end

local function spawner_detail(spawner)
    if not valid(spawner) then return nil end
    local name = get_spawner_name(spawner)
    local ground = resolved_spawners[name:lower()] or {}
    local group_ok, group = call(spawner, "GetWildGroupGuid")
    return {
        name = name,
        actor = object_name(spawner),
        class = class_name(spawner),
        position = call_vector(spawner, "K2_GetActorLocation"),
        disabled = call_boolean(spawner, "IsSpawnDisable"),
        spawned = call_boolean(spawner, "IsSpawned"),
        group = guid_hex(group_ok and group or member(spawner, "WildGroupGuid")),
        groups = spawner_pal_summary(spawner),
        ground_resolved = ground.ground_resolved == true,
        ground_error = ground.ground_error,
        map_x = ground.map_x, map_y = ground.map_y,
        world_x = ground.world_x, world_y = ground.world_y,
        ground_z = ground.ground_z, resolved_z = ground.resolved_z,
        clearance = ground.clearance,
        build_protected=false,
        build_protection="suspended_recovery_patch",
    }
end

local function set_spawner_disabled(spawner, disabled)
    if not valid(spawner) then return false, "spawner_not_loaded" end
    local flag, flag_error = make_fname(GUARD_FLAG)
    if not flag then return false, flag_error end
    local ok, result = call(spawner, "SetSpawnDisableFlag", flag, disabled == true)
    if not ok then return false, tostring(result or "SetSpawnDisableFlag unavailable") end
    return true, disabled and "locked" or "unlocked"
end

local function lock_matching_spawners(prefix)
    local count, failed, grounded, ground_failed, rows = 0, 0, 0, 0, {}
    local wanted = tostring(prefix or spawner_guard_prefix):lower()
    for _, spawner in ipairs(all_spawners()) do
        local name = get_spawner_name(spawner)
        if name:lower():sub(1, #wanted) == wanted then
            local ok, why = set_spawner_disabled(spawner, true)
            if ok then count = count + 1 else failed = failed + 1 end
            local ground_ok, ground_result = false, "spawner lock failed"
            if ok then ground_ok, ground_result = ensure_spawner_grounded(spawner) end
            if ground_ok then
                grounded = grounded + 1
            else ground_failed = ground_failed + 1 end
            local row = spawner_detail(spawner) or {}
            row.lock_result = ok and (ground_ok and "locked_grounded" or "locked_ground_failed") or tostring(why)
            if not ground_ok then row.ground_error = tostring(ground_result) end
            rows[#rows + 1] = row
        end
    end
    table.sort(rows, function(a, b) return tostring(a.name) < tostring(b.name) end)
    return {
        locked = count, failed = failed,
        grounded = grounded, ground_failed = ground_failed,
        spawners = rows,
    }
end

local function report_guard(reason, report)
    if type(spawner_guard_reporter) ~= "function" then return end
    pcall(spawner_guard_reporter, reason, report)
end

local function schedule_guard(reason)
    if spawner_guard_pending then return end
    spawner_guard_pending = true
    local function run()
        spawner_guard_pending = false
        local ok, report = pcall(lock_matching_spawners, spawner_guard_prefix)
        report_guard(reason, ok and report or { locked = 0, failed = 1, error = tostring(report) })
    end
    -- Only enqueue Lua work here; construction notifications may re-enter.
    local ok, why = Native.schedule(1, run)
    if not ok then
        spawner_guard_pending = false
        report_guard(reason, {locked=0, failed=1, error=why})
    end
end

function Native.capabilities()
    local fname_present = FName ~= nil
    return {
        find_all = type(FindAllOf) == "function",
        game_thread = dispatcher.status().ready,
        delay = dispatcher.status().ready,
        notify = type(NotifyOnNewObject) == "function",
        static_find = type(StaticFindObject) == "function",
        ground_trace = type(StaticFindObject) == "function",
        fname = fname_present,
        fname_type = type(FName),
        hook = type(RegisterHook) == "function",
        game_executor = "loop_async_one_shot",
        ready = type(FindAllOf) == "function" and dispatcher.status().ready
            and type(NotifyOnNewObject) == "function"
            and type(StaticFindObject) == "function" and fname_present,
    }
end

local function set_placements(placements)
    spawner_placements = {}
    if type(placements) ~= "table" then return end
    for name, placement in pairs(placements) do
        if type(placement) == "table" then
            spawner_placements[tostring(name):lower()] = placement
        end
    end
end

function Native.install_spawner_guard(prefix, reporter, placements)
    if not dispatcher.status().ready then return false, dispatcher.status().error end
    spawner_guard_prefix = tostring(prefix or "WorldBossFramework_")
    spawner_guard_reporter = reporter
    set_placements(placements)
    if spawner_guard_registered then return true, "already_registered" end
    if type(NotifyOnNewObject) ~= "function" then return false, "NotifyOnNewObject unavailable" end
    spawner_guard_callback = function() schedule_guard("new_spawner") end
    local ok, result = pcall(NotifyOnNewObject, SPAWNER_NOTIFY_CLASS, spawner_guard_callback)
    if not ok then return false, tostring(result) end
    spawner_guard_registered = true
    return true, "registered"
end

function Native.reconcile_spawners(prefix, placements, done)
    set_placements(placements)
    if type(done) ~= "function" then done = function() end end
    local ok, err = game_call(function()
        local success, report = pcall(lock_matching_spawners, prefix)
        done(success, success and nil or tostring(report), success and report or nil)
    end)
    return ok, ok and "scheduled" or tostring(err)
end

function Native.list_spawners(prefix)
    local wanted, rows = tostring(prefix or spawner_guard_prefix):lower(), {}
    for _, spawner in ipairs(all_spawners()) do
        local row = spawner_detail(spawner)
        if row and row.name:lower():sub(1, #wanted) == wanted then rows[#rows + 1] = row end
    end
    table.sort(rows, function(a, b) return a.name < b.name end)
    return rows
end

function Native.inspect_spawner(name)
    return spawner_detail(find_spawner(name))
end

function Native.schedule(delay_ms, callback)
    return dispatcher.schedule(delay_ms, callback)
end

function Native.players_near(location, radius)
    radius = tonumber(radius)
    if type(location) ~= "table" or not radius or radius <= 0 then
        return nil, "invalid_player_proximity_query"
    end
    local ok, states = pcall(FindAllOf, "PalPlayerState")
    if not ok or type(states) ~= "table" then return nil, "player_states_unavailable" end
    local result = { count = 0, examined = 0, nearest_distance = nil, players = {} }
    for _, state in ipairs(states) do
        local controller = controller_of_state(state)
        local pawn = pawn_of_controller(controller)
        local position = pawn and call_vector(pawn, "K2_GetActorLocation") or nil
        local apart = position and horizontal_distance(position, location) or nil
        if apart then
            result.examined = result.examined + 1
            if result.nearest_distance == nil or apart < result.nearest_distance then
                result.nearest_distance = apart
            end
            if apart <= radius then
                result.count = result.count + 1
                -- Keep only scalar identity data.  No reflected player/state
                -- objects escape this bridge call or enter the reward ledger.
                local uid = state_uid(state)
                if uid ~= "" then result.players[#result.players + 1] = { uid = uid, distance = apart } end
            end
        end
    end
    table.sort(result.players, function(a, b) return a.uid < b.uid end)
    return result
end

function Native.lock_spawner(name, done)
    if type(done) ~= "function" then done = function() end end
    local scheduled, schedule_error = game_call(function()
        local spawner = find_spawner(name)
        if not spawner then done(false, "spawner_not_loaded") return end
        local ok, why = set_spawner_disabled(spawner, true)
        done(ok, ok and nil or why, spawner_detail(spawner))
    end)
    return scheduled, scheduled and "scheduled" or tostring(schedule_error)
end

function Native.release_spawner(name, done)
    if type(done) ~= "function" then done = function() end end
    local scheduled, schedule_error = game_call(function()
        local spawner = find_spawner(name)
        if not spawner then done(false, "spawner_not_loaded") return end
        local before = spawner_detail(spawner) or {}
        local locked, lock_error = set_spawner_disabled(spawner, true)
        if not locked then done(false, lock_error, { before = before }) return end
        local reset_ok, reset_error = call(spawner, "SetSpawnedFlag", false)
        if not reset_ok then
            done(false, tostring(reset_error or "SetSpawnedFlag unavailable"), { before = before })
            return
        end
        pcall(function() spawner.RespawnTimer = 0.0 end)
        pcall(function() spawner.RespawnTime = 0.0 end)
        local after = spawner_detail(spawner) or {}
        if after.spawned ~= false then
            done(false, "spawned_flag_verification_failed", { before = before, after = after })
            return
        end
        local key=tostring(name):lower()
        relock_generations[key]=(relock_generations[key] or 0)+1
        done(true, nil, { before = before, after = after, method = "SetSpawnedFlag(false)" })
    end)
    return scheduled, scheduled and "scheduled" or tostring(schedule_error)
end


-- A relock belongs to one spawn attempt, not to a spawner name forever.
local function arm_relock(name, delay, reason)
    local key=tostring(name):lower()
    local generation=(relock_generations[key] or 0)+1
    relock_generations[key]=generation
    return Native.schedule(delay,function()
        if relock_generations[key]~=generation then return end
        local current=find_spawner(name)
        if not current then return end
        local ok,why=set_spawner_disabled(current,true)
        report_guard(reason,{locked=ok and 1 or 0,failed=ok and 0 or 1,
            error=not ok and why or nil,spawners={spawner_detail(current)}})
    end)
end

function Native.trigger_spawner(name, relock_delay_ms, done)
    if type(done) ~= "function" then done = function() end end
    local scheduled, schedule_error = game_call(function()
        local spawner = find_spawner(name)
        if not spawner then done(false, "spawner_not_loaded") return end
        local before = spawner_detail(spawner)
        if not before or before.ground_resolved ~= true then
            set_spawner_disabled(spawner, true)
            done(false, "spawner_ground_unresolved", before)
            return
        end
        if before and before.spawned == true then
            set_spawner_disabled(spawner, true)
            done(false, "spawner_occupied", before)
            return
        end
        local delay = math.max(1000, math.min(30000, tonumber(relock_delay_ms) or 10000))
        local armed, arm_error = arm_relock(name, delay, "post_summon_relock")
        if not armed then done(false, arm_error, before) return end
        local unlocked, unlock_error = set_spawner_disabled(spawner, false)
        if not unlocked then done(false, unlock_error, before) return end
        pcall(function() spawner.RespawnTimer = 0.0 end)
        pcall(function() spawner.RespawnTime = 0.0 end)

        local shapes = {
            { "SpawnRequest_ByOutside(false)", function() return spawner:SpawnRequest_ByOutside(false) end },
            { "RespawnByOutside()", function() return spawner:RespawnByOutside() end },
        }
        local method, errors
        errors = {}
        for _, shape in ipairs(shapes) do
            local ok, result = pcall(shape[2])
            if ok then method = shape[1] break end
            errors[#errors + 1] = shape[1] .. ":" .. tostring(result)
        end
        if not method then
            set_spawner_disabled(spawner, true)
            done(false, table.concat(errors, " | "), before)
            return
        end

        local after = spawner_detail(spawner) or before or {}
        after.method = method
        after.relock_delay_ms = delay
        done(true, nil, after)
    end)
    return scheduled, scheduled and "scheduled" or tostring(schedule_error)
end

function Native.respawn_spawner(name, relock_delay_ms, done)
    if type(done) ~= "function" then done = function() end end
    local scheduled, schedule_error = game_call(function()
        local spawner = find_spawner(name)
        if not spawner then done(false, "spawner_not_loaded") return end
        local before = spawner_detail(spawner)
        if not before or before.ground_resolved ~= true then
            set_spawner_disabled(spawner, true)
            done(false, "spawner_ground_unresolved", { before = before })
            return
        end

        local locked, lock_error = set_spawner_disabled(spawner, true)
        if not locked then done(false, lock_error, { before = before }) return end
        local reset_ok, reset_error = call(spawner, "SetSpawnedFlag", false)
        if not reset_ok then
            done(false, tostring(reset_error or "SetSpawnedFlag unavailable"), { before = before })
            return
        end
        local reset = spawner_detail(spawner) or {}
        if reset.spawned ~= false then
            done(false, "spawned_flag_verification_failed", { before = before, reset = reset })
            return
        end
        pcall(function() spawner.RespawnTimer = 0.0 end)
        pcall(function() spawner.RespawnTime = 0.0 end)
        local delay = math.max(1000, math.min(30000, tonumber(relock_delay_ms) or 10000))
        local armed, arm_error = arm_relock(name, delay, "post_respawn_relock")
        if not armed then done(false, arm_error, before) return end
        local unlocked, unlock_error = set_spawner_disabled(spawner, false)
        if not unlocked then done(false, unlock_error, { before = before, reset = reset }) return end

        local shapes = {
            { "SpawnRequest_ByOutside(false)", function() return spawner:SpawnRequest_ByOutside(false) end },
            { "RespawnByOutside()", function() return spawner:RespawnByOutside() end },
        }
        local method, errors = nil, {}
        for _, shape in ipairs(shapes) do
            local fired, result = pcall(shape[2])
            if fired then method = shape[1] break end
            errors[#errors + 1] = shape[1] .. ":" .. tostring(result)
        end
        if not method then
            set_spawner_disabled(spawner, true)
            done(false, table.concat(errors, " | "), { before = before, reset = reset })
            return
        end

        local after = spawner_detail(spawner) or {}
        done(true, nil, {
            before = before, reset = reset, after = after,
            method = method, relock_delay_ms = delay,
        })
    end)
    return scheduled, scheduled and "scheduled" or tostring(schedule_error)
end

function Native.is_native_admin(uid)
    local controller = controller_of_state(find_state(uid))
    return controller ~= nil and member(controller, "bAdmin") == true
end

function Native.snapshot(species)
    local wanted, ids = tostring(species or ""):lower(), {}
    for _, pal in ipairs(loaded_pals()) do
        if wanted == "" or pal.species:lower() == wanted then ids[pal.id] = true end
    end
    return ids
end

function Native.new_pals(species, baseline)
    local wanted = tostring(species or ""):lower()
    baseline = type(baseline) == "table" and baseline or {}
    local out = {}
    for _, pal in ipairs(loaded_pals()) do
        if pal.species:lower() == wanted and not baseline[pal.id] then out[#out + 1] = detail(pal) end
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

function Native.inspect(id) return detail(find_pal(id)) end

function Native.is_alive(id)
    local pal = find_pal(id)
    if not pal then return false, "not_loaded" end
    local dead, source = dead_state(pal.character)
    if dead then return false, source end
    local controller = controller_of_character(pal.character)
    local authority_ok, authority = call(pal.character, "HasAuthority")
    local max_hp = call_number(pal.parameter_component, "GetMaxHP")
    local scale = call_vector(pal.character, "GetActorScale3D")
    local zero_scale = scale and math.abs(scale.x) < 0.0001
        and math.abs(scale.y) < 0.0001 and math.abs(scale.z) < 0.0001
    if authority_ok and authority == false and not valid(controller)
        and (max_hp == nil or max_hp <= 0) and zero_scale then
        return false, "despawned_shell"
    end
    return true, "loaded"
end

function Native.apply_scale(id, scale)
    local pal = find_pal(id)
    if not pal then return false, "pal_not_found" end
    local wanted = (tonumber(scale) or 1) + 0.0
    local ok, err = pcall(function()
        pal.character:SetActorScale3D({ X = wanted, Y = wanted, Z = wanted })
    end)
    return ok, ok and "SetActorScale3D" or tostring(err)
end

function Native.apply_profile(id, profile)
    local pal = find_pal(id)
    if not pal then return false, "pal_not_found" end
    profile = type(profile) == "table" and profile or {}
    local character, parameter, parameter_component = pal.character, pal.parameter, pal.parameter_component
    local static = member(character, "StaticCharacterParameterComponent")
    local controller = controller_of_character(character)
    local skill_slot = controller and member(controller, "SkillSlot") or nil
    local before = detail(pal) or {}
    -- Inspect the actual ID as well as the config flag: future override paths
    -- must not be able to replace RAID/GYM combat loadouts or double-designate.
    local prefix = tostring(pal.species or ""):match("^([^_]+)_") or ""
    local upper = prefix:upper()
    local special = profile.preserve_designation == true
    local preserve_active = profile.preserve_active_skills == true or upper == "RAID" or upper == "GYM"
    local steps, failed = {}, 0
    local function step(name, ok, why)
        if not ok then failed = failed + 1 end
        steps[#steps + 1] = name .. "=" .. (ok and "ok" or ("failed:" .. tostring(why or "unknown")))
        return ok
    end

    -- PalAISensor is the controller Blueprint component also used by Palladium.
    -- A missing component yields a profile diagnostic and cannot block spawning.
    local sight_ok, sight_result, sight_detail = pcall(function()
        local sensor=member(controller, "PalAISensor")
        if not valid(sensor) then
            local sensor_class=StaticFindObject("/Script/Pal.PalAISensorComponent")
            if valid(sensor_class) then
                local found,value=call(controller,"GetComponentByClass",sensor_class)
                if found then sensor=value end
                if not valid(sensor) then
                    found,value=call(character,"GetComponentByClass",sensor_class)
                    if found then sensor=value end
                end
            end
        end
        return SightPolicy.apply(sensor, {
            valid=valid, find_class=StaticFindObject, construct=StaticConstructObject, fname=FName,
        })
    end)
    step("player_sight", sight_ok and sight_result==true, sight_ok and sight_detail or sight_result)

    local active = {}
    for _, configured in ipairs(preserve_active and {} or (profile.active_skills or {})) do
        local value, canonical = WazaIds.resolve(configured)
        if value == nil then
            step("active_resolve_" .. tostring(configured), false, canonical)
        else
            active[#active + 1] = { id = value, name = canonical }
        end
    end
    if failed > 0 then
        return false, { steps = table.concat(steps, ";"), before = before, after = before }
    end

    local uncapturable_ok, uncapturable_error = call(parameter, "SetUncapturable", profile.uncapturable == true)
    step("uncapturable", uncapturable_ok, uncapturable_error)

    local spawned_type = profile.predator == true and 8 or 2
    if not special then
    local type_ok, type_error = call(static, "SetSpawnedCharacterType", spawned_type)
    step("spawned_type_" .. tostring(spawned_type), type_ok, type_error)
    local predator_ok, predator_error = set_member(parameter_component, "IsPredator", profile.predator == true)
    step("predator_flag", predator_ok, predator_error)
    end

    if #(profile.passive_skills or {}) > 0 then
        local old_ok, old_value = call(parameter, "GetPassiveSkillList")
        step("passive_read_before", old_ok, old_value)
        if old_ok then
            for _, old_name in ipairs(list_values(old_value, text_of)) do
                local old_fname, old_error = make_fname(old_name)
                if old_fname then
                    local ok, err = call(parameter, "RemovePassiveSkill", old_fname)
                    step("passive_remove_" .. old_name, ok, err)
                else
                    step("passive_remove_" .. old_name, false, old_error)
                end
            end
        end
        local none_name = make_fname("None")
        for _, configured in ipairs(profile.passive_skills or {}) do
            local fname, fname_error = make_fname(configured)
            if fname and none_name then
                local ok, err = call(parameter, "AddPassiveSkill", fname, none_name)
                step("passive_add_" .. configured, ok, err)
            else
                step("passive_add_" .. configured, false, fname_error or "None FName unavailable")
            end
        end
    end

    if #active > 0 then
        local clear_ok, clear_error = call(parameter, "ClearEquipWaza")
        step("active_clear", clear_ok, clear_error)
        for index, skill in ipairs(active) do
            local equip_ok, equip_error = call(parameter, "AddEquipWaza", skill.id)
            step("active_equip_" .. skill.name, equip_ok, equip_error)
            if valid(static) then call(static, "LoadWazaActionClass", skill.id) end
        end
    end

    local rep_ok, rep_error = call(parameter, "OnRep_SaveParameter")
    step("parameter_refresh", rep_ok, rep_error)
    for index, skill in ipairs(active) do
        local slot_ok, slot_error = call(skill_slot, "SetSkill", index - 1, skill.id)
        step("active_slot_" .. tostring(index - 1) .. "_" .. skill.name, slot_ok, slot_error)
    end

    local hp_rate = (tonumber(profile.hp_multiplier) or 1) + 0.0
    local attack_rate = (tonumber(profile.attack_multiplier) or 1) + 0.0
    local receive_rate = (tonumber(profile.receive_damage_rate) or 1) + 0.0
    local hp_ok, hp_error = set_member(parameter_component, "AdditionalEnemyMaxHPRate", hp_rate)
    step("enemy_max_hp_rate", hp_ok, hp_error)
    local attack_ok, attack_error = set_member(parameter_component, "AdditionalEnemyInflictDamageRate", attack_rate)
    step("enemy_inflict_rate", attack_ok, attack_error)
    local defense_ok, defense_error = set_member(parameter_component, "AdditionalEnemyReceiveDamageRate", receive_rate)
    step("enemy_receive_rate", defense_ok, defense_error)
    local recovery_ok, recovery_error = call(parameter, "FullRecoveryHP")
    step("full_recovery", recovery_ok, recovery_error)

    local wanted_scale = (tonumber(profile.scale) or 1) + 0.0
    local scale_ok, scale_error = pcall(function()
        character:SetActorScale3D({ X = wanted_scale, Y = wanted_scale, Z = wanted_scale })
    end)
    step("scale", scale_ok, scale_error)

    local after = detail(find_pal(id)) or {}
    local function close_enough(actual, expected)
        actual, expected = tonumber(actual), tonumber(expected)
        return actual and expected and math.abs(actual - expected) <= 0.0001
    end
    step("verify_uncapturable", after.uncapturable == (profile.uncapturable == true), after.uncapturable)
    if not special then
        step("verify_spawned_type", tonumber(after.spawned_type) == spawned_type, after.spawned_type)
        step("verify_predator_flag", after.is_predator == (profile.predator == true), after.is_predator)
    end
    step("verify_enemy_max_hp_rate", close_enough(after.enemy_hp_rate, hp_rate), after.enemy_hp_rate)
    step("verify_enemy_inflict_rate", close_enough(after.enemy_inflict_rate, attack_rate), after.enemy_inflict_rate)
    step("verify_enemy_receive_rate", close_enough(after.enemy_receive_rate, receive_rate), after.enemy_receive_rate)
    step("verify_scale", type(after.scale) == "table" and close_enough(after.scale.x, wanted_scale),
        type(after.scale) == "table" and after.scale.x or "unavailable")
    for _, skill in ipairs(active) do
        step("verify_active_" .. skill.name,
            tostring(after.equip_waza or ""):find(skill.name .. ":" .. tostring(skill.id), 1, true) ~= nil,
            after.equip_waza)
    end
    for _, passive in ipairs(profile.passive_skills or {}) do
        step("verify_passive_" .. passive,
            tostring(after.passive_skills or ""):find(passive, 1, true) ~= nil,
            after.passive_skills)
    end
    if hp_rate ~= 1 and tonumber(before.max_hp) and tonumber(after.max_hp) then
        step("verify_max_hp_changed", tonumber(before.max_hp) ~= tonumber(after.max_hp),
            tostring(before.max_hp) .. "->" .. tostring(after.max_hp))
    end
    return failed == 0, {
        steps = table.concat(steps, ";"), before = before, after = after,
        active = joined((function()
            local out = {} for _, skill in ipairs(active) do out[#out + 1] = skill.name .. ":" .. skill.id end
            return out
        end)()),
        passive = joined(profile.passive_skills or {}),
    }
end

-- Simple reflected scalar arguments only; never marshal FPalDeadInfo/save structs.
function Native.kill(id, done)
    done = type(done) == "function" and done or function() end
    local queued, err = game_call(function()
        local pal = find_pal(id)
        if not pal then done(false, "pal_not_loaded") return end
        local reaction = member(pal.character, "DamageReactionComponent")
        if not valid(reaction) or member(reaction, "SlipDamage") == nil then
            done(false, "kill_method_unavailable") return
        end
        local suppressed = set_member(pal.parameter_component, "CanDropItem", false)
        if not suppressed or member(pal.parameter_component, "CanDropItem") ~= false then
            done(false, "drop_suppression_failed") return
        end
        local ok, why = call(reaction, "SlipDamage", 2147483647, true, 10, true)
        if not ok then done(false, tostring(why or "SlipDamage failed")) return end
        local dead = dead_state(pal.character)
        done(dead == true, dead and nil or "death_not_confirmed")
    end)
    return queued, queued and "scheduled" or tostring(err)
end

local combat_lookup, combat_callback
local combat_hooks = {}
local function character_id(actor)
    actor=unwrap(actor)
    if not valid(actor) then return "" end
    local parameter=pal_parameter(actor)
    if parameter then return pal_id(parameter) end
    return ""
end
local function teammate(actor)
    local id=character_id(actor)
    return id~="" and combat_lookup and combat_lookup(id)==true
end
local function attacking_player(actor)
    actor=unwrap(actor)
    for _=1,4 do
        if not valid(actor) then return nil end
        local state=member(actor,"PlayerState")
        if not valid(state) then
            local controller=controller_of_character(actor)
            state=controller and member(controller,"PlayerState") or nil
        end
        local uid=valid(state) and state_uid(state) or ""
        if uid~="" then return uid end
        local parameter=pal_parameter(actor)
        if parameter then
            uid=guid_hex(member(member(parameter,"SaveParameter"),"OwnerPlayerUId"))
            if uid~="" then return uid end
        end
        local ok,owner=call(actor,"GetOwner")
        if not ok or not valid(owner) then ok,owner=call(actor,"GetInstigator") end
        actor=ok and owner or nil
    end
    return nil
end

function Native.share_aggro(ids,uid)
    local pawn=pawn_of_controller(controller_of_state(find_state(uid)))
    if not valid(pawn) then return false,"attacker_offline" end
    local changed,failed=0,0
    for _,id in ipairs(ids) do
        local pal=find_pal(id)
        if pal and not dead_state(pal.character) then
            local controller=controller_of_character(pal.character)
            local hate=controller and member(controller,"HateSystem") or nil
            if not valid(hate) then
                local ok,value=call(controller,"GetHateSystem")
                if ok then hate=value end
            end
            local target_ok=call(controller,"AddTargetPlayer_ForEnemy",pawn)
            local hate_ok=call(hate,"ChangeHate",pawn,1000000.0)
            if target_ok or hate_ok then changed=changed+1 else failed=failed+1 end
        end
    end
    return failed==0 and changed>0,"targets=" .. changed .. " failed=" .. failed
end

function Native.register_combat_hooks(lookup,callback)
    combat_lookup,combat_callback=lookup,callback
    if type(RegisterHook)~="function" then return false,"RegisterHook unavailable" end
    local function install(key,path,pre,post)
        if combat_hooks[key] then return end
        local ok=pcall(RegisterHook,path,pre,post)
        combat_hooks[key]=ok
    end
    install("damage","/Script/Pal.PalCharacterParameterComponent:OnDamage",function(context,result)
        local data=unwrap(result)
        local defender=member(data,"Defender")
        if not valid(defender) then
            local ok,owner=call(unwrap(context),"GetOwner")
            if ok then defender=owner end
        end
        if not teammate(defender) then return end
        local attacker=member(data,"Attacker")
        if teammate(attacker) then return end -- Never rally against our own roster.
        local damage=tonumber(member(data,"ActualDamage")) or tonumber(member(data,"Damage")) or 0
        if damage<=0 then return end
        local uid=attacking_player(attacker)
        if uid then
            local record={id=character_id(defender),player_uid=uid,damage=damage}
            Native.schedule(1,function()
                local ok,err=pcall(combat_callback,record)
                if not ok then print("[WorldBossFramework] damage callback failed: " .. tostring(err)) end
            end)
        end
    end)
    install("friend","/Script/Pal.PalUtility:IsFriend",function() end,function(_,a,b)
        if teammate(a) and teammate(b) then return true end
    end)
    install("enemy","/Script/Pal.PalUtility:IsEnemy",function() end,function(_,a,b)
        if teammate(a) and teammate(b) then return false end
    end)
    install("hate","/Script/Pal.PalHate:ChangeHate",function(context,attacker,amount)
        if not teammate(attacker) then return end
        if (tonumber(unwrap(amount)) or 0)<=0 then return end
        local hate=unwrap(context)
        local ok,owner=call(hate,"GetOuter")
        for _=1,3 do
            if not ok or not valid(owner) then return end
            local pawn=member(owner,"Pawn") or owner
            if teammate(pawn) then
                pcall(function() amount:set(0.0) end)
                return
            end
            ok,owner=call(owner,"GetOuter")
        end
    end)
    local all=true
    local out={}
    for _,key in ipairs({"damage","friend","enemy","hate"}) do
        all=all and combat_hooks[key]==true
        out[#out+1]=key .. "=" .. tostring(combat_hooks[key]==true)
    end
    return all,table.concat(out," ")
end

function Native.register_death_hook(callback)
    if death_hook_registered then return true, "already_registered" end
    if type(RegisterHook) ~= "function" then return false, "RegisterHook unavailable" end
    death_hook_callback = callback
    local result = { pcall(RegisterHook, "/Script/Pal.PalCharacter:OnDeadCharacter", function(context, dead_info)
        -- OnDeadCharacter's context is the character. The controller needs its
        -- identity only; do not materialize death-info or its attacker weak ref.
        local actor = unwrap(context)
        if not valid(actor) then return end
        local parameter = pal_parameter(actor)
        local id = parameter and pal_id(parameter) or ""
        if id == "" or type(death_hook_callback) ~= "function" then return end
        local record = {
            id = id, actor = object_name(actor),
            species = parameter and text_of(member(member(parameter, "SaveParameter"), "CharacterID")) or nil,
        }
        Native.schedule(1,function()
            local ok,err=pcall(death_hook_callback,record)
            if not ok then print("[WorldBossFramework] death callback failed: " .. tostring(err)) end
        end)
    end) }
    if not result[1] then return false, tostring(result[2]) end
    death_hook_registered = true
    return true, "registered"
end

function Native.register_capture_hook(callback)
    if capture_hook_registered then return true, "already_registered" end
    if type(RegisterHook) ~= "function" then return false, "RegisterHook unavailable" end
    capture_hook_callback = callback
    local function on_capture(context, attacker, monster)
        local actor = unwrap(monster)
        if not valid(actor) then actor = unwrap(attacker) end
        if not valid(actor) then return end
        local parameter = pal_parameter(actor)
        local id = parameter and pal_id(parameter) or ""
        if id == "" or type(capture_hook_callback) ~= "function" then return end
        local record = {
            id = id, actor = object_name(actor),
            species = parameter and text_of(member(member(parameter, "SaveParameter"), "CharacterID")) or nil,
            captor = object_name(unwrap(attacker)),
        }
        local function dispatch()
            local ok, err = pcall(capture_hook_callback, record)
            if not ok then print("[WorldBossFramework] capture callback failed: " .. tostring(err)) end
        end
        local ok, why = Native.schedule(1, dispatch)
        if not ok then print("[WorldBossFramework] capture dispatch failed: " .. tostring(why)) end
    end
    local result = { pcall(RegisterHook, "/Script/Pal.PalUtility:PalCaptureSuccess", on_capture) }
    if not result[1] then return false, tostring(result[2]) end
    capture_hook_registered = true
    return true, "registered"
end

return Native
