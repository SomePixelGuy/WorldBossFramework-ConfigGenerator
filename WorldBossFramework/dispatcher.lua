-- Lua-owned delayed work driven by an async clock and short-lived game-thread
-- submissions. The async callback never executes a queued job or touches an
-- Unreal object. At most one game-thread callback is outstanding at a time.
local Dispatcher = {}

function Dispatcher.new(start_clock, submit_game, report)
    local queue, tick, running = {}, 0, false
    local failed, completed, submissions, submit_failures = 0, 0, 0, 0
    local in_flight, flight_token, flight_started_tick = false, 0, 0
    local timeouts, handle = 0, nil
    local last_heartbeat, last_submission, last_completion = os.time(), 0, os.time()
    local interval, max_jobs, capacity = 100, 128, 4096
    local timeout_ticks = math.max(1, math.ceil(5000 / interval))

    local function log(message)
        if report then pcall(report, message) end
    end

    local function invoke(callback)
        local ok, err = pcall(callback)
        if not ok then failed = failed + 1; log("job failed: " .. tostring(err)) end
        completed = completed + 1
        return ok, err
    end

    local function has_due_work()
        for _, job in ipairs(queue) do
            if job.due <= tick then return true end
        end
        return false
    end

    local function pump(token)
        if token ~= flight_token then return end
        if running then return end
        running = true
        local batch = queue
        queue = {}
        local ready, count = {}, 0
        for _, job in ipairs(batch) do
            if job.due <= tick and count < max_jobs then
                count = count + 1
                ready[#ready + 1] = job
            else
                queue[#queue + 1] = job
            end
        end
        for _, job in ipairs(ready) do invoke(job.callback) end
        running = false
        in_flight = false
        last_completion = os.time()
    end

    local available, error_detail = false, "LoopAsync or ExecuteInGameThread unavailable"

    local function wake()
        tick = tick + 1
        last_heartbeat = os.time()
        if in_flight and tick - flight_started_tick >= timeout_ticks then
            timeouts = timeouts + 1
            in_flight = false
            flight_token = flight_token + 1
            log("game-thread submission timed out; superseding token")
        end
        if in_flight or not has_due_work() then return end

        in_flight = true
        flight_token = flight_token + 1
        flight_started_tick = tick
        local token = flight_token
        local function run()
            local ok, err = pcall(pump, token)
            if not ok then
                if token == flight_token then in_flight = false end
                failed = failed + 1
                log("game-thread pump failed: " .. tostring(err))
            end
        end
        local ok, why = submit_game(run)
        if ok then
            submissions = submissions + 1
            last_submission = os.time()
        else
            in_flight = false
            submit_failures = submit_failures + 1
            log("game-thread submission failed: " .. tostring(why))
        end
    end

    if type(start_clock) == "function" and type(submit_game) == "function" then
        local ok, value, detail = pcall(start_clock, interval, wake)
        available = ok and value ~= nil and value ~= false
        if available then
            handle = value
        else
            error_detail = ok and tostring(detail or value) or tostring(value)
        end
    end

    local api = {}

    function api.schedule(delay_ms, callback)
        if not available then return false, error_detail end
        if type(callback) ~= "function" then return false, "callback_required" end
        if #queue >= capacity then log("queue capacity reached"); return false, "dispatcher_queue_full" end
        local delay = tonumber(delay_ms) or 1
        if delay ~= delay or delay == math.huge or delay == -math.huge then return false, "invalid_delay" end
        queue[#queue + 1] = {
            due = tick + math.max(1, math.ceil(delay / interval)),
            callback = callback,
        }
        return true, "queued"
    end

    function api.call(callback)
        if type(callback) ~= "function" then return false, "callback_required" end
        if running then return invoke(callback) end
        return api.schedule(1, callback)
    end

    function api.status()
        return {
            ready = available,
            error = not available and error_detail or nil,
            handle = handle,
            tick = tick,
            pending = #queue,
            failed = failed,
            completed = completed,
            interval_ms = interval,
            last_heartbeat = last_heartbeat,
            last_submission = last_submission,
            last_completion = last_completion,
            in_flight = in_flight,
            submissions = submissions,
            submit_failures = submit_failures,
            timeouts = timeouts,
            persistent_game_callback = false,
        }
    end

    return api
end

return Dispatcher
