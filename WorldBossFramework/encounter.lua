-- One logical encounter, independent native child spawners and member ledgers.
-- No UObject references survive a bridge call.
local Encounter = {}

function Encounter.new(native, callbacks)
    local E = {}
    local function current(s) return callbacks.current(s) and not s.finished end
    local function report(s, text) callbacks.log("encounter " .. s.token .. ": " .. text) end
    local function complete_callback(s, ok, why)
        if s.summon_done then
            local done = s.summon_done
            s.summon_done = nil
            pcall(done, ok, why, { token=s.token, spawner_id=s.spawner_id, source=s.source, title=s.title })
        end
    end
    local function all_terminal(s)
        for _, m in ipairs(s.members) do if not m.terminal then return false end end
        return true
    end
    function E.finish(s, reason)
        if not current(s) or s.release_pending then return false end
        if not s.completion_notified then
            s.completion_notified = true
            if callbacks.completing then pcall(callbacks.completing, s, reason) end
        end
        s.release_pending, s.status = true, "releasing"
        s.release_reason, s.release_started = reason, os.time()
        s.release_generation = (s.release_generation or 0) + 1
        local generation = s.release_generation
        local remaining, failed = #s.members, false
        for _, m in ipairs(s.members) do
            local called = false
            local function released(ok, why)
                if called or s.finished or generation ~= s.release_generation then return end
                called = true
                if not ok then failed = true report(s, "release failed " .. m.profile.full_name .. ": " .. tostring(why)) end
                remaining = remaining - 1
                if remaining == 0 then
                    s.finished, s.status, s.release_pending = true, reason, false
                    complete_callback(s, false, reason)
                    callbacks.finished(s, reason, not failed)
                end
            end
            local queued, why = native.release_spawner(m.profile.full_name, released)
            if not queued then released(false, why) end
        end
        return true
    end
    function E.terminal(s, id, reason)
        if not current(s) or s.release_pending then return false end
        local m = s.ids[tostring(id):upper()]
        if not m or m.terminal then return false end
        m.terminal, m.reason = true, reason
        s.ids[m.id] = nil
        native.lock_spawner(m.profile.full_name)
        report(s, "member=" .. m.profile.index .. " ended reason=" .. reason)
        if all_terminal(s) then E.finish(s, s.suppress_rewards and "admin_kill" or reason) end
        return true
    end
    local function capture(s, m, detail)
        if m.terminal or m.id or s.retired[detail.id] or s.ids[detail.id] then return false end
        local spawner = native.inspect_spawner(m.profile.full_name)
        -- Never guess by species/position alone. A missing/zero group GUID
        -- defers correlation and respawning rather than applying the wrong profile.
        if not spawner or not spawner.group or spawner.group == "" or spawner.group == "none"
            or spawner.group ~= detail.group
            or tostring(detail.species):lower() ~= m.profile.spawn_pal_id:lower()
            or tonumber(detail.level) ~= m.profile.level then return false end
        local alive,why = native.is_alive(detail.id)
        if not alive and (why == "not_loaded" or why == "despawned_shell") then return false end
        m.id, m.missing, m.retry_at = detail.id, 0, 0
        s.ids[detail.id] = m
        s.order[#s.order+1] = detail.id
        if not m.spawned_once then m.spawned_once=true s.count=s.count+1 end
        if not alive then
            -- A member can die between construction and the first polling tick.
            E.terminal(s,detail.id,"confirmed_dead_state")
            return true
        end
        native.lock_spawner(m.profile.full_name)
        local ok, result = native.apply_profile(detail.id, m.profile)
        if not current(s) or m.terminal then return true end
        report(s, "member=" .. m.profile.index .. " pal=" .. detail.id .. " profile=" ..
            (ok and "applied" or "partial") .. " steps=" .. tostring(type(result)=="table" and result.steps or result))
        if callbacks.captured then callbacks.captured(s, detail.id) end
        if s.aggro_player and native.share_aggro then native.share_aggro({detail.id},s.aggro_player) end
        if s.count == s.expected_count and not s.controller_spawned and not s.suppress_rewards then
            s.controller_spawned, s.status = true, "spawned"
            callbacks.spawned(s)
            complete_callback(s, true)
        end
        return true
    end
    function E.scan(s)
        if not current(s) or s.release_pending or s.scanning then return 0 end
        -- Reflected reads/profile setters can re-enter npc.spawn on this thread.
        -- Claim the entire scan before the first bridge call.
        s.scanning = true
        local found, cache = 0, {}
        local ok, err = pcall(function()
        for _, m in ipairs(s.members) do
            if not m.terminal and not m.id and m.requested then
                local species = m.profile.spawn_pal_id
                if not cache[species] then cache[species] = native.new_pals(species, {}) or {} end
                for _, detail in ipairs(cache[species]) do
                    if not s.baseline[detail.id] and capture(s,m,detail) then found=found+1 break end
                end
            end
        end
        end)
        s.scanning = false
        if not ok then report(s,"scan failed: " .. tostring(err)) end
        return found
    end
    function E.reconcile(s)
        if not current(s) then return false end
        for _, m in ipairs(s.members) do
            if m.id and not m.terminal then
                local alive, why = native.is_alive(m.id)
                if not alive and why ~= "not_loaded" and why ~= "despawned_shell" then
                    E.terminal(s,m.id,"confirmed_dead_state")
                end
            end
        end
        return s.finished == true
    end
    function E.damage(s,record)
        if not current(s) or s.release_pending or not s.ids[record.id] or not record.player_uid then return false end
        if s.aggro_player==record.player_uid and s.aggro_at==os.time() then return false end
        s.aggro_player,s.aggro_at=record.player_uid,os.time()
        local ids={}
        for id,m in pairs(s.ids) do if not m.terminal then ids[#ids+1]=id end end
        if native.share_aggro then
            local ok,why=native.share_aggro(ids,record.player_uid)
            report(s,"group aggression player=" .. record.player_uid .. " result=" .. tostring(ok) .. " " .. tostring(why))
            return ok
        end
        return false
    end
    local function request(s,m,respawn)
        if not current(s) or s.release_pending or s.suppress_rewards or m.inflight or m.terminal then return end
        m.inflight, m.requested, m.retry_at = true, true, os.time()+10
        local callback_called = false
        local function done(ok,why)
            if callback_called then return end
            callback_called = true
            m.inflight = false
            if not current(s) then native.lock_spawner(m.profile.full_name) return end
            m.retry_at = os.time()+10
            report(s,"member=" .. m.profile.index .. " request=" .. (ok and "accepted" or tostring(why)))
            E.scan(s)
        end
        local fn = respawn and native.respawn_spawner or native.trigger_spawner
        local queued, why = fn(m.profile.full_name,s.relock_delay,done)
        if not queued then done(false,why) end
    end
    function E.tick(s)
        if not current(s) then return end
        if s.release_pending then
            if os.time() - (s.release_started or os.time()) >= 5 then
                if (s.release_generation or 0)>=3 then
                    s.finished,s.release_pending,s.status=true,false,"release_timeout"
                    report(s,"release timed out after three attempts; arena blocked, controller released")
                    complete_callback(s,false,"release_timeout")
                    callbacks.finished(s,s.release_reason,false)
                    return
                end
                report(s,"release callback timeout; retrying idempotent native release")
                s.release_pending = false
                E.finish(s,s.release_reason)
            end
            return
        end
        if all_terminal(s) then E.finish(s,s.suppress_rewards and "admin_kill" or "confirmed_dead_state") return end
        E.scan(s)
        E.reconcile(s)
        if not current(s) or s.release_pending then return end
        local nearby
        for _, m in ipairs(s.members) do
            if not m.terminal then
                local alive, why = false, "not_spawned"
                if m.id then alive,why = native.is_alive(m.id) end
                if alive then m.missing=0
                else m.missing=(m.missing or 0)+1 end
                if not alive and m.missing >= 2 and not m.inflight and os.time() >= (m.retry_at or 0)
                    and not s.suppress_rewards then
                    if nearby == nil then
                        local result = native.players_near(s.location,s.respawn_player_radius)
                        nearby = result and tonumber(result.count) and result.count>0 or false
                    end
                    local spawner = nearby and native.inspect_spawner(m.profile.full_name) or nil
                    if spawner and spawner.ground_resolved then
                        -- If an occupied group has never been correlated, its Pal
                        -- may already exist. Never clear that flag blindly.
                        local safe = m.id ~= nil or spawner.spawned == false
                        if safe then
                            if m.id then
                                s.retired[m.id],s.ids[m.id] = true,nil
                                m.id = nil
                            end
                            m.missing=0
                            request(s,m,m.requested)
                        end
                    end
                end
            end
        end
    end
    local function schedule(s)
        if not current(s) then return end
        local ok,why = native.schedule(1000,function()
            if not current(s) then return end
            E.tick(s)
            schedule(s)
        end)
        if not ok then report(s,"monitor stopped: " .. tostring(why)) end
    end
    function E.start(s,configured)
        s.members,s.ids,s.order,s.retired,s.baseline = {},{},{},{},{}
        s.count,s.expected_count,s.status = 0,#configured.members,"awaiting_spawn"
        for _, profile in ipairs(configured.members) do
            for id in pairs(native.snapshot(profile.spawn_pal_id) or {}) do s.baseline[id]=true end
            s.members[#s.members+1] = { profile=profile,missing=0 }
        end
        for _, m in ipairs(s.members) do request(s,m,false) end
        schedule(s)
    end
    function E.kill(s,done)
        if not current(s) or s.release_pending then return false,"encounter_ending" end
        E.scan(s)
        -- Mark suppression BEFORE any native death callback can fire.
        s.suppress_rewards,s.status = true,"admin_kill_pending"
        local pending, failed = 1, {}
        local function result(ok,why)
            if not ok then failed[#failed+1]=tostring(why) end
            pending=pending-1
            if pending==0 then
                if all_terminal(s) and current(s) then E.finish(s,"admin_kill") end
                done(#failed==0,table.concat(failed,", "))
            end
        end
        for _, m in ipairs(s.members) do
            if not m.terminal then
                if m.id then
                    pending=pending+1
                    local called=false
                    local function killed(ok,why)
                        if called then return end
                        called=true
                        if ok then E.terminal(s,m.id,"admin_kill") end
                        result(ok,why)
                    end
                    local queued,why = native.kill(m.id,killed)
                    if not queued then killed(false,why) end
                elseif not m.inflight and os.time() >= (m.retry_at or 0) then
                    local spawner = native.inspect_spawner(m.profile.full_name)
                    if spawner and spawner.spawned == false then m.terminal=true
                    else failed[#failed+1]="member_" .. m.profile.index .. "_unresolved" end
                else failed[#failed+1]="member_" .. m.profile.index .. "_spawn_in_flight" end
            end
        end
        result(true)
        return true
    end
    return E
end
return Encounter
