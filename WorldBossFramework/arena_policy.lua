-- Server-side Build-flag query overlay. No actors/components are constructed.
-- A registered UFunction hook is not proof that a native C++ caller uses it.
local Policy = {}

local function finite(v)
    local n = tonumber(v)
    if n and n == n and n ~= math.huge and n ~= -math.huge then return n end
end

function Policy.new(options)
    local arenas, hooks = {}, {}
    local counters = { queries=0, overrides=0, requests=0, unverified_requests=0, errors=0 }
    local request_stack = {}
    local function report(message)
        if options.report then pcall(options.report, "arena policy: " .. message) end
    end
    -- Snapshot only primitive config data; no reflected values survive callbacks.
    for _, row in ipairs(options.arenas or {}) do
        local x,y,r = finite(row.world_x),finite(row.world_y),finite(row.arena_radius)
        if row.block_building == true and x and y and r and r > 0 then
            arenas[#arenas+1] = {id=tostring(row.id),x=x,y=y,r=r}
        end
    end
    local function inside(x,y,padding)
        x,y,padding = finite(x),finite(y),finite(padding or 0)
        if not x or not y or not padding or padding < 0 then return nil end
        for _, a in ipairs(arenas) do
            if (x-a.x)^2+(y-a.y)^2 <= (a.r+padding)^2 then return a.id end
        end
    end
    local function enabled() return not options.enabled or options.enabled() == true end
    -- These are declared hook parameters, not arbitrary reflected values.
    local function xy(param)
        local v = param:get()
        return finite(v.X),finite(v.Y)
    end
    local function check(flag, position, padding)
        if not enabled() then return end
        local mask = finite(flag:get())
        if not mask or mask % 1 ~= 0 or (mask & 1) == 0 then return end
        counters.queries = counters.queries + 1
        local x,y = xy(position)
        local id = inside(x,y,padding)
        if id then
            counters.overrides = counters.overrides + 1
            local request = request_stack[#request_stack]
            if request and request.id then request.overrides=request.overrides+1 end
            return true -- Outside arenas return nil, preserving native restrictions.
        end
    end
    local function safe(fn)
        return function(...)
            local ok,result = pcall(fn,...)
            if ok then return result end
            counters.errors=counters.errors+1
            if counters.errors <= 3 then report("callback_error=" .. tostring(result)) end
            -- Do not reject unrelated construction on a malformed callback.
        end
    end
    local function install(name,pre,post)
        if hooks[name] then return true end
        local ok,a,b = pcall(options.register_hook,name,pre,post)
        if not ok or type(a)~="number" or type(b)~="number" then
            report("hook_failed=" .. name .. " detail=" .. tostring(a))
            return false
        end
        hooks[name]={a,b} -- Retain IDs; registration is performed once.
        return true
    end
    local noop = function() end
    local function request_pre(_,_,location)
        -- Stack is also used for outside requests so nested RPCs cannot borrow
        -- the outer request's observation. It contains no UObject references.
        local frame={overrides=0}
        request_stack[#request_stack+1]=frame
        if not enabled() then return end
        local x,y=xy(location)
        frame.id=inside(x,y)
        if frame.id then counters.requests=counters.requests+1 end
    end
    local function request_post()
        local frame=table.remove(request_stack)
        if not frame or not frame.id then return end
        if frame.overrides==0 then counters.unverified_requests=counters.unverified_requests+1 end
        if counters.requests<=5 or counters.requests%25==0 then
            report("build_request arena=" .. frame.id .. " query_overrides=" .. frame.overrides ..
                " enforcement=" .. (frame.overrides>0 and "query_observed_confirm_rejection_live" or "UNVERIFIED"))
        end
    end
    local api={}
    function api.install()
        if #arenas==0 then return true,"disabled_no_protected_arenas" end
        if type(options.register_hook)~="function" then return false,"RegisterHook unavailable" end
        local registered=0
        if install("/Script/Pal.PalUtility:PointOvelapLimitVolume",noop,safe(function(_,_,flag,location)
            return check(flag,location,0)
        end)) then registered=registered+1 end
        if install("/Script/Pal.PalUtility:SphereOverlapLimitVolume",noop,safe(function(_,_,flag,center,radius)
            local r=finite(radius:get())
            if r and r>=0 then return check(flag,center,r) end
        end)) then registered=registered+1 end
        if install("/Script/Pal.PalUtility:BoxOvelapLimitVolume",noop,safe(function(_,_,flag,center,extent)
            local e=extent:get()
            local x,y,z=finite(e.X),finite(e.Y),finite(e.Z)
            if x and y and z and x>=0 and y>=0 and z>=0 then
                -- A circumscribed sphere covers any box rotation. Conservative
                -- near the arena boundary; no quaternion/weak-reference access.
                return check(flag,center,math.sqrt(x*x+y*y+z*z))
            end
        end)) then registered=registered+1 end
        local observer=install("/Script/Pal.PalNetworkPlayerComponent:RequestBuild_ToServer",
            safe(request_pre),safe(request_post))
        return registered==3 and observer,"query_hooks=" .. registered .. "/3 request_observer=" .. tostring(observer) ..
            " protected_arenas=" .. #arenas .. " enforcement=requires_live_placement_check"
    end
    function api.status()
        return {queries=counters.queries,overrides=counters.overrides,requests=counters.requests,
            unverified_requests=counters.unverified_requests,errors=counters.errors,arenas=#arenas}
    end
    api.contains=inside
    return api
end
return Policy
