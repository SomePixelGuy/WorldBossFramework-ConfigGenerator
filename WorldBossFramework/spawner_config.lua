local Config = {}

local MAP_WORLD_SCALE = 459.0
local MAP_WORLD_X_OFFSET = -123888.0
local MAP_WORLD_Y_OFFSET = 158000.0
local BOOTSTRAP_Z = 0.0

local FIELD_NAMES = {
    enabled = true,
    title = true, first_defeat_title = true, auto_enabled = true, queue_order = true,
    shop_offer_enabled = true, shop_currency_cost = true,
    shop_max_purchases = true, shop_cooldown_seconds = true,
    shop_reset_schedule = true,
    map_x = true, map_y = true, ground_clearance = true,
    rotation_pitch = true, rotation_yaw = true, rotation_roll = true,
    pal_id = true, level = true, scale = true, match_radius = true,
    respawn_player_radius = true,
    member_spacing = true, arena_radius = true, block_building = true,
    alpha = true, predator = true, uncapturable = true,
    hp_multiplier = true, attack_multiplier = true, defense_multiplier = true,
    active_skill_1 = true, active_skill_2 = true, active_skill_3 = true,
    passive_skill_1 = true, passive_skill_2 = true,
    passive_skill_3 = true, passive_skill_4 = true,
}

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function finite_number(value)
    local number = tonumber(value)
    if not number or number ~= number or number == math.huge or number == -math.huge then return nil end
    return number
end

local function parse_value(value)
    value = trim(value)
    local quoted = value:match('^"(.*)"$')
    if quoted == nil then quoted = value:match("^'(.*)'$") end
    if quoted ~= nil then
        quoted = quoted:gsub("\\n", "\n"):gsub("\\r", "\r"):gsub("\\t", "\t")
            :gsub("\\\"", "\""):gsub("\\'", "'"):gsub("\\\\", "\\")
        return quoted
    end
    if value == "true" then return true end
    if value == "false" then return false end
    return finite_number(value) or value
end

local function strip_comment(value)
    local quote, escaped = nil, false
    for index = 1, #value do
        local character = value:sub(index, index)
        if escaped then
            escaped = false
        elseif quote and character == "\\" then
            escaped = true
        elseif quote then
            if character == quote then quote = nil end
        elseif character == "\"" or character == "'" then
            quote = character
        elseif (character == ";" or character == "#")
            and (index == 1 or value:sub(index - 1, index - 1):match("%s")) then
            return value:sub(1, index - 1)
        end
    end
    return value
end

local function require_number(row, field, minimum, maximum, fallback)
    local value = row[field]
    if value == nil then value = fallback end
    value = finite_number(value)
    if value == nil or value < minimum or value > maximum then
        return nil, string.format("spawners.%s.%s must be between %s and %s",
            row.id, field, tostring(minimum), tostring(maximum))
    end
    return value
end

local function optional_name(row, field, maximum)
    local value = trim(row[field])
    if value == "" or value:lower() == "none" then return nil end
    if #value > maximum or not value:match("^[%w_]+$") then
        return nil, string.format("spawners.%s.%s is invalid", row.id, field)
    end
    return value
end

local function json_string(value)
    local text = tostring(value or "")
    text = text:gsub("\\", "\\\\"):gsub('"', '\\"')
        :gsub("\b", "\\b"):gsub("\f", "\\f")
        :gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t")
    return '"' .. text .. '"'
end

local function json_float(value)
    local text = string.format("%.9f", value)
    text = text:gsub("0+$", "")
    if text:sub(-1) == "." then text = text .. "0" end
    if not text:find(".", 1, true) then text = text .. ".0" end
    return text
end

function Config.map_to_world(map_x, map_y)
    map_x, map_y = finite_number(map_x), finite_number(map_y)
    if not map_x or not map_y then return nil, nil end
    return map_y * MAP_WORLD_SCALE + MAP_WORLD_X_OFFSET,
        map_x * MAP_WORLD_SCALE + MAP_WORLD_Y_OFFSET
end

-- Member fields always use a positive, contiguous instance suffix.
local MEMBER_FIELDS = {
    pal_id=true, level=true, alpha=true, predator=true, uncapturable=true, scale=true,
    hp_multiplier=true, attack_multiplier=true, defense_multiplier=true,
    active_skill_1=true, active_skill_2=true, active_skill_3=true,
    passive_skill_1=true, passive_skill_2=true, passive_skill_3=true, passive_skill_4=true,
}
function Config.special_id(id)
    local prefix = tostring(id or ""):match("^([^_]+)_")
    if not prefix then return false, false end
    local upper = prefix:upper()
    local known = { BOSS=true, RAID=true, GYM=true, PREDATOR=true, SUMMON=true, POLICE=true }
    return known[upper] == true or prefix:match("^[A-Z][A-Z0-9]*$") ~= nil,
        upper == "RAID" or upper == "GYM"
end

local function numeric(raw, out, field, low, high, fallback, integer)
    local value, err = require_number(raw, field, low, high, fallback)
    if not value then return err end
    if integer and value % 1 ~= 0 then return raw.id .. "." .. field .. " must be an integer" end
    out[field] = integer and math.floor(value) or value + 0.0
end

function Config.load(path)
    local file, err = io.open(path, "r")
    if not file then return nil, "could not open spawner config: " .. tostring(err) end
    local rows, seen, line_number = {}, {}, 0
    for raw_line in file:lines() do
        line_number = line_number + 1
        local line = trim(strip_comment(raw_line))
        if line ~= "" then
            local key, value = line:match("^([%w_.-]+)%s*=%s*(.-)%s*$")
            local id, field, index, reward_index, reward_field
            if key then
                id, reward_index, reward_field = key:match("^spawners%.([%w_-]+)%.reward%.(%d+)%.([%w_]+)$")
                if id then
                    field = "reward"
                else
                    id, field, index = key:match("^spawners%.([%w_-]+)%.([%w_]+)%.(%d+)$")
                end
                if not id then id, field = key:match("^spawners%.([%w_-]+)%.([%w_]+)$") end
            end
            local problem
            if not id or #id > 32 then problem = "invalid key or spawner ID"
            elseif field == "count" then problem = "count removed; configure pal_id.1, pal_id.2 and each instance explicitly"
            elseif field == "reward" and (not reward_index or not reward_field) then problem = "reward keys require reward.<index>.<kind|item|count|chance>"
            elseif field == "reward" and not ({kind=true,item=true,count=true,chance=true})[reward_field] then problem = "unsupported reward field"
            elseif MEMBER_FIELDS[field] and not index then
                problem = "scalar member key removed; migrate " .. field .. " to " .. field .. ".1"
            elseif not FIELD_NAMES[field] and field ~= "reward" then problem = "unsupported key"
            elseif index and not MEMBER_FIELDS[field] then problem = "unsupported indexed key"
            elseif index and (tonumber(index) < 1 or tonumber(index) > 16 or tostring(tonumber(index)) ~= index) then
                problem = "member index must be 1 through 16 without leading zeroes"
            elseif reward_index and (tonumber(reward_index) < 1 or tonumber(reward_index) > 64 or tostring(tonumber(reward_index)) ~= reward_index) then
                problem = "reward index must be 1 through 64 without leading zeroes"
            elseif seen[key:lower()] then problem = "duplicate key"
            end
            if problem then file:close() return nil, string.format("%s: %s (line %d)", tostring(key), problem, line_number) end
            seen[key:lower()] = true
            rows[id] = rows[id] or { id=id, members={}, rewards={} }
            local target = rows[id]
            if reward_index then
                reward_index = tonumber(reward_index)
                target.rewards[reward_index] = target.rewards[reward_index] or { id=id .. ".reward." .. reward_index }
                target = target.rewards[reward_index]
                target[reward_field] = parse_value(value)
            elseif index then
                index = tonumber(index)
                target.members[index] = target.members[index] or { id=id .. ".member." .. index }
                target = target.members[index]
                target[field] = parse_value(value)
            else
                target[field] = parse_value(value)
            end
        end
    end
    file:close()
    local config = { by_id={}, list={}, warnings={}, path=path }
    for id, raw in pairs(rows) do
        if config.by_id[id:lower()] then return nil, "duplicate case-insensitive spawner ID: " .. id end
        if raw.enabled ~= false then
            local row = { id=id, enabled=true, title=trim(raw.title),
                first_defeat_title=trim(raw.first_defeat_title),
                auto_enabled=raw.auto_enabled==true,
                shop_offer_enabled=raw.shop_offer_enabled==true,
                shop_reset_schedule=raw.shop_reset_schedule==true,
                members={}, rewards={} }
            if row.title == "" or #row.title > 128 then return nil, "spawners." .. id .. ".title must contain 1 to 128 characters" end
            if row.first_defeat_title == "" or row.first_defeat_title:lower() == "none" then
                row.first_defeat_title = nil
            elseif #row.first_defeat_title > 96 or not row.first_defeat_title:match("^[%w_.-]+$") then
                return nil, "spawners." .. id .. ".first_defeat_title is invalid"
            end
            for _, spec in ipairs({
                {"queue_order",0,1000000,1000,true}, {"map_x",-10000,10000}, {"map_y",-10000,10000},
                {"ground_clearance",10,5000,100}, {"rotation_pitch",-360,360,0},
                {"rotation_yaw",-360,360,0}, {"rotation_roll",-360,360,0},
                {"match_radius",100,20000,5000}, {"respawn_player_radius",1000,100000,15000},
                {"member_spacing",100,10000,800}, {"arena_radius",1000,100000,raw.respawn_player_radius or 15000},
            }) do
                local why = numeric(raw, row, table.unpack(spec))
                if why then return nil, why end
            end
            for _, spec in ipairs({
                {"shop_max_purchases",0,1000000,0,true},
                {"shop_cooldown_seconds",0,31536000,0,true},
            }) do
                local why = numeric(raw, row, table.unpack(spec))
                if why then return nil, why end
            end
            if raw.shop_currency_cost ~= nil then
                local why = numeric(raw, row, "shop_currency_cost", 1, 9000000000000, nil, true)
                if why then return nil, why end
            elseif row.shop_offer_enabled then
                return nil, "spawners." .. id .. ".shop_currency_cost is required when shop_offer_enabled is true"
            end
            local maximum = 0
            for index in pairs(raw.members) do maximum = math.max(maximum, index) end
            if maximum == 0 then return nil, "spawners." .. id .. ".pal_id.1 is required" end
            row.level = 0 -- Highest member level: shared announcement/find contract.
            for index = 1, maximum do
                local input = raw.members[index]
                if not input or not input.pal_id then return nil, "spawners." .. id .. ".pal_id." .. index .. " is required; indices must be contiguous" end
                local m = { index=index, pal_id=trim(input.pal_id), active_skills={}, passive_skills={} }
                if m.pal_id == "" or #m.pal_id > 64 or not m.pal_id:match("^[%w_.-]+$") then return nil, input.id .. ".pal_id is invalid" end
                m.preserve_designation, m.preserve_active_skills = Config.special_id(m.pal_id)
                m.alpha = not m.preserve_designation and input.alpha == true
                m.predator = not m.preserve_designation and input.predator == true
                if m.alpha and m.predator then return nil, input.id .. ": alpha and predator are mutually exclusive" end
                if m.preserve_designation and (input.alpha == true or input.predator == true) then
                    config.warnings[#config.warnings+1] = input.id .. ": special ID preserved; alpha/predator ignored"
                end
                m.uncapturable = input.uncapturable ~= false
                m.spawn_pal_id = m.alpha and ("BOSS_" .. m.pal_id) or m.pal_id
                for _, spec in ipairs({
                    {"level",1,100,5,true}, {"scale",0.1,10,1.5},
                    {"hp_multiplier",0.01,1000,1}, {"attack_multiplier",0.01,1000,1},
                    {"defense_multiplier",0.01,1000,1},
                }) do
                    local why = numeric(input,m,table.unpack(spec))
                    if why then return nil, why end
                end
                m.receive_damage_rate = 1.0 / m.defense_multiplier
                for _, kind in ipairs({{"active",3}, {"passive",4}}) do
                    for slot=1,kind[2] do
                        local name, why = optional_name(input,kind[1] .. "_skill_" .. slot,96)
                        if why then return nil,why end
                        if name then m[kind[1] .. "_skills"][#m[kind[1] .. "_skills"]+1] = name end
                    end
                end
                -- Child names are unique even when arena IDs contain suffix-like text.
                m.native_id = id .. "__member_" .. index
                m.full_name = "WorldBossFramework_" .. m.native_id
                row.members[index] = m
                row.level = math.max(row.level,m.level)
            end
            local reward_maximum = 0
            for index in pairs(raw.rewards or {}) do reward_maximum = math.max(reward_maximum, index) end
            for index = 1, reward_maximum do
                local input = raw.rewards[index]
                if not input then
                    return nil, "spawners." .. id .. ".reward." .. index .. " is required; indices must be contiguous"
                end
                local kind = trim(input.kind):lower()
                if kind == "" then kind = "item" end
                if kind ~= "item" and kind ~= "currency" then
                    return nil, "spawners." .. id .. ".reward." .. index .. ".kind must be item or currency"
                end
                local item = trim(input.item)
                if kind == "item" and (item == "" or #item > 128 or not item:match("^[%w_]+$")) then
                    return nil, "spawners." .. id .. ".reward." .. index .. ".item is required and must be a valid item ID"
                elseif kind == "currency" and item ~= "" then
                    return nil, "spawners." .. id .. ".reward." .. index .. ".item is not used for currency rewards"
                end
                local count = finite_number(input.count == nil and 1 or input.count)
                if not count or count % 1 ~= 0 or count < 1 then
                    return nil, "spawners." .. id .. ".reward." .. index .. ".count must be a positive integer"
                end
                local chance = finite_number(input.chance == nil and 1.0 or input.chance)
                if not chance or chance < 0 or chance > 1 then
                    return nil, "spawners." .. id .. ".reward." .. index .. ".chance must be between 0 and 1"
                end
                row.rewards[index] = {
                    index=index, kind=kind, item=kind == "item" and item or "",
                    count=math.floor(count), chance=chance + 0.0,
                }
            end
            row.full_name = row.members[1].full_name
            row.world_x,row.world_y = Config.map_to_world(row.map_x,row.map_y)
            row.bootstrap_z = BOOTSTRAP_Z
            row.location = { x=row.world_x,y=row.world_y,z=row.bootstrap_z }
            row.block_building_requested = raw.block_building == true
            row.block_building = false -- Native arena volumes suspended in recovery build.
            local largest = 1.0
            for _,m in ipairs(row.members) do largest=math.max(largest,m.scale) end
            local spacing=row.member_spacing*largest
            local radius=#row.members>1 and spacing/(2*math.sin(math.pi/#row.members)) or 0.0
            if radius+spacing*0.5 > math.min(row.arena_radius,row.respawn_player_radius) then
                return nil,"spawners." .. id .. ": member formation exceeds arena/respawn radius; reduce spacing/scale or enlarge radii"
            end
            for index,m in ipairs(row.members) do
                local angle=2*math.pi*(index-1)/#row.members + math.rad(row.rotation_yaw)
                m.world_x=row.world_x+radius*math.cos(angle)
                m.world_y=row.world_y+radius*math.sin(angle)
                m.location={x=m.world_x,y=m.world_y,z=BOOTSTRAP_Z}
            end
            config.by_id[id:lower()] = row
            config.list[#config.list+1] = row
        end
    end
    table.sort(config.list,function(a,b) return a.id:lower()<b.id:lower() end)
    if #config.list==0 then return nil,"spawner config contains no enabled spawners" end
    return config
end

function Config.render_palschema(config)
    local entries = {}
    for _, row in ipairs(config.list) do
        for _, m in ipairs(row.members) do
            entries[#entries+1] = table.concat({
                "  {", '    "Type": "Sheet",',
                string.format('    "Location": { "X": %s, "Y": %s, "Z": %s },',
                    json_float(m.world_x),json_float(m.world_y),json_float(row.bootstrap_z)),
                string.format('    "Rotation": { "Pitch": %s, "Yaw": %s, "Roll": %s },',
                    json_float(row.rotation_pitch),json_float(row.rotation_yaw),json_float(row.rotation_roll)),
                '    "SpawnerName": ' .. json_string(m.native_id) .. ',',
                '    "SpawnerType": "FieldBoss",',
                '    "SpawnGroupList": [ { "Weight": 100, "PalList": [',
                string.format('      { "PalId": %s, "Level": %d, "Level_Max": %d, "Num": 1, "Num_Max": 1 }',
                    json_string(m.spawn_pal_id),m.level,m.level),
                '    ] } ]', "  }",
            },"\n")
        end
    end
    return "[\n" .. table.concat(entries,",\n") .. "\n]\n"
end

function Config.write_if_changed(path, content)
    local existing = io.open(path, "r")
    if existing then
        local previous = existing:read("*a")
        existing:close()
        if previous == content then return true, "unchanged" end
    end
    local file, open_error = io.open(path, "w")
    if not file then return false, "could not write generated PalSchema spawners: " .. tostring(open_error) end
    local ok, write_error = file:write(content)
    local close_ok, close_error = file:close()
    if not ok then return false, "could not write generated PalSchema spawners: " .. tostring(write_error) end
    if close_ok == nil then return false, "could not close generated PalSchema spawners: " .. tostring(close_error) end
    return true, "written"
end

return Config
