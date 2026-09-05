local Core = require("PalworldModCore").require_api(1)
local BossService = require("WorldBossFramework").require_api(1)

local source = (debug.getinfo(1, "S").source or ""):gsub("^@", "")
local mod_directory = source:match("^(.*[\\/])[^\\/]-$")
if not mod_directory then error("WorldBossFramework could not resolve its mod directory") end

local function load_helper(name)
    local chunk, err = loadfile(mod_directory .. name, "t", _ENV)
    if not chunk then error("WorldBossFramework could not load " .. name .. ": " .. tostring(err)) end
    return chunk()
end

local Native = load_helper("native.lua")
local SpawnerConfig = load_helper("spawner_config.lua")
local Encounter = load_helper("encounter.lua")
local Queue = load_helper("queue.lua")
local engine
local function dispatch_game(callback)
    if Native.on_game_thread then return Native.on_game_thread(callback) end
    callback()
    return true
end

local OWNER = "WorldBossFramework"
local VERSION = "0.7.1"
local SPAWNER_PREFIX = "WorldBossFramework_"
local RESPAWN_CHECK_INTERVAL_MS = 1000
local CONTROLLER_MAX_SLEEP_MS = 60000
-- Palladium's player.give_item capability accepts at most 9999 per request.
-- Larger configured rewards are ledger amounts and must be delivered in
-- capability-sized chunks.
local CLAIM_ITEM_CHUNK = 9999
local SHOP_REWARD_KIND = "worldboss_summon"
local PAL_SCHEMA_OUTPUT = mod_directory ..
    "../PalSchema/mods/WorldBossFramework/spawns/world_boss_spawners.json"

local active
local last_session
local blocked_spawners = {}
local sequence = 0
local ready_logged = false
local death_hook_logged = false
local capture_hook_logged = false
local combat_hook_logged = false
local current_pal
local controller_generation = 0
local controller_loaded = false
local controller_state
local fallback_controller_rows = {}
local fallback_reward_rows = {}
local claim_running = {}
local begin_summon
local controller_try_due
local sync_shop_integration

local function log(pal, message) Core.log(pal, OWNER, message) end

local function clean(value, limit)
    local text = tostring(value == nil and "unavailable" or value):gsub("[%c]", " "):gsub("%s+", " ")
    limit = tonumber(limit) or 160
    if #text > limit then text = text:sub(1, limit - 3) .. "..." end
    return text
end

local spawner_config, spawner_config_error = SpawnerConfig.load(mod_directory .. "spawners.config")
local config_write_ok, config_write_status = false, "not_attempted"
if spawner_config then
    config_write_ok, config_write_status = SpawnerConfig.write_if_changed(
        PAL_SCHEMA_OUTPUT, SpawnerConfig.render_palschema(spawner_config))
else
    config_write_status = spawner_config_error
end

local spawner_placements = {}
if spawner_config then
    for _, row in ipairs(spawner_config.list) do
        for _, member in ipairs(row.members) do
        spawner_placements[member.full_name:lower()] = {
            map_x = row.map_x, map_y = row.map_y,
            world_x = member.world_x, world_y = member.world_y,
            clearance = row.ground_clearance,
        }
        end
    end
end

local function scalar_map(data)
    if type(data) ~= "table" then return clean(data or "none", 400) end
    local keys, values = {}, {}
    for key, value in pairs(data) do
        if type(key) == "string" and type(value) ~= "table" and type(value) ~= "function" then
            keys[#keys + 1] = key
            values[key] = value
        end
    end
    for _, entry in ipairs(data) do
        if type(entry) == "table" and type(entry[1]) == "string"
            and type(entry[2]) ~= "table" and type(entry[2]) ~= "function" then
            if values[entry[1]] == nil then keys[#keys + 1] = entry[1] end
            values[entry[1]] = entry[2]
        end
    end
    table.sort(keys)
    local out = {}
    for _, key in ipairs(keys) do out[#out + 1] = key .. "=" .. clean(values[key], 180) end
    return #out > 0 and table.concat(out, " ") or "none"
end

local function vector_text(value)
    if type(value) ~= "table" then return "unavailable" end
    return string.format("%.2f,%.2f,%.2f",
        tonumber(value.x or value.X) or 0,
        tonumber(value.y or value.Y) or 0,
        tonumber(value.z or value.Z) or 0)
end

local function horizontal_distance(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return nil end
    local ax, ay = tonumber(a.x or a.X), tonumber(a.y or a.Y)
    local bx, by = tonumber(b.x or b.X), tonumber(b.y or b.Y)
    if not ax or not ay or not bx or not by then return nil end
    local dx, dy = ax - bx, ay - by
    return math.sqrt(dx * dx + dy * dy)
end

local function number(value, minimum, maximum, fallback)
    value = tonumber(value)
    if not value or value ~= value then return fallback end
    if minimum and value < minimum then return fallback end
    if maximum and value > maximum then return fallback end
    return value
end

local function tell(pal, who, text)
    if who and pal and pal.player then pal.player.message(who, { text = clean(text, 500) }) end
end

local function configured_admin(pal, who)
    local configured = pal.settings.administrator_uids
    if type(configured) ~= "table" then return false end
    local wanted = tostring(who or ""):upper()
    for _, value in pairs(configured) do
        local uid = type(value) == "table" and (value.uid or value.id) or value
        if tostring(uid or ""):upper() == wanted then return true end
    end
    return false
end

local function may_administer(pal, event, who, mode)
    if pal.can and pal.can(who, "worldbossframework.admin", { mode = mode }) then
        return true, "palladium_permission"
    end
    local ok, native = pcall(Native.is_native_admin, who)
    if ok and native == true then return true, "native_admin" end
    if configured_admin(pal, who) then return true, "configured_uid" end
    local role = event.subject and tostring(event.subject.role or ""):upper() or ""
    if role == "ADMINS" then return true, "palladium_admin_role" end
    return false, "not_authorized"
end

local function session_label(session) return session and tostring(session.token) or "none" end

local function configured_spawner(id)
    if not spawner_config then return nil end
    return spawner_config.by_id[tostring(id or ""):lower()]
end

local function controller_settings(pal)
    local raw = type(pal.settings.controller) == "table" and pal.settings.controller or {}
    return {
        enabled = raw.enabled == true and pal.settings.enabled ~= false
            and pal.settings.probe_enabled == true,
        spawn_interval_seconds = math.floor(number(raw.spawn_interval_seconds, 1, 2592000, 7200)),
        initial_delay_seconds = math.floor(number(raw.initial_delay_seconds, 1, 2592000, 900)),
        due_retry_seconds = math.floor(number(raw.due_retry_seconds, 1, 300, 1)),
        recovery_delay_seconds = math.floor(number(raw.recovery_delay_seconds, 1, 3600, 30)),
        count_server_downtime = raw.count_server_downtime == true,
        queue_order = ({ascending=true,descending=true,random=true})[raw.queue_order] and raw.queue_order or "ascending",
    }
end

local function controller_store(pal)
    if pal and pal.data ~= nil then
        local ok, store = pcall(pal.data, "controller_state")
        if ok and type(store) == "table" then return store end
    end
    return {
        get = function(_, key) return fallback_controller_rows[key] end,
        set = function(_, key, value) fallback_controller_rows[key] = value return true end,
    }
end

local function reward_store(pal)
    if pal and pal.data ~= nil then
        local ok, store = pcall(pal.data, "reward_claims")
        if ok and type(store) == "table" then return store end
    end
    return {
        get = function(_, key) return fallback_reward_rows[key] end,
        set = function(_, key, value) fallback_reward_rows[key] = value return true end,
        all = function()
            local out = {}
            for key, value in pairs(fallback_reward_rows) do
                local row = {}
                for field, item in pairs(value) do row[field] = item end
                row.key = row.key or key
                out[#out + 1] = row
            end
            return out
        end,
    }
end

local function reward_rows(store)
    if type(store) ~= "table" or type(store.all) ~= "function" then return {} end
    local ok, rows = pcall(function() return store:all() end)
    if not ok or type(rows) ~= "table" then return {} end
    local out = {}
    for key, value in pairs(rows) do
        if type(value) == "table" then
            local row = {}
            for field, item in pairs(value) do row[field] = item end
            row.key = row.key or (type(key) == "string" and key or nil)
            out[#out + 1] = row
        end
    end
    table.sort(out, function(a, b)
        return tostring(a.created_at or a.key or "") < tostring(b.created_at or b.key or "")
    end)
    return out
end

local function split_queue(value)
    local out = {}
    for id in tostring(value or ""):gmatch("[^,]+") do out[#out + 1] = id end
    return out
end

local function automatic_ids()
    local out = {}
    for _, configured in ipairs(spawner_config and spawner_config.list or {}) do
        if configured.auto_enabled then out[#out + 1] = configured.id end
    end
    return out
end

local function reconcile_queue(queue)
    local allowed, seen, out = {}, {}, {}
    for _, id in ipairs(automatic_ids()) do allowed[id:lower()] = id end
    for _, id in ipairs(queue or {}) do
        local canonical = allowed[tostring(id):lower()]
        if canonical and not seen[canonical] then seen[canonical]=true out[#out+1]=canonical end
    end
    return out
end

local function fresh_queue(pal)
    return Queue.build(spawner_config and spawner_config.list or {},controller_settings(pal).queue_order)
end

local function controller_remaining(now)
    if not controller_state then return nil end
    now = now or os.time()
    if controller_state.mode == "countdown" then
        return math.max(0, (tonumber(controller_state.deadline_at) or now) - now)
    end
    if controller_state.mode == "due_waiting" or controller_state.mode == "spawning_auto" then return 0 end
    if controller_state.mode == "spawning_external" or controller_state.mode == "active_external" then
        return math.max(0, tonumber(controller_state.paused_remaining) or 0)
    end
    return nil
end

local function duration_text(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    local days, hours, minutes = math.floor(seconds / 86400), math.floor(seconds % 86400 / 3600),
        math.floor(seconds % 3600 / 60)
    local parts = {}
    if days > 0 then parts[#parts + 1] = days .. "d" end
    if hours > 0 then parts[#parts + 1] = hours .. "h" end
    if minutes > 0 then parts[#parts + 1] = minutes .. "m" end
    if #parts == 0 or (#parts < 2 and seconds % 60 > 0) then parts[#parts + 1] = (seconds % 60) .. "s" end
    return table.concat(parts, " ")
end

local function title_service()
    local ok, service = pcall(require, "PlayerTitleFramework")
    if not ok or type(service) ~= "table" or type(service.ready) ~= "function" then return nil end
    local ready_ok, ready = pcall(service.ready)
    if not ready_ok or ready ~= true or type(service.get) ~= "function"
        or type(service.title_name) ~= "function" then return nil end
    return service
end

local function server_shop_service(require_ready)
    local ok, service = pcall(require, "ServerShopFramework")
    if not ok or type(service) ~= "table" or type(service.require_api) ~= "function" then return nil end
    local api_ok, api = pcall(service.require_api, 1)
    if not api_ok or type(api) ~= "table" then return nil end
    if require_ready then
        if type(api.ready) ~= "function" then return nil end
        local ready_ok, ready = pcall(api.ready)
        if not ready_ok or ready ~= true then return nil end
    end
    return api
end

local function player_announcement_name(pal, player)
    local name = clean(player.name or player.uid, 64)
    local service = title_service()
    if not service then return name end
    local ok, titles = pcall(service.get, player.uid)
    if not ok or type(titles) ~= "table" then return name end
    local active = clean(titles.active, 96)
    if active == "" then return name end
    local name_ok, display = pcall(service.title_name, active)
    if not name_ok or display == nil or clean(display, 64) == "" then return name end
    return "[" .. clean(display, 64) .. "]" .. name
end

local function grant_first_defeat_title(pal, configured, player)
    local title_id = configured and configured.first_defeat_title
    if not title_id then return false end
    local service = title_service()
    if not service then
        log(pal, "titles: first-defeat title unavailable; PlayerTitleFramework API 1 is not ready")
        return false
    end
    local ok, granted, reason = pcall(service.grant, player.uid, title_id, {
        name = player.name, source = "WorldBossFramework:" .. configured.id,
    })
    if not ok then
        log(pal, "titles: first-defeat grant failed player=" .. clean(player.uid, 64) ..
            " title=" .. clean(title_id, 96) .. " error=" .. clean(granted, 180))
        return false
    end
    if granted == true then
        log(pal, "titles: first-defeat title granted player=" .. clean(player.uid, 64) ..
            " title=" .. clean(title_id, 96))
        return true
    end
    if reason ~= "already_owned" then
        log(pal, "titles: first-defeat grant rejected player=" .. clean(player.uid, 64) ..
            " title=" .. clean(title_id, 96) .. " reason=" .. clean(reason, 180))
    end
    return false
end

local function announcement_template(pal, kind)
    local configured = type(pal.settings.announcements) == "table" and pal.settings.announcements or {}
    if kind == "spawn" then
        return configured.spawn or "[Boss Title] (Lv.[Level]) has appeared at map [Map X], [Map Y]!"
    end
    return configured.defeat or "[Boss Title] has been defeated! Next world boss in [Next Spawn]."
end

local function render_announcement(pal, kind, configured, remaining)
    local message = tostring(announcement_template(pal, kind))
    local replacements = {
        { "%[Boss Title%]", configured.title },
        { "%[Level%]", tostring(configured.level) },
        { "%[Map X%]", string.format("%.0f", configured.map_x) },
        { "%[Map Y%]", string.format("%.0f", configured.map_y) },
        { "%[Spawner%]", configured.id },
        { "%[Next Spawn%]", remaining == nil and "automatic timer disabled" or duration_text(remaining) },
    }
    for _, pair in ipairs(replacements) do
        message = message:gsub(pair[1], function() return tostring(pair[2] or "") end)
    end
    return clean(message, 500)
end

local function emit_service(pal, event_type, session, extra)
    local event_spawner = session and session.spawner_id or (extra and extra.spawner_id)
    local configured = configured_spawner(event_spawner)
    local data = {
        token = session and session.token or nil,
        spawner_id = event_spawner,
        title = configured and configured.title or nil,
        source = session and session.source or (extra and extra.source),
    }
    for key, value in pairs(extra or {}) do data[key] = value end
    BossService.emit(event_type, {
        type = event_type, at = os.time(),
        subject = { kind = "worldboss", id = data.spawner_id or "controller", name = data.title or "World Boss" },
        data = data,
    }, function(owner, err)
        log(pal, string.format("service subscriber %s failed during %s: %s", owner, event_type, clean(err, 200)))
    end)
end

local function broadcast(pal, kind, configured, remaining, source)
    if not pal or not pal.server or type(pal.server.announce) ~= "function" then
        log(pal, "announcement failed: server.announce unavailable")
        return false
    end
    local message = render_announcement(pal, kind, configured, remaining)
    pal.server.announce({ message = message }, function(ok, err)
        log(pal, string.format("world boss announcement: kind=%s spawner=%s source=%s result=%s message=%s detail=%s",
            kind, configured.id, clean(source, 32), ok and "sent" or "failed", clean(message, 500), clean(err or "none", 160)))
    end)
    return true
end

local function recipient_list(session)
    local recipients = session and session.reward_recipients or {}
    local out = {}
    for _, name in ipairs(recipients) do out[#out + 1] = clean(name, 120) end
    return out
end

local function join_recipients(recipients)
    if #recipients == 0 then return "" end
    if #recipients == 1 then return recipients[1] end
    if #recipients == 2 then return recipients[1] .. " and " .. recipients[2] end
    return table.concat(recipients, ", ", 1, #recipients - 1) .. ", and " .. recipients[#recipients]
end

local function broadcast_defeat(pal, configured, session, remaining, source)
    if not pal or not pal.server or type(pal.server.announce) ~= "function" then
        log(pal, "announcement failed: server.announce unavailable")
        return false
    end
    local recipients = recipient_list(session)
    local message = "World boss " .. clean(configured.title, 128) .. " has been defeated"
    if #recipients > 0 then message = message .. " by " .. join_recipients(recipients) end
    message = clean(message .. "!", 500)
    local function announce_next()
        local next_message = remaining == nil
            and "Next world boss timer is disabled."
            or "Next world boss appears in (" .. duration_text(remaining) .. ")."
        next_message = clean(next_message, 500)
        pal.server.announce({ message = next_message }, function(ok, err)
            log(pal, string.format("world boss announcement: kind=next_spawn spawner=%s source=%s result=%s message=%s detail=%s",
                configured.id, clean(source, 32), ok and "sent" or "failed",
                next_message, clean(err or "none", 160)))
        end)
    end
    pal.server.announce({ message = message }, function(ok, err)
        log(pal, string.format("world boss announcement: kind=defeat_by spawner=%s source=%s result=%s message=%s detail=%s",
            configured.id, clean(source, 32), ok and "sent" or "failed", message, clean(err or "none", 160)))
        announce_next()
    end)
    return true
end

local function complete_defeat_announcement(session)
    if not session or session.completion_announcement_sent
        or not session.completion_announcement then return end
    session.completion_announcement_sent = true
    local announcement = session.completion_announcement
    broadcast_defeat(announcement.pal, announcement.configured, session,
        announcement.remaining, announcement.source)
end

local function resolve_recipient_names(pal, session, players)
    session.reward_recipients = {}
    if #players == 0 then
        session.reward_recipients_ready = true
        complete_defeat_announcement(session)
        return
    end
    session.reward_recipients_ready = false
    local remaining = #players
    local resolved = {}
    local function finish(index, player, name)
        if resolved[index] then return end
        resolved[index] = true
        session.reward_recipients[index] = player_announcement_name(pal, {
            uid = player.uid, name = name or player.name or player.uid,
        })
        remaining = remaining - 1
        if remaining == 0 then
            session.reward_recipients_ready = true
            complete_defeat_announcement(session)
        end
    end
    for index, player in ipairs(players) do
        local done_called = false
        local function done(ok, _, data)
            if done_called then return end
            done_called = true
            local name = ok and type(data) == "table" and data.name or nil
            finish(index, player, name)
        end
        if pal and pal.player and type(pal.player.playtime) == "function" then
            local ok, err = pcall(pal.player.playtime, player.uid, {}, done)
            if not ok then
                log(pal, "rewards: player name lookup failed uid=" .. clean(player.uid, 64) ..
                    " error=" .. clean(err, 180))
                done(false, err)
            end
        else
            finish(index, player, player.name or player.uid)
        end
    end
end

local function save_controller(pal)
    if not controller_state then return false end
    controller_state.updated_at = os.time()
    local row = {
        mode = tostring(controller_state.mode or "disabled"),
        queue = table.concat(controller_state.queue or {}, ","),
        deadline_at = tostring(math.floor(tonumber(controller_state.deadline_at) or 0)),
        checkpoint_remaining = tostring(math.floor(tonumber(controller_state.checkpoint_remaining) or 0)),
        paused_remaining = tostring(math.floor(tonumber(controller_state.paused_remaining) or 0)),
        due_spawner = tostring(controller_state.due_spawner or ""),
        active_spawner = tostring(controller_state.active_spawner or ""),
        active_source = tostring(controller_state.active_source or ""),
        announced_due = controller_state.announced_due and "true" or "false",
        updated_at = tostring(controller_state.updated_at),
    }
    local ok = controller_store(pal):set("global", row)
    if not ok then log(pal, "controller state write failed") end
    return ok == true
end

local function queue_remove(id)
    if not controller_state then return end
    local out = {}
    for _, queued in ipairs(controller_state.queue or {}) do
        if tostring(queued):lower() ~= tostring(id):lower() then out[#out + 1] = queued end
    end
    controller_state.queue = out
end

local function queue_prepend(id)
    if not id or id == "" then return end
    queue_remove(id)
    table.insert(controller_state.queue, 1, id)
end

local function queue_rotate(id)
    queue_remove(id)
    -- Consumed entries stay out until the next round. The remaining order is persisted.
end

local controller_tick
local function schedule_controller(pal)
    if not controller_loaded or not controller_state then return false end
    local settings = controller_settings(pal)
    if not settings.enabled or active
        or controller_state.mode == "disabled" or controller_state.mode:match("^active_")
        or controller_state.mode:match("^spawning_") then return false end
    controller_generation = controller_generation + 1
    local generation = controller_generation
    local delay = settings.due_retry_seconds * 1000
    if controller_state.mode == "countdown" then
        local remaining = controller_remaining(os.time()) or settings.spawn_interval_seconds
        delay = math.max(1, math.min(CONTROLLER_MAX_SLEEP_MS, remaining * 1000))
    end
    local queued, reason = Native.schedule(delay, function()
        if generation ~= controller_generation then return end
        controller_tick(pal, "scheduled")
    end)
    if not queued then log(pal, "controller wake schedule failed: " .. clean(reason, 200)) end
    return queued
end

local function start_countdown(pal, seconds, reason)
    local now = os.time()
    if #controller_state.queue == 0 then controller_state.queue = fresh_queue(pal) end
    controller_state.mode = "countdown"
    controller_state.deadline_at = now + math.max(1, math.floor(seconds))
    controller_state.checkpoint_remaining = math.max(1, math.floor(seconds))
    controller_state.paused_remaining = 0
    controller_state.due_spawner = ""
    controller_state.active_spawner = ""
    controller_state.active_source = ""
    controller_state.announced_due = false
    save_controller(pal)
    log(pal, string.format("controller countdown: reason=%s remaining=%d deadline=%d queue=%s",
        clean(reason, 48), seconds, controller_state.deadline_at, table.concat(controller_state.queue, ",")))
    emit_service(pal, "worldboss.timer_started", nil, { remaining_seconds = seconds, reason = reason })
    schedule_controller(pal)
end

local function controller_pause_for_session(pal, session)
    local settings = controller_settings(pal)
    if not settings.enabled then return true end
    if session.source == "automatic" then
        controller_state.mode = "spawning_auto"
        controller_state.active_spawner = session.spawner_id
        controller_state.active_source = session.source
    else
        controller_state.paused_remaining = controller_remaining(os.time())
            or controller_state.checkpoint_remaining or settings.spawn_interval_seconds
        controller_state.mode = "spawning_external"
        controller_state.active_spawner = session.spawner_id
        controller_state.active_source = session.source
        emit_service(pal, "worldboss.timer_paused", session, {
            remaining_seconds = controller_state.paused_remaining,
        })
    end
    controller_generation = controller_generation + 1
    save_controller(pal)
    return true
end

local function controller_session_spawned(pal, session)
    if not controller_state then return end
    if session.source == "automatic" then
        if not session.queue_rotated then
            queue_rotate(session.spawner_id)
            session.queue_rotated = true
        end
        controller_state.mode = "active_auto"
    else
        controller_state.mode = "active_external"
    end
    controller_state.active_spawner = session.spawner_id
    controller_state.active_source = session.source
    save_controller(pal)
    if not session.announcement_sent then
        broadcast(pal, "spawn", configured_spawner(session.spawner_id), nil, session.source)
        session.announcement_sent = true
    end
    emit_service(pal, "worldboss.spawned", session, { level = session.level })
end

local function terminal_completion(reason)
    return reason == "death_event" or reason == "capture_event" or reason == "confirmed_dead_state"
end

local function seed_rewards(pal, session, reason)
    if session.suppress_rewards or not terminal_completion(reason) or session.rewards_seeded then return end
    session.rewards_seeded = true
    local configured = configured_spawner(session.spawner_id)
    if not configured or (#configured.rewards == 0 and not configured.first_defeat_title) then
        log(pal, "rewards: no configured reward rows for encounter " .. session_label(session))
        return
    end
    local nearby, why = Native.players_near(session.location, configured.match_radius)
    local candidates = nearby and nearby.players or {}
    if not nearby then
        log(pal, "rewards: arena snapshot failed token=" .. session_label(session) .. " reason=" .. clean(why, 160))
        session.rewards_seeded = false
        return
    end
    local store = reward_store(pal)
    local created_at = os.time()
    local awarded_players, awarded_rows = 0, 0
    session.reward_recipients = {}
    session.reward_recipients_ready = true
    local notified = {}
    local recipient_players = {}
    for _, player in ipairs(candidates) do
        local player_awarded = false
        for _, reward in ipairs(configured.rewards) do
            local key = table.concat({ tostring(player.uid), tostring(session.reward_id), tostring(reward.index) }, "|")
            if (reward.chance >= 1.0 or (reward.chance > 0.0 and math.random() < reward.chance))
                and not store:get(key) then
                local record = {
                    key = key, uid = player.uid, encounter = session.reward_id,
                    spawner = configured.id, title = configured.title,
                    reward_index = reward.index, kind = reward.kind or "item", item = reward.item or "",
                    awarded = reward.count, delivered = 0, status = "pending",
                    created_at = created_at, updated_at = created_at,
                }
                local ok = store:set(key, record)
                if ok ~= false then
                    awarded_rows = awarded_rows + 1
                    player_awarded = true
                else
                    log(pal, "rewards: ledger write failed key=" .. clean(key, 180))
                end
            end
        end
        local title_awarded = grant_first_defeat_title(pal, configured, player)
        if player_awarded or title_awarded then
            awarded_players = awarded_players + 1
            recipient_players[#recipient_players + 1] = player
            if not notified[player.uid] then
                notified[player.uid] = true
                if player_awarded then
                    tell(pal, player.uid, "World boss rewards are waiting. Use !worldboss claim to collect them.")
                else
                    tell(pal, player.uid, "Your world boss title reward is ready. Use !titlerewards to manage it.")
                end
            end
        end
    end
    log(pal, string.format("rewards: snapshot token=%s radius=%.1f eligible=%d awarded_players=%d awarded_rows=%d",
        session_label(session), configured.match_radius, #candidates, awarded_players, awarded_rows))
    resolve_recipient_names(pal, session, recipient_players)
end

local function claim_rewards(pal, who)
    if claim_running[who] then
        tell(pal, who, "A world boss reward claim is already being processed.")
        return
    end
    local store = reward_store(pal)
    local pending = {}
    for _, row in ipairs(reward_rows(store)) do
        local awarded, delivered = tonumber(row.awarded) or 0, tonumber(row.delivered) or 0
        if tostring(row.uid or ""):upper() == tostring(who):upper() and awarded > delivered then
            pending[#pending + 1] = row
        end
    end
    if #pending == 0 then
        tell(pal, who, "You have no unclaimed world boss rewards.")
        return
    end
    claim_running[who] = true
    local index, delivered_total, completed_rows = 1, 0, 0
    local function finish()
        claim_running[who] = nil
        local left = 0
        for _, row in ipairs(reward_rows(store)) do
            if tostring(row.uid or ""):upper() == tostring(who):upper()
                and (tonumber(row.awarded) or 0) > (tonumber(row.delivered) or 0) then left = left + 1 end
        end
        tell(pal, who, string.format("World boss claim delivered %d reward unit(s) across %d reward(s).%s",
            delivered_total, completed_rows, left > 0 and " Some rewards remain pending; use !worldboss claim again." or ""))
    end
    local function next_row()
        local row = pending[index]
        index = index + 1
        if not row then finish() return end
        local awarded, delivered = tonumber(row.awarded) or 0, tonumber(row.delivered) or 0
        local remaining = math.max(0, math.floor(awarded - delivered))
        if remaining == 0 then next_row() return end
        row.status, row.updated_at = "delivering", os.time()
        if store:set(row.key, row) == false then next_row() return end

        local kind = tostring(row.kind or "item"):lower()
        if kind == "currency" then
            local shop = server_shop_service(true)
            if not shop or type(shop.add) ~= "function" then
                row.status, row.error, row.updated_at = "pending", "shop currency service unavailable", os.time()
                store:set(row.key, row)
                next_row()
                return
            end
            local idempotency_key = table.concat({
                OWNER, tostring(row.encounter or row.key or "unknown"),
                tostring(row.reward_index or 0),
            }, ":")
            local called, granted, balance_or_error = pcall(shop.add, who, remaining, {
                idempotency_key = idempotency_key,
                source = OWNER,
                reason = "world boss reward: " .. tostring(row.spawner or "unknown"),
                player_name = who,
            })
            if called and granted == true then
                row.delivered = awarded
                row.status, row.error, row.updated_at = "delivered", "", os.time()
                if store:set(row.key, row) ~= false then
                    delivered_total = delivered_total + remaining
                    completed_rows = completed_rows + 1
                end
            else
                row.status = "pending"
                row.error = tostring(called and balance_or_error or granted or "currency delivery failed")
                row.updated_at = os.time()
                store:set(row.key, row)
            end
            next_row()
            return
        elseif kind ~= "item" then
            row.status, row.error, row.updated_at = "pending", "unsupported reward kind: " .. kind, os.time()
            store:set(row.key, row)
            next_row()
            return
        elseif not pal.player or type(pal.player.give_item) ~= "function" then
            row.status, row.error, row.updated_at = "pending", "item delivery unavailable", os.time()
            store:set(row.key, row)
            next_row()
            return
        end

        local function deliver_chunk(delivered_so_far, remaining_so_far)
            if remaining_so_far <= 0 then
                row.delivered = delivered_so_far
                row.status, row.error, row.updated_at = "delivered", "", os.time()
                if store:set(row.key, row) ~= false then
                    completed_rows = completed_rows + 1
                end
                next_row()
                return
            end

            local requested = math.min(remaining_so_far, CLAIM_ITEM_CHUNK)
            local called = false
            local function result(ok, err, data)
                if called then return end
                called = true
                local gained = ok and tonumber(data and data.gained) or nil
                if ok and gained == nil then gained = requested end
                gained = math.max(0, math.min(requested, math.floor(gained or 0)))
                local total = delivered_so_far + gained
                delivered_total = delivered_total + gained
                row.delivered, row.updated_at = total, os.time()

                if gained < requested then
                    row.status = gained > 0 and "partial" or "pending"
                    row.error = tostring(err or "inventory did not accept the full amount")
                    store:set(row.key, row)
                    next_row()
                    return
                end

                if total >= awarded then
                    row.status, row.error = "delivered", ""
                    store:set(row.key, row)
                    completed_rows = completed_rows + 1
                    next_row()
                    return
                end

                row.status, row.error = "pending", ""
                if store:set(row.key, row) == false then
                    next_row()
                    return
                end
                deliver_chunk(total, awarded - total)
            end
            local ok, err = pcall(pal.player.give_item, who,
                { item = row.item, count = requested }, result)
            if not ok then result(false, tostring(err)) end
        end
        deliver_chunk(delivered, remaining)
    end
    next_row()
end

local function controller_session_finished(pal, session, reason)
    if not controller_state then return end
    if session.source == "automatic" and not session.queue_rotated then
        queue_rotate(session.spawner_id)
        session.queue_rotated = true
    end
    local settings = controller_settings(pal)
    local completed = not session.suppress_rewards and terminal_completion(reason)
    local remaining
    if settings.enabled then
        local reset_schedule = session.source == "automatic" or reason == "admin_kill"
            or (session.reset_schedule == true and completed)
        if reset_schedule then
            remaining = settings.spawn_interval_seconds
        else
            remaining = math.max(1, tonumber(controller_state.paused_remaining)
                or settings.spawn_interval_seconds)
        end
        local countdown_source = session.source == "automatic" and "automatic_defeat"
            or (session.reset_schedule == true and completed and "external_reset" or "external_resume")
        start_countdown(pal, remaining, countdown_source)
        if session.source ~= "automatic" then
            emit_service(pal, "worldboss.timer_resumed", session, { remaining_seconds = remaining })
        end
    else
        controller_state.mode = "disabled"
        controller_state.active_spawner, controller_state.active_source = "", ""
        save_controller(pal)
    end
    if reason == "admin_kill" then
        emit_service(pal, "worldboss.cancelled", session, { reason=reason, rewards_suppressed=true })
    end
    if completed then
        session.completion_announcement = {
            pal = pal, configured = configured_spawner(session.spawner_id),
            remaining = remaining, source = session.source,
        }
        if session.reward_recipients_ready ~= false then complete_defeat_announcement(session) end
        emit_service(pal, "worldboss.defeated", session, {
            reason = reason, next_spawn_seconds = remaining,
        })
    end
end

local function controller_expire(pal)
    local id = controller_state.queue and controller_state.queue[1]
    local configured = configured_spawner(id)
    if not configured then
        controller_state.queue = fresh_queue(pal)
        id = controller_state.queue[1]
        configured = configured_spawner(id)
    end
    if not configured then
        controller_state.mode = "no_queue"
        save_controller(pal)
        log(pal, "controller due with no automatic world boss spawners configured")
        return false
    end
    controller_state.mode = "due_waiting"
    controller_state.due_spawner = configured.id
    controller_state.deadline_at = 0
    controller_state.checkpoint_remaining = 0
    controller_state.announced_due = true
    save_controller(pal)
    broadcast(pal, "spawn", configured, nil, "automatic_timer")
    emit_service(pal, "worldboss.timer_elapsed", nil, {
        spawner_id = configured.id, source = "automatic", level = configured.level,
        map_x = configured.map_x, map_y = configured.map_y,
    })
    log(pal, string.format("controller timer elapsed: spawner=%s title=%s level=%d map=%.0f,%.0f state=due_waiting announcement=sent",
        configured.id, clean(configured.title, 128), configured.level, configured.map_x, configured.map_y))
    return true
end

controller_tick = function(pal, reason)
    if not controller_loaded or not controller_state then return end
    local settings = controller_settings(pal)
    if not settings.enabled then
        controller_state.mode = "disabled"
        save_controller(pal)
        return
    end
    if controller_state.mode == "disabled" or controller_state.mode == "no_queue" then
        controller_state.queue = fresh_queue(pal)
        if #controller_state.queue == 0 then
            controller_state.mode = "no_queue"
            save_controller(pal)
            return
        end
        start_countdown(pal, settings.initial_delay_seconds, "controller_enabled")
        return
    end
    if active then return end
    if controller_state.mode == "countdown" then
        local remaining = controller_remaining(os.time()) or 0
        controller_state.checkpoint_remaining = remaining
        save_controller(pal)
        if remaining <= 0 then controller_expire(pal) end
    end
    if controller_state.mode == "due_waiting" then
        if os.time() >= (tonumber(controller_state.retry_not_before) or 0) then
            controller_try_due(pal, reason or "controller_tick")
        end
    end
    schedule_controller(pal)
end

local function initialize_controller(pal)
    if controller_loaded then return end
    controller_loaded = true
    local settings = controller_settings(pal)
    local saved = controller_store(pal):get("global")
    local now = os.time()
    if type(saved) == "table" then
        controller_state = {
            mode = tostring(saved.mode or "countdown"),
            queue = reconcile_queue(split_queue(saved.queue)),
            deadline_at = tonumber(saved.deadline_at) or 0,
            checkpoint_remaining = tonumber(saved.checkpoint_remaining) or settings.initial_delay_seconds,
            paused_remaining = tonumber(saved.paused_remaining) or 0,
            due_spawner = tostring(saved.due_spawner or ""),
            active_spawner = tostring(saved.active_spawner or ""),
            active_source = tostring(saved.active_source or ""),
            announced_due = tostring(saved.announced_due) == "true",
        }
        if controller_state.mode == "active_auto" or controller_state.mode == "spawning_auto" then
            queue_prepend(controller_state.active_spawner ~= "" and controller_state.active_spawner
                or controller_state.due_spawner)
            controller_state.mode = "countdown"
            controller_state.deadline_at = now + settings.recovery_delay_seconds
            controller_state.checkpoint_remaining = settings.recovery_delay_seconds
            controller_state.active_spawner, controller_state.active_source = "", ""
            controller_state.due_spawner, controller_state.announced_due = "", false
            log(pal, "controller recovered interrupted automatic encounter; spawner returned to queue head")
        elseif controller_state.mode == "active_external" or controller_state.mode == "spawning_external" then
            controller_state.mode = "countdown"
            controller_state.deadline_at = now + math.max(1, controller_state.paused_remaining)
            controller_state.checkpoint_remaining = math.max(1, controller_state.paused_remaining)
            controller_state.active_spawner, controller_state.active_source = "", ""
            log(pal, "controller recovered interrupted external encounter; paused timer resumed")
        elseif controller_state.mode == "countdown" and not settings.count_server_downtime then
            controller_state.deadline_at = now + math.max(1, controller_state.checkpoint_remaining)
        end
    else
        controller_state = {
            mode = settings.enabled and "countdown" or "disabled",
            queue = fresh_queue(pal),
            deadline_at = now + settings.initial_delay_seconds,
            checkpoint_remaining = settings.initial_delay_seconds,
            paused_remaining = 0, due_spawner = "", active_spawner = "", active_source = "",
            announced_due = false,
        }
    end
    if not settings.enabled then controller_state.mode = "disabled" end
    save_controller(pal)
    log(pal, string.format("controller initialized: enabled=%s mode=%s queue=%s remaining=%s count_server_downtime=%s",
        tostring(settings.enabled), controller_state.mode, table.concat(controller_state.queue, ","),
        clean(controller_remaining(now), 30), tostring(settings.count_server_downtime)))
end

local function diagnostic_line(pal, session, id, phase, category, values)
    log(pal, string.format("boss diagnostic: token=%s phase=%s category=%s pal=%s %s",
        session_label(session), phase, category, id, values))
end

local function log_native_inspection(pal, session, id, phase)
    local d = Native.inspect(id)
    if not d then
        diagnostic_line(pal, session, id, phase, "identity", "result=not_loaded")
        return nil
    end
    diagnostic_line(pal, session, id, phase, "identity", string.format(
        "species=%s save_character=%s level=%s rank=%s rare=%s actor=%s class=%s",
        clean(d.species, 64), clean(d.save_character, 64), clean(d.level, 20), clean(d.rank, 20),
        clean(d.rare, 12), clean(d.actor, 220), clean(d.class, 180)))
    diagnostic_line(pal, session, id, phase, "actor", string.format(
        "position=%s rotation=%s scale=%s authority=%s local_role=%s remote_role=%s replicates=%s hidden=%s battle_mode=%s dead=%s dead_source=%s",
        vector_text(d.position), vector_text(d.rotation), vector_text(d.scale), clean(d.authority, 12),
        clean(d.local_role, 20), clean(d.remote_role, 20), clean(d.replicates, 12), clean(d.hidden, 12),
        clean(d.battle_mode, 12), clean(d.dead, 12), clean(d.dead_source, 50)))
    diagnostic_line(pal, session, id, phase, "controller", string.format(
        "object=%s class=%s present=%s pawn=%s possession_matches=%s state=%s battle_mode=%s target=%s play_default_action=%s action_component=%s brain=%s blackboard=%s perception=%s",
        clean(d.controller, 180), clean(d.controller_class, 180), clean(d.has_controller, 12),
        clean(d.controller_pawn, 180), clean(d.possession_matches, 12), clean(d.controller_state, 80),
        clean(d.controller_battle_mode, 12), clean(d.controller_target, 180),
        clean(d.has_play_default_action, 12), clean(d.has_action_component, 12),
        clean(d.has_brain_component, 12), clean(d.has_blackboard, 12), clean(d.has_perception, 12)))
    diagnostic_line(pal, session, id, phase, "individual", string.format(
        "parameter=%s parameter_class=%s parameter_component=%s handle=%s handle_class=%s handle_id=%s group=%s owner_uid=%s spawned_type=%s uncapturable=%s predator=%s static_predator=%s mirror_character=%s mirror_level=%s",
        clean(d.parameter, 180), clean(d.parameter_class, 180), clean(d.parameter_component, 180),
        clean(d.handle, 180), clean(d.handle_class, 180), clean(d.handle_id, 40), clean(d.group, 40),
        clean(d.owner_uid, 40), clean(d.spawned_type, 20), clean(d.uncapturable, 12),
        clean(d.is_predator, 12), clean(d.static_predator, 12),
        clean(d.mirror_character, 64), clean(d.mirror_level, 20)))
    diagnostic_line(pal, session, id, phase, "stats", string.format(
        "hp=%s max_hp=%s hp_rate=%s melee=%s melee_buffed=%s shot=%s shot_buffed=%s defense=%s defense_buffed=%s enemy_max_hp_rate=%s enemy_inflict_rate=%s enemy_receive_rate=%s talent_hp=%s talent_melee=%s talent_shot=%s talent_defense=%s",
        clean(d.hp, 30), clean(d.max_hp, 30), clean(d.hp_rate, 30),
        clean(d.melee_attack, 20), clean(d.melee_attack_buffed, 20),
        clean(d.shot_attack, 20), clean(d.shot_attack_buffed, 20),
        clean(d.defense, 20), clean(d.defense_buffed, 20),
        clean(d.enemy_hp_rate, 20), clean(d.enemy_inflict_rate, 20), clean(d.enemy_receive_rate, 20),
        clean(d.talent_hp, 20), clean(d.talent_melee, 20), clean(d.talent_shot, 20), clean(d.talent_defense, 20)))
    diagnostic_line(pal, session, id, phase, "skills", string.format(
        "active=%s passive=%s", clean(d.equip_waza, 500), clean(d.passive_skills, 500)))
    diagnostic_line(pal, session, id, phase, "components", string.format(
        "parameter=%s static=%s status=%s movement=%s capsule=%s mesh=%s root=%s",
        clean(d.has_parameter_component, 12), clean(d.has_static_component, 12),
        clean(d.has_status_component, 12), clean(d.has_movement_component, 12),
        clean(d.has_capsule_component, 12), clean(d.has_mesh, 12), clean(d.has_root_component, 12)))
    diagnostic_line(pal, session, id, phase, "verdict", string.format(
        "wiring=%s issues=%s expected_controller=MonsterAIController expected_spawned_type=2_or_8",
        clean(d.wiring_status, 20), clean(d.wiring_issues, 200)))
    return d
end

local function inspect_pal(pal, session, id, phase)
    log_native_inspection(pal, session, id, phase)
    if pal.pal and pal.pal.inspect then
        pal.pal.inspect({ pal = id }, function(ok, err, data)
            log(pal, string.format("palladium inspect: token=%s phase=%s pal=%s result=%s detail=%s",
                session_label(session), phase, id, ok and "ok" or "failed",
                ok and scalar_map(data) or clean(err, 300)))
        end)
    end
    if pal.pal and pal.pal.stats then
        pal.pal.stats({ pal = id }, function(ok, err, data)
            log(pal, string.format("palladium stats: token=%s phase=%s pal=%s result=%s detail=%s",
                session_label(session), phase, id, ok and "ok" or "failed",
                ok and scalar_map(data) or clean(err, 300)))
        end)
    end
end

engine = Encounter.new(Native, {
    current = function(session) return active == session end,
    log = function(message) log(current_pal,message) end,
    captured = function(session,id) inspect_pal(current_pal,session,id,"after_profile") end,
    spawned = function(session) controller_session_spawned(current_pal,session) end,
    completing = function(session, reason) seed_rewards(current_pal, session, reason) end,
    finished = function(session,reason,released)
        last_session = session
        if active == session then active = nil end
        blocked_spawners[session.spawner_id:lower()] = not released and "native_release_failed" or nil
        controller_session_finished(current_pal,session,reason)
        log(current_pal,"encounter ended: token=" .. session.token .. " reason=" .. reason ..
            " spawner_reuse=" .. (released and "allowed" or "blocked"))
    end,
})
local function scan_new(_,session) return session and engine.scan(session) or 0 end
local function release_if_ended(_,session) return session and engine.reconcile(session) or false end
local function cleanup(pal,session)
    if not session then return false,"no_active_encounter" end
    -- Never abandon living members and allow a second encounter on top of them.
    return false,"use !worldboss kill; logical abandonment of multi-Pal encounters is disabled"
end
local function reset_spawner(pal,who,id)
    local configured = configured_spawner(id)
    if not configured then tell(pal,who,"Unknown spawner.") return end
    if active then tell(pal,who,"Reset refused while an encounter is active; use !worldboss kill.") return end
    local remaining, failed = #configured.members,false
    for _,m in ipairs(configured.members) do
        local called=false
        local function done(ok,why)
            if called then return end
            called=true
            failed=failed or not ok
            remaining=remaining-1
            if remaining==0 then
                blocked_spawners[configured.id:lower()] = failed and "reset_failed" or nil
                tell(pal,who,failed and "Reset failed; arena remains blocked." or "All member spawners reset.")
            end
        end
        -- Only an unoccupied group is safe to reset without tracked members.
        local native = Native.inspect_spawner(m.full_name)
        if not native or native.spawned ~= false then done(false,"occupied_or_unloaded")
        else
            local queued,why = Native.release_spawner(m.full_name,done)
            if not queued then done(false,why) end
        end
    end
end

local function arena_ready(configured)
    local first
    for _,m in ipairs(configured.members) do
        local native = Native.inspect_spawner(m.full_name)
        if not native then return nil,"spawner_not_loaded" end
        if native.ground_resolved ~= true then return nil,"spawner_ground_unresolved" end
        if native.spawned ~= false then return nil,"spawner_occupied_or_unknown" end
        local apart=horizontal_distance(native.position,m.location)
        if not apart or apart>500 then return nil,"spawner_location_mismatch" end
        first=first or native
    end
    return first
end

begin_summon = function(pal, event, spawner_id, options, done)
    options = type(options) == "table" and options or {}
    local source = tostring(options.source or "admin"):lower()
    local quiet = options.quiet == true
    local requester = event.subject and event.subject.id
    local function reject(reason, message)
        if not quiet then tell(pal, requester, message or reason) end
        if type(done) == "function" then pcall(done, false, reason) end
        return false, reason
    end
    if pal.settings.enabled == false or pal.settings.probe_enabled ~= true then
        return reject("summoning_disabled",
            "World boss summoning is disabled. Set probe_enabled = true and restart the server.")
    end
    if not spawner_config or not config_write_ok then
        return reject("spawner_config_unavailable",
            "World boss spawner configuration is unavailable; preserve the startup log.")
    end
    local configured = configured_spawner(spawner_id)
    if not configured then
        return reject("unknown_spawner",
            "Unknown world boss spawner '" .. tostring(spawner_id) .. "'. Use !worldboss spawners.")
    end
    if blocked_spawners[configured.id:lower()] then
        return reject("spawner_blocked", "Spawner " .. configured.id ..
            " is blocked until the next server restart: " .. blocked_spawners[configured.id:lower()] .. ".")
    end
    if active then
        scan_new(pal, active, "preflight")
        release_if_ended(pal, active, "preflight")
    end
    if active then
        return reject("worldboss_busy", "Encounter " .. session_label(active) ..
            " is still active at " .. active.spawner_id .. ". Use !worldboss status or !worldboss cleanup.")
    end
    local settings = controller_settings(pal)
    if settings.enabled and controller_state then
        if source == "automatic" then
            if controller_state.mode ~= "due_waiting"
                or tostring(controller_state.due_spawner):lower() ~= configured.id:lower() then
                return reject("automatic_spawner_not_due", "That automatic world boss is not due.")
            end
        elseif controller_state.mode == "due_waiting" or controller_state.mode == "spawning_auto" then
            return reject("automatic_spawn_pending",
                "The automatic world boss timer has elapsed and its queued encounter is pending.")
        elseif controller_state.mode:match("^active_") or controller_state.mode:match("^spawning_") then
            return reject("controller_busy", "The world boss controller is busy.")
        end
    end
    local capabilities = Native.capabilities()
    if not capabilities.ready then
        return reject("native_unavailable", "PalSchema world boss spawning is unavailable; preserve the startup log.")
    end
    local spawner,why = arena_ready(configured)
    if not spawner then return reject(why,"Arena not ready: " .. why .. ". Travel to its map location and retry.") end
    sequence = sequence + 1
    local session = {
        token=sequence, requester=requester, source=source, title=configured.title,
        map_x=configured.map_x,map_y=configured.map_y,
        announcement_sent=options.announcement_sent==true,summon_done=done,
        reset_schedule=options.reset_schedule==true,
        spawner_id=configured.id,spawner_name=configured.full_name,
        species="multi-pal",level=configured.level,
        location={x=configured.world_x,y=configured.world_y,z=spawner.position.z},
        respawn_player_radius=configured.respawn_player_radius,
        reward_id="wb-" .. tostring(os.time()) .. "-" .. tostring(sequence) .. "-" .. configured.id,
        reward_recipients={},
        relock_delay=number(pal.settings.spawner_relock_delay_ms,1000,30000,10000),
    }
    active=session
    controller_pause_for_session(pal,session)
    engine.start(session,configured)
    if not quiet then tell(pal,requester,"World boss encounter requested: " .. configured.title ..
        " (" .. #configured.members .. " members).") end
    return true,session.token
end

controller_try_due = function(pal, reason)
    if active or not controller_state or controller_state.mode ~= "due_waiting" then return false end
    local configured = configured_spawner(controller_state.due_spawner)
    if not configured then
        controller_state.queue = reconcile_queue(controller_state.queue)
        controller_expire(pal)
        return false
    end
    if blocked_spawners[configured.id:lower()] then
        log(pal, string.format("controller due spawn deferred: spawner=%s reason=spawner_blocked detail=%s",
            configured.id, clean(blocked_spawners[configured.id:lower()], 120)))
        return false
    end
    local spawner = Native.inspect_spawner(configured.full_name)
    if not spawner or spawner.ground_resolved ~= true then
        if controller_state.last_defer_reason ~= "spawner_not_ready" then
            controller_state.last_defer_reason = "spawner_not_ready"
            log(pal, string.format("controller due spawn deferred: spawner=%s reason=%s map=%.0f,%.0f announcement_already_sent=true",
                configured.id, spawner and "terrain_unresolved" or "spawner_not_loaded",
                configured.map_x, configured.map_y))
        end
        return false
    end
    local players, player_error = Native.players_near(configured.location, configured.respawn_player_radius)
    if not players or (tonumber(players.count) or 0) < 1 then
        if controller_state.last_defer_reason ~= "no_nearby_players" then
            controller_state.last_defer_reason = "no_nearby_players"
            log(pal, string.format("controller due spawn deferred: spawner=%s reason=%s nearby_players=%s radius=%.1f announcement_already_sent=true",
                configured.id, clean(player_error or "no_nearby_players", 120),
                clean(players and players.count, 20), configured.respawn_player_radius))
        end
        return false
    end
    controller_state.last_defer_reason = nil
    local event = { subject = { id = "SERVER", name = "World Boss Controller", role = "SYSTEM" } }
    local accepted, result = begin_summon(pal, event, configured.id, {
        source = "automatic", quiet = true, announcement_sent = true,
    }, function(ok, err, data)
        log(pal, string.format("controller automatic summon completion: spawner=%s result=%s detail=%s token=%s",
            configured.id, ok and "spawned" or "failed", clean(err or "none", 160),
            clean(data and data.token, 30)))
    end)
    log(pal, string.format("controller due spawn attempt: spawner=%s trigger=%s result=%s detail=%s nearby_players=%d",
        configured.id, clean(reason, 48), accepted and "accepted" or "deferred",
        clean(result, 160), tonumber(players.count) or 0))
    return accepted
end

local function show_spawners(pal,who)
    if not spawner_config then tell(pal,who,"Spawner configuration unavailable: " .. tostring(spawner_config_error)) return end
    for _,row in ipairs(spawner_config.list) do
        tell(pal,who,string.format("%s: %s; highest level=%d members=%d map=%.0f,%.0f automatic=%s order=%d",
            row.id,row.title,row.level,#row.members,row.map_x,row.map_y,tostring(row.auto_enabled),row.queue_order))
        for _,m in ipairs(row.members) do
            local native=Native.inspect_spawner(m.full_name)
            log(pal,"member status: arena=" .. row.id .. " index=" .. m.index .. " species=" .. m.spawn_pal_id ..
                " level=" .. m.level .. " native=" .. scalar_map(native))
        end
    end
end

local function status(pal, who)
    if active then
        scan_new(pal, active, "status_reconcile")
        release_if_ended(pal, active, "status_reconcile")
    end
    local remaining = controller_remaining(os.time())
    if controller_state then
        tell(pal, who, string.format("Controller: mode=%s next=%s remaining=%s queue=%s source=%s.",
            controller_state.mode, controller_state.due_spawner ~= "" and controller_state.due_spawner
                or (controller_state.queue and controller_state.queue[1]) or "none",
            remaining == nil and "stopped" or duration_text(remaining),
            table.concat(controller_state.queue or {}, ","),
            controller_state.active_source ~= "" and controller_state.active_source or "none"))
    end
    local session = active or last_session
    if not session then
        tell(pal, who, "No world boss encounter has run during this server session.")
        return
    end
    tell(pal, who, string.format("World boss %s: spawner=%s species=%s level=%d status=%s tracked=%d/%d request=%s.",
        session_label(session), session.spawner_id, session.species, session.level,
        session.status, session.count, session.expected_count, session.request_result or "pending"))
    for _, id in ipairs(session.order) do inspect_pal(pal, session, id, "status") end
end

local function command(event, _, pal, params)
    current_pal = pal
    local who = event.subject and event.subject.id
    if not who then return end
    params = type(params) == "table" and params or {}
    local mode = tostring(params.mode or "status"):lower()
    if mode == "claim" then
        claim_rewards(pal, who)
        return
    end
    if mode == "find" then
        local id=active and active.spawner_id or (controller_state and controller_state.mode=="due_waiting" and controller_state.due_spawner)
        local configured=configured_spawner(id)
        tell(pal,who,configured and render_announcement(pal,"spawn",configured) or "No world boss is currently active.")
        return
    end
    local allowed, authorization = may_administer(pal, event, who, mode)
    if not allowed then
        tell(pal, who, "You are not allowed to run world boss administration commands.")
        log(pal, string.format("admin command denied: caller=%s(%s) mode=%s",
            clean(event.subject and event.subject.name or who, 64), tostring(who), clean(mode, 32)))
        return
    end
    log(pal, string.format("admin command accepted: caller=%s(%s) mode=%s authorization=%s",
        clean(event.subject and event.subject.name or who, 64), tostring(who), clean(mode, 32), authorization))
    if mode == "spawn" then
        if active or (controller_state and controller_state.mode=="due_waiting") then
            tell(pal,who,"A world boss is already active or waiting at its arena.") return
        end
        if not controller_state or not controller_settings(pal).enabled then
            tell(pal,who,"Enable the automatic controller before using spawn.") return
        end
        if controller_expire(pal) then
            controller_try_due(pal,"admin_spawn")
            schedule_controller(pal)
            tell(pal,who,"Next queued world boss is due now; visit its arena if it is waiting for players.")
        else tell(pal,who,"No automatic world bosses are configured.") end
        return
    end
    if mode == "kill" then
        if active then
            local accepted,why = engine.kill(active,function(ok,err)
                tell(pal,who,ok and "World boss members killed without framework rewards; ending encounter and starting the next timer."
                    or ("Kill incomplete; rewards suppressed. Resolve/retry: " .. tostring(err)))
            end)
            if not accepted then tell(pal,who,"Kill refused: " .. tostring(why)) end
        elseif controller_state and controller_state.mode=="due_waiting" then
            queue_remove(controller_state.due_spawner)
            start_countdown(pal,controller_settings(pal).spawn_interval_seconds,"admin_kill_due_waiting")
            tell(pal,who,"Waiting encounter cancelled without rewards; next timer started.")
        else tell(pal,who,"No world boss is active.") end
        return
    end
    if mode == "status" or mode == "timer" or mode == "queue" then status(pal, who) return end
    if mode == "spawners" or mode == "list" then show_spawners(pal, who) return end
    if mode == "cleanup" then
        local ok, result = cleanup(pal, active, "command")
        tell(pal, who, ok and ("Cleanup: " .. result .. ".") or ("Cleanup failed: " .. result .. "."))
        return
    end
    if mode == "reset" then
        local spawner_id = tostring(params.spawner or "")
        if spawner_id == "" then
            tell(pal, who, "Usage: !worldboss reset <spawner>")
            return
        end
        reset_spawner(pal, who, spawner_id)
        return
    end
    if mode == "exact" or mode == "static" then
        tell(pal, who, "That diagnostic route was retired. Use !worldboss summon <spawner>.")
        return
    end
    if mode ~= "summon" then
        tell(pal, who, "Usage: !worldboss <find|claim|spawn|kill|summon|spawners|status|timer|queue|reset> [spawner]")
        return
    end
    local spawner_id = tostring(params.spawner or "")
    if spawner_id == "" or #spawner_id > 32 or not spawner_id:match("^[%w_-]+$") then
        tell(pal, who, "Provide a valid spawner ID. Use !worldboss spawners to list configured IDs.")
        return
    end
    begin_summon(pal, event, spawner_id, { source = "admin" })
end

local function on_npc_spawn(_,pal)
    current_pal=pal
    if active then engine.scan(active) end
end
local function on_native_terminal(record,reason)
    if active and type(record)=="table" then engine.terminal(active,tostring(record.id or ""):upper(),reason) end
end

local function on_native_death(record) on_native_terminal(record, "death_event") end
local function on_native_capture(record) on_native_terminal(record, "capture_event") end

local function guard_report(reason, report)
    report = type(report) == "table" and report or {}
    log(current_pal, string.format("spawner guard: reason=%s locked=%s failed=%s grounded=%s ground_failed=%s error=%s",
        clean(reason, 40), clean(report.locked, 20), clean(report.failed, 20),
        clean(report.grounded, 20), clean(report.ground_failed, 20), clean(report.error or "none", 200)))
    for _, row in ipairs(report.spawners or {}) do
        log(current_pal, string.format("spawner guarded: name=%s result=%s disabled=%s occupied=%s map=%s,%s world_xy=%s,%s ground_resolved=%s ground_z=%s clearance=%s position=%s ground_error=%s groups=%s actor=%s",
            clean(row.name, 80), clean(row.lock_result or "locked", 120), clean(row.disabled, 12),
            clean(row.spawned, 12), clean(row.map_x, 30), clean(row.map_y, 30),
            clean(row.world_x, 30), clean(row.world_y, 30), clean(row.ground_resolved, 12),
            clean(row.ground_z, 30), clean(row.clearance, 30), vector_text(row.position),
            clean(row.ground_error or "none", 180), clean(row.groups, 200), clean(row.actor, 220)))
        if row.build_protection then
            log(current_pal,"arena building guard: spawner=" .. clean(row.name,80) ..
                " verified=" .. tostring(row.build_protected) .. " detail=" .. clean(row.build_protection,180))
        end
    end
    if current_pal and controller_loaded and controller_state
        and controller_state.mode == "due_waiting" then
        controller_try_due(current_pal, "spawner_guard")
    end
end

local guard_ok, guard_result = Native.install_spawner_guard(SPAWNER_PREFIX, guard_report, spawner_placements)

local function ready(pal)
    current_pal = pal
    if sync_shop_integration then sync_shop_integration(pal) end
    if not combat_hook_logged then
        combat_hook_logged=true
        log(pal,"aggression: player_sight=Battle_Anyway applied_per_boss_profile; shared_species_presets_unchanged")
    end
    if not death_hook_logged then
        local ok, result = Native.register_death_hook(on_native_death)
        death_hook_logged = true
        log(pal, "death hook: target=/Script/Pal.PalCharacter:OnDeadCharacter result=" ..
            (ok and "registered" or "failed") .. " detail=" .. clean(result, 180))
    end
    if not capture_hook_logged then
        local ok, result = Native.register_capture_hook(on_native_capture)
        capture_hook_logged = true
        log(pal, "capture hook: target=/Script/Pal.PalUtility:PalCaptureSuccess result=" ..
            (ok and "registered" or "failed") .. " detail=" .. clean(result, 180))
    end
    initialize_controller(pal)
    if active then engine.tick(active) end -- Event-time recovery if a scheduled wake was lost.
    Native.reconcile_spawners(SPAWNER_PREFIX, spawner_placements, function(ok, err, report)
        if ok then
            guard_report("ready_reconcile", report)
        else
            log(pal, "spawner guard: reason=ready_reconcile locked=0 failed=1 error=" .. clean(err, 200))
        end
    end)
    controller_tick(pal, "ready")
    if ready_logged then return end
    ready_logged = true
    local queue_mode = pal.settings.controller and pal.settings.controller.queue_order
    if queue_mode ~= nil and not ({ascending=true,descending=true,random=true})[queue_mode] then
        log(pal,"config warning: invalid controller.queue_order; using ascending next round")
    end
    local native = Native.capabilities()
    log(pal,"arena protection: removed_from_world_boss_scope; block_building ignored; no hooks or building mutation")
    log(pal,"rewards: natural completion snapshots players within match_radius; delivery=player.claim; kinds=item+shop_currency; collection=reward_claims")
    log(pal,"scheduler: executor=loop_async_one_shot heartbeat_ms=100 max_in_flight=1 timeout_ms=5000 event_dispatch=queued capture_scan=serialized release_watchdog=5s/3_attempts")
    log(pal, string.format("startup: v%s world-boss coordination controller ready; Core API %d accepted; enabled=%s probe_enabled=%s controller_enabled=%s controller_mode=%s config=%s generated=%s configured_spawners=%d automatic_spawners=%d coordinate_mode=map_overlay terrain_z=runtime_ground_trace guard=%s guard_detail=%s native_ready=%s find_all=%s game_thread=%s delay=%s notify=%s static_find=%s ground_trace=%s fname=%s fname_type=%s hook=%s lifecycle=death+capture+active_distance_respawn native_spawner_reset=true instance_profiles=true hybrid_designation=false active_respawn_interval_ms=%d idle_respawn_checks=false controller_state_persistent=true service_api=%d",
        VERSION, Core.API, tostring(pal.settings.enabled ~= false), tostring(pal.settings.probe_enabled == true),
        tostring(controller_settings(pal).enabled), clean(controller_state and controller_state.mode, 32),
        spawner_config and "ready" or "failed", clean(config_write_status, 80),
        spawner_config and #spawner_config.list or 0, #automatic_ids(),
        tostring(guard_ok), clean(guard_result, 80),
        tostring(native.ready == true), tostring(native.find_all == true), tostring(native.game_thread == true),
        tostring(native.delay == true), tostring(native.notify == true), tostring(native.static_find == true),
        tostring(native.ground_trace == true), tostring(native.fname == true),
        tostring(native.fname_type or "unknown"), tostring(native.hook == true),
        RESPAWN_CHECK_INTERVAL_MS, BossService.API))
end

log(nil, string.format("startup: v%s loaded; Core API %d accepted; persistent world-boss coordination controller; config=%s generated=%s guard=%s",
    VERSION, Core.API, spawner_config and "ready" or "failed", clean(config_write_status, 80), tostring(guard_ok)))
for _,warning in ipairs(spawner_config and spawner_config.warnings or {}) do log(nil,"config warning: " .. warning) end
if not spawner_config then log(nil, "spawner config error: " .. clean(spawner_config_error, 400)) end
if not config_write_ok then log(nil, "PalSchema spawner generation error: " .. clean(config_write_status, 400)) end

local function service_status()
    if not controller_state then return nil, "not_ready" end
    local queue = {}
    for index, id in ipairs(controller_state.queue or {}) do queue[index] = id end
    return {
        version = VERSION,
        controller_mode = controller_state.mode,
        remaining_seconds = controller_remaining(os.time()),
        queue = queue,
        due_spawner = controller_state.due_spawner ~= "" and controller_state.due_spawner or nil,
        active = active ~= nil,
        active_token = active and active.token or nil,
        active_spawner = active and active.spawner_id or nil,
        active_source = active and active.source or nil,
    }
end

local function service_can_summon(spawner_id, options)
    if not current_pal then return false, "not_ready" end
    if current_pal.settings.enabled == false or current_pal.settings.probe_enabled ~= true then
        return false, "summoning_disabled"
    end
    local configured = configured_spawner(spawner_id)
    if not configured then return false, "unknown_spawner" end
    if active then return false, "worldboss_busy" end
    if blocked_spawners[configured.id:lower()] then return false, "spawner_blocked" end
    local source = tostring(options and options.source or "integration"):lower()
    local settings = controller_settings(current_pal)
    if settings.enabled and controller_state then
        if source == "automatic" then
            if controller_state.mode ~= "due_waiting"
                or tostring(controller_state.due_spawner):lower() ~= configured.id:lower() then
                return false, "automatic_spawner_not_due"
            end
        elseif controller_state.mode == "due_waiting" or controller_state.mode:match("^spawning_")
            or controller_state.mode:match("^active_") then
            return false, "controller_busy"
        end
    end
    local capabilities = Native.capabilities()
    if not capabilities.ready then return false, "native_unavailable" end
    local spawner,why = arena_ready(configured)
    if not spawner then return false,why end
    return true, {
        spawner_id = configured.id, title = configured.title, level = configured.level,
        map_x = configured.map_x, map_y = configured.map_y,
    }
end

local service_adapter = {}
function service_adapter.status()
    return service_status()
end
function service_adapter.can_summon(spawner_id, options)
    return service_can_summon(spawner_id, options)
end
function service_adapter.summon(spawner_id, options, done)
    options = type(options) == "table" and options or {}
    local allowed, reason = service_can_summon(spawner_id, options)
    if not allowed then
        if type(done) == "function" then pcall(done, false, reason) end
        return false, reason
    end
    local requester = tostring(options.player_id or options.requester_id or "INTEGRATION")
    local event = { subject = {
        id = requester,
        name = tostring(options.player_name or options.requester_name or requester),
        role = "SERVICE",
    } }
    return begin_summon(current_pal, event, spawner_id, {
        source = tostring(options.source or "integration"),
        quiet = options.quiet ~= false,
        announcement_sent = options.announcement_sent == true,
        reset_schedule = options.reset_schedule == true,
    }, done)
end
assert(BossService.bind(service_adapter))

local shop_offer_specs = {}
local shop_reservation
local shop_provider_registered = false
local shop_provider_status = "not_attempted"
local shop_subscribed = false
local shop_sync_logged = false

local function current_shop_reservation()
    if shop_reservation and os.time() - (tonumber(shop_reservation.at) or 0) > 600 then
        shop_reservation = nil
    end
    return shop_reservation
end

local function shop_spawner(id)
    local configured = configured_spawner(id)
    if not configured or configured.shop_offer_enabled ~= true then return nil end
    return configured
end

local function clear_shop_reservation(event)
    local transaction = event and event.data and tostring(event.data.transaction_id or "") or ""
    if transaction ~= "" and shop_reservation and shop_reservation.transaction == transaction then
        shop_reservation = nil
    end
end

local function shop_provider_preflight(context)
    if tonumber(context and context.amount) ~= 1 then return false, "summon_amount_must_be_one" end
    local configured = shop_spawner(context and context.id)
    if not configured then return false, "worldboss_shop_offer_unavailable" end
    local transaction = tostring(context.transaction_id or "")
    local held = current_shop_reservation()
    if held and held.transaction ~= transaction then
        return false, "worldboss_summon_purchase_in_progress"
    end
    local allowed, reason = service_can_summon(configured.id, { source = "server_shop" })
    if not allowed then return false, reason end
    shop_reservation = { transaction = transaction, spawner = configured.id, at = os.time() }
    return true
end

local function shop_provider_deliver(context, done)
    local completed = false
    local function finish(ok, reason)
        if completed then return end
        completed = true
        local transaction = tostring(context and context.transaction_id or "")
        if shop_reservation and shop_reservation.transaction == transaction then shop_reservation = nil end
        done(ok == true, reason)
    end
    if tonumber(context and context.amount) ~= 1 then finish(false, "summon_amount_must_be_one") return end
    local configured = shop_spawner(context and context.id)
    if not configured then finish(false, "worldboss_shop_offer_unavailable") return end
    local transaction = tostring(context.transaction_id or "")
    local held = current_shop_reservation()
    if held and held.transaction ~= transaction then
        finish(false, "worldboss_summon_purchase_in_progress")
        return
    end
    local accepted, reason = BossService.summon(configured.id, {
        source = "server_shop",
        player_id = context.player_id,
        player_name = context.player_name,
        quiet = true,
        reset_schedule = configured.shop_reset_schedule == true,
    }, function(ok, why)
        if ok then
            log(current_pal, string.format("shop summon completed: transaction=%s player=%s spawner=%s reset_schedule=%s",
                clean(transaction, 96), clean(context.player_id, 64), configured.id,
                tostring(configured.shop_reset_schedule == true)))
        else
            log(current_pal, string.format("shop summon failed: transaction=%s player=%s spawner=%s reason=%s",
                clean(transaction, 96), clean(context.player_id, 64), configured.id, clean(why, 180)))
        end
        finish(ok, why)
    end)
    if accepted ~= true then finish(false, reason or "worldboss_summon_rejected") end
end

sync_shop_integration = function(pal)
    local shop = server_shop_service(false)
    if not shop then
        if not shop_sync_logged then
            shop_sync_logged = true
            log(pal, "shop integration unavailable; ServerShopFramework API 1 was not found")
        end
        return
    end
    if not shop_provider_registered then
        local ok, reason = shop.register_reward_provider(SHOP_REWARD_KIND, OWNER, {
            preflight = shop_provider_preflight,
            deliver = shop_provider_deliver,
        })
        shop_provider_registered = ok == true
        shop_provider_status = ok and "registered" or tostring(reason)
    end
    if not shop_subscribed and shop_provider_registered then
        shop.subscribe("purchase.completed", OWNER, clear_shop_reservation)
        shop.subscribe("purchase.failed", OWNER, clear_shop_reservation)
        shop_subscribed = true
    end
    local present, configured_count = {}, 0
    for _, configured in ipairs(spawner_config and spawner_config.list or {}) do
        if configured.shop_offer_enabled == true then
            configured_count = configured_count + 1
            local offer_id = "worldboss_" .. configured.id
            present[offer_id] = true
            local fresh = {
                enabled = shop_provider_registered and pal.settings.enabled ~= false
                    and pal.settings.probe_enabled == true,
                name = "Summon " .. configured.title,
                description = "Summon the world boss " .. configured.title .. " immediately.",
                category = "worldboss",
                max_purchases = configured.shop_max_purchases,
                cooldown_seconds = configured.shop_cooldown_seconds,
                costs = { { kind = "currency", amount = configured.shop_currency_cost } },
                rewards = { { kind = SHOP_REWARD_KIND, id = configured.id, amount = 1 } },
            }
            local spec = shop_offer_specs[offer_id]
            if spec then
                for key in pairs(spec) do spec[key] = nil end
                for key, value in pairs(fresh) do spec[key] = value end
            else
                local ok, reason = shop.register_offer(OWNER, offer_id, fresh)
                if ok then
                    shop_offer_specs[offer_id] = fresh
                else
                    log(pal, "shop offer registration failed: " .. offer_id .. " reason=" .. clean(reason, 180))
                end
            end
        end
    end
    for offer_id, spec in pairs(shop_offer_specs) do
        if not present[offer_id] then spec.enabled = false end
    end
    if not shop_sync_logged then
        shop_sync_logged = true
        log(pal, string.format("shop integration: provider=%s offers=%d currency_rewards=claim_only",
            shop_provider_status, configured_count))
    end
end

local command_definition = {
    node = "worldbossframework.probe_command",
    help = "!worldboss <find|claim|spawn|kill|summon|spawners|status|timer|queue|reset> [spawner]",
    params = {
        { name = "mode", kind = "string", required = true, max_len = 16 },
        { name = "spawner", kind = "string", max_len = 32 },
    },
    run = function(event,text,pal,params)
        return dispatch_game(function() command(event,text,pal,params) end)
    end,
}

return {
    name = OWNER, version = VERSION, api = 1,
    description = "Persistent world-boss queue, arena-range item/currency rewards, shop summons, and PalSchema lifecycle.",
    permissions = {
        { node = "worldbossframework.probe_command", description = "reach the internally authorized world boss command", default = "allow" },
        { node = "worldbossframework.admin", description = "run world boss administration commands", default = "deny" },
    },
    settings = {
        enabled = true, probe_enabled = false, administrator_uids = {},
        spawner_relock_delay_ms = 10000,
        controller = {
            enabled = false,
            queue_order = "ascending",
            spawn_interval_seconds = 7200,
            initial_delay_seconds = 900,
            due_retry_seconds = 1,
            recovery_delay_seconds = 30,
            count_server_downtime = false,
        },
        announcements = {
            spawn = "[Boss Title] (Lv.[Level]) has appeared at map [Map X], [Map Y]!",
            defeat = "[Boss Title] has been defeated! Next world boss in [Next Spawn].",
        },
    },
    data = {
        controller_state = {
            description = "persistent automatic world-boss queue and timer state",
            fields = {
                mode = "string", queue = "string", deadline_at = "int",
                checkpoint_remaining = "int", paused_remaining = "int",
                due_spawner = "string", active_spawner = "string", active_source = "string",
                announced_due = "bool", updated_at = "int",
            },
        },
        reward_claims = {
            description = "persistent unclaimed world-boss item and shop-currency rewards",
            fields = {
                uid = "string", encounter = "string", spawner = "string", title = "string",
                reward_index = "int", kind = "string", item = "string", awarded = "int", delivered = "int",
                status = "string", error = "string", created_at = "int", updated_at = "int",
            },
        },
    },
    on = {
        ["bridge.ready"] = function(_, pal) dispatch_game(function() ready(pal) end) end,
        ["player.join"] = function(_, pal) dispatch_game(function() ready(pal) end) end,
        ["player.chat"] = function(_, pal) dispatch_game(function() ready(pal) end) end,
        ["clock.minute"] = function(_, pal)
            dispatch_game(function()
                current_pal = pal
                initialize_controller(pal)
                if active then engine.tick(active) end
                controller_tick(pal, "clock.minute")
            end)
        end,
        ["npc.spawn"] = function(event,pal) dispatch_game(function() on_npc_spawn(event,pal) end) end,
    },
    commands = {
        ["!worldboss"] = command_definition,
        ["!worldbossprobe"] = command_definition,
    },
}
