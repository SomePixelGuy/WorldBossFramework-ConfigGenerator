local Queue = {}
function Queue.build(rows,mode,random)
    random = random or math.random
    local out = {}
    for _, row in ipairs(rows) do if row.auto_enabled then out[#out+1]=row end end
    local function shuffle(first,last)
        for i=last,first+1,-1 do
            local j=random(first,i)
            out[i],out[j]=out[j],out[i]
        end
    end
    if mode=="random" then shuffle(1,#out)
    else
        table.sort(out,function(a,b)
            if a.queue_order==b.queue_order then return a.id<b.id end
            if mode=="descending" then return a.queue_order>b.queue_order end
            return a.queue_order<b.queue_order
        end)
        local first=1
        while first<=#out do
            local last=first
            while last<#out and out[last+1].queue_order==out[first].queue_order do last=last+1 end
            shuffle(first,last)
            first=last+1
        end
    end
    local ids={}
    for i,row in ipairs(out) do ids[i]=row.id end
    return ids
end
return Queue
