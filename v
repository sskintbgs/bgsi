-- Demonscan_master_scanner_v23.13.lua - Live Stats, Custom Filters, & Safe Webhooks
-- Updated: Custom Lua Table Parser for external JSON files
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()
local requestFunc = request or http_request or syn.request or http.request or fluxus.request or getgenv().request
if not requestFunc then warn("[-] No HTTP request function!") return end

-- Safe Clipboard Wrapper
local safeClipboard = setclipboard or toclipboard or set_clipboard or (Clipboard and Clipboard.set) or function() warn("Clipboard not supported on this executor.") end

-- Services & Remotes
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local CoreGui = game:GetService("CoreGui")
local RemoteFunction = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Framework"):WaitForChild("Network"):WaitForChild("Remote"):WaitForChild("RemoteFunction")
local RemoteEvent = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Framework"):WaitForChild("Network"):WaitForChild("Remote"):WaitForChild("RemoteEvent")

-- Files & Globals
local CACHE_FILE = "bgsi_global_v56.json"
local HISTORY_FILE = "bgsi_scan_history.json"
local SHARK_FILE = "shark_pets.json"
local SETTINGS_FILE = "bgsi_settings.json"
local UNMAPPED_FILE = "bgsi_unmapped.json"

local petCache = {}
local scanHistory = {}
local sharkList = {}  
local pendingUnmappedSet = {}

-- State Variables
local sharkEnabled = false
local isScanning = false
local isResyncing = false
local autoScanNewJoins = false
local skipAlreadyScanned = true
local webhookUrl = ""
local autoHop = false
local AutoGuess = false
local autoScanOnJoin = false
local showExtraWebhookInfo = false
local apiSyncDelay = 0.05
local webhookMinValue = 10000 -- Default minimum value for webhook lists
local isUiLoaded = false

-- Lifetime Stats Variables
local totalPetsScannedLifetime = 0
local totalPeopleScannedLifetime = 0
local totalServersJoinedLifetime = 0
local adminWebhookUrl = ""
local adminWebhookMessageId = ""
local adminLiveStatsEnabled = false

-- Data Loading (Standard JSON)
local function loadJSON(file)
    if isfile(file) then
        local s, c = pcall(readfile, file)
        if s and c then
            local dOk, loaded = pcall(HttpService.JSONDecode, HttpService, c)
            if dOk then return loaded end
        end
    end
    return {}
end

-- Data Loading (Custom Parser for Pet Cache allowing Lua Syntax)
local function loadPetCache(file)
    if isfile(file) then
        local s, c = pcall(readfile, file)
        if s and c then
            -- 1. Try standard JSON decode first
            local dOk, loaded = pcall(HttpService.JSONDecode, HttpService, c)
            if dOk and type(loaded) == "table" then return loaded end
            
            -- 2. Fallback: Parse raw Lua table syntax if user pasted it directly
            local parseStr = "local data = " .. c .. "\nreturn data"
            local func = loadstring(parseStr)
            if func then
                local lOk, luaTable = pcall(func)
                if lOk and type(luaTable) == "table" then
                    return luaTable
                end
            end
        end
    end
    return {}
end

local function formatPetCache(rawTable)
    local formatted = {}
    for k, v in pairs(rawTable) do
        local key = tostring(k):lower()
        if type(v) == "table" then
            if v[1] and v[2] ~= nil then
                -- Handled pasted format: {"Rarity", Value}
                formatted[key] = {
                    apiRarity = tostring(v[1]),
                    value = tonumber(v[2]) or 0,
                    eggType = "Unknown"
                }
            else
                -- Standard JSON format
                formatted[key] = {
                    value = tonumber(v.value) or tonumber(v.numericValue) or 0,
                    apiRarity = v.apiRarity or "Unknown",
                    eggType = v.eggType or "Unknown"
                }
            end
        end
    end
    return formatted
end

petCache = formatPetCache(loadPetCache(CACHE_FILE))
scanHistory = loadJSON(HISTORY_FILE)
sharkList = loadJSON(SHARK_FILE)
pendingUnmappedSet = loadJSON(UNMAPPED_FILE)

-- Load Settings
local savedSettings = loadJSON(SETTINGS_FILE)
webhookUrl = savedSettings.webhookUrl or ""
autoHop = savedSettings.autoHop or false
sharkEnabled = savedSettings.sharkEnabled or false
autoScanNewJoins = savedSettings.autoScanNewJoins or false
AutoGuess = savedSettings.AutoGuess or false
autoScanOnJoin = savedSettings.autoScanOnJoin or false
showExtraWebhookInfo = savedSettings.showExtraWebhookInfo or false
if savedSettings.apiSyncDelay ~= nil then apiSyncDelay = savedSettings.apiSyncDelay end
if savedSettings.skipAlreadyScanned ~= nil then skipAlreadyScanned = savedSettings.skipAlreadyScanned end
if savedSettings.webhookMinValue ~= nil then webhookMinValue = savedSettings.webhookMinValue end
totalPetsScannedLifetime = savedSettings.totalPetsScannedLifetime or 0
totalPeopleScannedLifetime = savedSettings.totalPeopleScannedLifetime or 0
totalServersJoinedLifetime = savedSettings.totalServersJoinedLifetime or 0
adminWebhookUrl = savedSettings.adminWebhookUrl or ""
adminWebhookMessageId = savedSettings.adminWebhookMessageId or ""
adminLiveStatsEnabled = savedSettings.adminLiveStatsEnabled or false

local function saveData()
    if writefile then
        pcall(writefile, CACHE_FILE, HttpService:JSONEncode(petCache))
        pcall(writefile, HISTORY_FILE, HttpService:JSONEncode(scanHistory))
        pcall(writefile, SHARK_FILE, HttpService:JSONEncode(sharkList))
        pcall(writefile, UNMAPPED_FILE, HttpService:JSONEncode(pendingUnmappedSet))
        pcall(writefile, SETTINGS_FILE, HttpService:JSONEncode({
            webhookUrl = webhookUrl,
            autoHop = autoHop,
            sharkEnabled = sharkEnabled,
            autoScanNewJoins = autoScanNewJoins,
            skipAlreadyScanned = skipAlreadyScanned,
            AutoGuess = AutoGuess,
            autoScanOnJoin = autoScanOnJoin,
            showExtraWebhookInfo = showExtraWebhookInfo,
            apiSyncDelay = apiSyncDelay,
            webhookMinValue = webhookMinValue,
            totalPetsScannedLifetime = totalPetsScannedLifetime,
            totalPeopleScannedLifetime = totalPeopleScannedLifetime,
            totalServersJoinedLifetime = totalServersJoinedLifetime,
            adminWebhookUrl = adminWebhookUrl,
            adminWebhookMessageId = adminWebhookMessageId,
            adminLiveStatsEnabled = adminLiveStatsEnabled
        }))
    end
end

-- ScreenGui HUD Setup
local hudGui = Instance.new("ScreenGui")
hudGui.Name = "BGSIScannerHUD"
hudGui.ResetOnSpawn = false
local protect = gethui or (syn and syn.protect_gui)
if protect then
    if syn and syn.protect_gui then syn.protect_gui(hudGui); hudGui.Parent = CoreGui else hudGui.Parent = protect() end
else
    hudGui.Parent = CoreGui
end
local statusLabel = Instance.new("TextLabel", hudGui)
statusLabel.Size = UDim2.new(0, 450, 0, 35)
statusLabel.Position = UDim2.new(0.5, -225, 0, 15)
statusLabel.BackgroundTransparency = 0.3
statusLabel.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
statusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
statusLabel.Font = Enum.Font.GothamBold
statusLabel.TextSize = 14
statusLabel.Text = "Status: Idle"
statusLabel.Visible = false
local uiCorner = Instance.new("UICorner", statusLabel)
uiCorner.CornerRadius = UDim.new(0, 8)
local uiStroke = Instance.new("UIStroke", statusLabel)
uiStroke.Color = Color3.fromRGB(60, 60, 60)
uiStroke.Thickness = 1

local function SetStatus(text, showHud)
    if statusLabel then
        statusLabel.Text = "📡 " .. text
        statusLabel.Visible = showHud or false
    end
end

-- Statistics & Utility
local function getDatabaseStats()
    local count, secrets, exclusives = 0, 0, 0
    for _, pet in pairs(petCache) do
        count = count + 1
        if pet.apiRarity == "Secret" then secrets = secrets + 1 end
        if pet.eggType == "Exclusive" then exclusives = exclusives + 1 end
    end
    return count, secrets, exclusives
end

local function stripPrefixes(name)
    local cleaned = tostring(name or ""):lower()
    local prefixes = {"shiny mythic xl ", "shiny mythic ", "mythic xl ", "shiny xl ", "shiny ", "mythic ", "xl ", "shiny giftbox ", "giftbox ", "og ", "vip ", ""}
    table.sort(prefixes, function(a, b) return #a > #b end)
    for _, p in ipairs(prefixes) do
        if cleaned:sub(1, #p) == p then return cleaned:sub(#p + 1) end
    end
    return cleaned
end

-- Formatting
local function formatInventoryForClipboard(name)
    local data = scanHistory[name]
    if not data or not data.map then return "No data found for " .. name end
    
    local lines = {"--- INVENTORY: " .. name .. " (" .. (data.date or "Unknown") .. ") ---"}
    local totalVal = 0
    local totalPetsCount = 0
    local petEntries = {}
    
    for petName, amount in pairs(data.map) do
        local info = petCache[petName] or {value = 0}
        local petValue = tonumber(info.value) or 0
        local totalForPet = petValue * amount
        table.insert(petEntries, {
            display = string.format("%s x%d | Value: %d (Total: %d)", petName:upper(), amount, petValue, totalForPet),
            totalValue = totalForPet,
            amount = amount
        })
        totalVal = totalVal + totalForPet
        totalPetsCount = totalPetsCount + amount
    end
    
    table.sort(petEntries, function(a, b)
        if a.totalValue ~= b.totalValue then return a.totalValue > b.totalValue end
        return a.amount > b.amount
    end)
    
    for _, entry in ipairs(petEntries) do table.insert(lines, entry.display) end
    table.insert(lines, "──────────────────────────────")
    table.insert(lines, "TOTAL PETS: " .. totalPetsCount)
    table.insert(lines, "TOTAL INVENTORY VALUE: " .. totalVal)
    return table.concat(lines, "\n")
end

-- API Sync Functions
local function fetchApi(url)
    local ok, resp = pcall(requestFunc, {Url = url, Method = "GET", Headers = {Accept = "application/json", Referer = "https://www.bgsi.gg/", Origin = "https://www.bgsi.gg"}})
    if ok and resp and (resp.StatusCode == 200 or resp.Success) then
        local dOk, data = pcall(HttpService.JSONDecode, HttpService, resp.Body)
        if dOk then return data end
    end
    return nil
end

local function processPet(obj)
    if not obj or not obj.id then return 0 end
    local key = tostring(obj.name):lower()
    local isNew = not petCache[key] and 1 or 0
    petCache[key] = {
        value = tonumber(obj.value) or tonumber(obj.numericValue) or 0,
        apiRarity = obj.rarity or "Unknown",
        eggType = obj.eggType or "Unknown"
    }
    return isNew
end

local function syncVariants(baseName)
    local slugVariations = {}
    local cleaned = stripPrefixes(baseName):gsub("%s+", "-"):gsub("[^%w%-]", ""):lower()
    table.insert(slugVariations, cleaned)
    table.insert(slugVariations, (cleaned:gsub("-", "")))
    table.insert(slugVariations, (cleaned:gsub("'", "")))
    table.insert(slugVariations, (cleaned:gsub("-", "_")))
    
    for _, slug in ipairs(slugVariations) do
        local data = fetchApi("https://api.bgsi.gg/api/items/" .. slug)
        if data and data.pet then
            local added = processPet(data.pet)
            if data.pet.allVariants then
                for _, v in ipairs(data.pet.allVariants) do added = added + processPet(v) end
            end
            return true, added
        end
        task.wait(apiSyncDelay)
    end
    return false, 0
end

-- Admin Webhook Editor (Edits 1 Message safely)
local function UpdateAdminWebhook()
    if not adminLiveStatsEnabled or adminWebhookUrl == "" then return end
    
    -- Strips query parameters (like ?wait=true) off the base URL so PATCH works
    local cleanUrl = string.match(adminWebhookUrl, "^([^%?]+)")
    if not cleanUrl then return end
    
    local embed = {
        title = "📊 Demonscan Global Stats (Live)",
        color = 3447003,
        fields = {
            {name = "🐾 Total Pets Scanned", value = tostring(totalPetsScannedLifetime), inline = true},
            {name = "👤 Total Players Scanned", value = tostring(totalPeopleScannedLifetime), inline = true},
            {name = "🌐 Total Servers Joined", value = tostring(totalServersJoinedLifetime), inline = true},
            {name = "Current Job ID", value = "```" .. game.JobId .. "```", inline = false}
        },
        footer = {text = "Demonscan Analytics • " .. os.date("%Y-%m-%d %H:%M:%S")},
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
    }
    local payload = HttpService:JSONEncode({embeds = {embed}})
    task.spawn(function()
        if adminWebhookMessageId == "" then
            -- Create message via POST
            local ok, res = pcall(requestFunc, {
                Url = cleanUrl .. "?wait=true",
                Method = "POST",
                Headers = {["Content-Type"] = "application/json"},
                Body = payload
            })
            if ok and type(res) == "table" and (res.StatusCode == 200 or res.StatusCode == 201) then
                local dOk, data = pcall(HttpService.JSONDecode, HttpService, res.Body)
                if dOk and data and data.id then
                    adminWebhookMessageId = data.id
                    saveData()
                end
            end
        else
            -- Edit existing message via PATCH
            local ok, res = pcall(requestFunc, {
                Url = cleanUrl .. "/messages/" .. adminWebhookMessageId,
                Method = "PATCH",
                Headers = {["Content-Type"] = "application/json"},
                Body = payload
            })
            -- If the message was deleted in Discord, 404 returns. Reset ID to create a new one.
            if ok and type(res) == "table" and res.StatusCode == 404 then
                adminWebhookMessageId = ""
                saveData()
                UpdateAdminWebhook()
            end
        end
    end)
end

-- UI Creation & Logic Hooks
local Window = Rayfield:CreateWindow({
    Name = "DemonScan v23.13",
    LoadingTitle = "Demonscan Initialization",
    LoadingSubtitle = "Ultimate Stability Edition",
    Theme = "Default"
})
local ScanTab = Window:CreateTab("Scanner", 4483362458)
local SharkTab = Window:CreateTab("Sharking", 4483362458)
local StatsTab = Window:CreateTab("Stats", 4483362458)
local HistoryTab = Window:CreateTab("History", 4483362458)
local DBTab = Window:CreateTab("Database", 4483362458)
local MiscTab = Window:CreateTab("Misc", 4483362458)

-- UI Helpers (Stats)
local StatsPetsLabel = StatsTab:CreateLabel("Total Pets Scanned: " .. totalPetsScannedLifetime)
local StatsPlayersLabel = StatsTab:CreateLabel("Total Players Scanned: " .. totalPeopleScannedLifetime)
local StatsServersLabel = StatsTab:CreateLabel("Total Servers Joined: " .. totalServersJoinedLifetime)
local function UpdateStatsUI()
    if StatsPetsLabel then StatsPetsLabel:Set("Total Pets Scanned: " .. totalPetsScannedLifetime) end
    if StatsPlayersLabel then StatsPlayersLabel:Set("Total Players Scanned: " .. totalPeopleScannedLifetime) end
    if StatsServersLabel then StatsServersLabel:Set("Total Servers Joined: " .. totalServersJoinedLifetime) end
end

StatsTab:CreateSection("Admin Live Stats Webhook")
StatsTab:CreateInput({
    Name = "Admin Webhook URL",
    CurrentValue = adminWebhookUrl,
    PlaceholderText = "https://discord.com/api/webhooks/...",
    Callback = function(v)
        adminWebhookUrl = v
        saveData()
    end
})
StatsTab:CreateToggle({
    Name = "Enable Live Editing Webhook",
    CurrentValue = adminLiveStatsEnabled,
    Callback = function(v)
        adminLiveStatsEnabled = v
        saveData()
        if v then UpdateAdminWebhook() end
    end
})
StatsTab:CreateButton({
    Name = "Force Send/Update Admin Webhook",
    Callback = function() UpdateAdminWebhook() end
})
StatsTab:CreateButton({
    Name = "Reset Webhook Message (Creates New Message)",
    Callback = function()
        adminWebhookMessageId = ""
        saveData()
        Rayfield:Notify({Title = "Reset", Content = "Message ID cleared. Will post fresh embed next scan.", Duration = 4})
        UpdateAdminWebhook()
    end
})

-- UI Helpers (Others)
local PendingPetsLabel = nil
local function UpdatePendingCounter()
    if not PendingPetsLabel then return end
    local count = 0
    for _ in pairs(pendingUnmappedSet) do count = count + 1 end
    PendingPetsLabel:Set("Pending Unmapped Pets: " .. count)
end

local DBStatsLabel = nil
local function refreshDBLabel()
    if DBStatsLabel then
        local c, s, e = getDatabaseStats()
        DBStatsLabel:Set("Database: " .. c .. " pets | " .. s .. " secrets | " .. e .. " exclusives")
    end
end

local ScanCounterLabel = ScanTab:CreateLabel("Scanned: 0 / 0")
local function updateScanCounter(scanned, total)
    ScanCounterLabel:Set("Scanned: " .. scanned .. " / " .. total)
end

local SelectedLive = nil
local SelectedHistory = nil
local PlayerDrop, HistDrop

local function refreshUI()
    local p, h = {}, {}
    for _, plr in ipairs(Players:GetPlayers()) do table.insert(p, plr.Name) end
    for name in pairs(scanHistory) do table.insert(h, name) end
    table.sort(p); table.sort(h)
    if PlayerDrop then PlayerDrop:Refresh(p, true) end
    if HistDrop then HistDrop:Refresh(h, true) end
    refreshDBLabel()
end

task.spawn(refreshUI)
Players.PlayerAdded:Connect(refreshUI)
Players.PlayerRemoving:Connect(refreshUI)

-- Server Hopper Function
local function hopServer()
    SetStatus("Hopping to new server...", true)
    local placeId = game.PlaceId
    local currentJobId = game.JobId
    local apiUrl = "https://games.roblox.com/v1/games/" .. placeId .. "/servers/Public?sortOrder=Asc&limit=100"
    local success, response = pcall(function() return HttpService:JSONDecode(game:HttpGet(apiUrl)) end)
    
    if success and response and response.data then
        local available = {}
        for _, server in ipairs(response.data) do
            if server.id ~= currentJobId and server.playing < server.maxPlayers then
                table.insert(available, server.id)
            end
        end
        if #available > 0 then
            TeleportService:TeleportToPlaceInstance(placeId, available[math.random(1, #available)])
        else
            SetStatus("No servers found. Try again later.", true)
            task.wait(3)
            SetStatus("Status: Idle", false)
        end
    else
        SetStatus("Failed to fetch servers.", true)
        task.wait(3)
        SetStatus("Status: Idle", false)
    end
end

-- Scanner Core
local function countTotalPets(t)
    local count = 0
    local function recurse(subT)
        if type(subT) ~= "table" then return end
        if subT.Name and subT.XP then count = count + 1 return end
        for _, v in pairs(subT) do recurse(v) end
    end
    recurse(t)
    return count
end

function RunScanner(playersToScan)
    if isScanning then return end
    isScanning = true
    
    local toScan = {}
    for _, plr in ipairs(playersToScan) do
        if not skipAlreadyScanned or not scanHistory[plr.Name] then table.insert(toScan, plr) end
    end
    
    local totalToScan = #toScan
    local scannedCount = 0
    updateScanCounter(scannedCount, totalToScan)
    
    if totalToScan == 0 then
        SetStatus("Nothing to scan (all already done)", true)
        task.wait(2)
        SetStatus("Status: Idle", false)
        isScanning = false
        if autoHop then hopServer() end
        return
    end
    
    local syncQueue = {}
    local newPetsFound = 0
    
    for i, plr in ipairs(toScan) do
        SetStatus("Scanning " .. plr.Name .. " (" .. i .. "/" .. totalToScan .. ")", true)
        
        local success, result = pcall(function() return RemoteFunction:InvokeServer("TradeViewInventory", plr) end)
        
        if not success or not result then
            SetStatus("Failed to scan " .. plr.Name, true)
            scannedCount = scannedCount + 1
            updateScanCounter(scannedCount, totalToScan)
            
            if i < totalToScan then
                SetStatus("Delaying 4s...", true)
                task.wait(4)
            end
            continue
        end
        
        local map = {}
        if sharkEnabled then
            local function fastExtract(t)
                if type(t) ~= "table" then return end
                if t.Name and t.XP then
                    local fullName = ((t.Shiny and "shiny " or "") .. (t.Mythic and "mythic " or "") .. (t.XL and "xl " or "") .. t.Name):lower()
                    map[fullName] = (map[fullName] or 0) + (tonumber(t.Amount) or 1)
                    
                    if not petCache[fullName] or petCache[fullName].value == 0 then
                        if not pendingUnmappedSet[t.Name] then
                            pendingUnmappedSet[t.Name] = true
                            UpdatePendingCounter()
                        end
                    end
                    return
                end
                for _, v in pairs(t) do fastExtract(v) end
            end
            fastExtract(result)
            scanHistory[plr.Name] = {map = map, date = os.date("%Y-%m-%d %H:%M:%S")}
        else
            local totalPets = countTotalPets(result)
            local processed = 0
            
            local function extract(t)
                if type(t) ~= "table" then return end
                if t.Name and t.XP then
                    local fullName = ((t.Shiny and "shiny " or "") .. (t.Mythic and "mythic " or "") .. (t.XL and "xl " or "") .. t.Name):lower()
                    map[fullName] = (map[fullName] or 0) + (tonumber(t.Amount) or 1)
                    
                    if not petCache[fullName] or petCache[fullName].value == 0 then
                        syncQueue[t.Name] = true
                        newPetsFound = newPetsFound + 1
                    end
                    
                    task.wait(0.005)
                    processed = processed + 1
                    local percent = math.floor((processed / totalPets) * 100 + 0.5)
                    SetStatus("Scanning " .. plr.Name .. ": " .. percent .. "% (" .. processed .. "/" .. totalPets .. ")", true)
                    return
                end
                for _, v in pairs(t) do extract(v) end
            end
            extract(result)
            scanHistory[plr.Name] = {map = map, date = os.date("%Y-%m-%d %H:%M:%S")}
        end
        
        -- Execute Lifetime Tracking immediately after scanning map is generated
        local petsThisScan = 0
        for _, amount in pairs(map) do petsThisScan = petsThisScan + amount end
        totalPetsScannedLifetime = totalPetsScannedLifetime + petsThisScan
        totalPeopleScannedLifetime = totalPeopleScannedLifetime + 1
        saveData()
        UpdateStatsUI()
        UpdateAdminWebhook()
        
        if sharkEnabled then
            local foundSharks = {}
            for _, targetPet in ipairs(sharkList) do
                local amount = map[targetPet]
                if amount and amount > 0 then
                    table.insert(foundSharks, {name = targetPet:upper(), amount = amount})
                end
            end
            
            if #foundSharks > 0 then
                local playerName = plr.Name
                local jobId = game.JobId
                local placeId = game.PlaceId
                local profileUrl = "https://www.roblox.com/users/" .. plr.UserId .. "/profile"
                local joinLink = "https://www.roblox.com/games/start?placeId=" .. placeId .. "&gameInstanceId=" .. jobId
                
                local sharkDesc = ""
                for _, s in ipairs(foundSharks) do
                    sharkDesc = sharkDesc .. s.amount .. "x **" .. s.name .. "**\n"
                end
                
                Rayfield:Notify({Title = "Demonscan Flag!", Content = playerName .. " has:\n" .. sharkDesc, Duration = 10})
                
                if webhookUrl ~= "" then
                    local embedsArray = {}
                    local embedFields = {
                        {name = "Job ID", value = "```" .. jobId .. "```", inline = true},
                        {name = "Place ID", value = tostring(placeId), inline = true},
                        {name = "Direct Join", value = "[Click to Join](" .. joinLink .. ")", inline = false}
                    }
                    
                    local secFiltered = {}
                    local excFiltered = {}
                    local legFiltered = {}
                    
                    if showExtraWebhookInfo then
                        local totalVal = 0
                        local totalSec = 0
                        local totalLeg = 0
                        local totalExc = 0
                        local totalPetsScanned = 0
                        
                        for petName, amount in pairs(map) do
                            local info = petCache[petName] or {value = 0, apiRarity = "Unknown", eggType = "Unknown"}
                            local val = tonumber(info.value) or 0
                            
                            totalVal = totalVal + (val * amount)
                            totalPetsScanned = totalPetsScanned + amount
                            
                            if info.apiRarity == "Secret" then
                                totalSec = totalSec + amount
                                if val >= webhookMinValue then
                                    table.insert(secFiltered, amount .. "x " .. petName:upper() .. " (Val: " .. val .. ")")
                                end
                            end
                            
                            if info.apiRarity == "Legendary" then
                                totalLeg = totalLeg + amount
                                if val >= webhookMinValue then
                                    table.insert(legFiltered, amount .. "x " .. petName:upper() .. " (Val: " .. val .. ")")
                                end
                            end
                            if info.eggType == "Exclusive" or info.apiRarity == "Exclusive" then
                                totalExc = totalExc + amount
                                if val >= webhookMinValue then
                                    table.insert(excFiltered, amount .. "x " .. petName:upper() .. " (Val: " .. val .. ")")
                                end
                            end
                        end
                        
                        table.insert(embedFields, {name = "🐾 Total Pets", value = tostring(totalPetsScanned), inline = true})
                        table.insert(embedFields, {name = "💰 Total Inv Value", value = tostring(totalVal), inline = true})
                        table.insert(embedFields, {name = "✨ Total Secrets", value = tostring(totalSec), inline = true})
                        table.insert(embedFields, {name = "🟡 Total Legendaries", value = tostring(totalLeg), inline = true})
                        table.insert(embedFields, {name = "🟣 Total Exclusives", value = tostring(totalExc), inline = true})
                    end
                    
                    local currentEmbed = {
                        title = "🚨 Flagged PET DETECTED!",
                        description = "**Player:** [" .. playerName .. "](" .. profileUrl .. ")\n**Has:**\n" .. sharkDesc,
                        color = 16711680,
                        fields = embedFields,
                        footer = {text = "Demonscan • " .. os.date("%Y-%m-%d %H:%M:%S")},
                        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
                    }
                    
                    local function addSafeField(name, val)
                        if #currentEmbed.fields >= 25 then
                            table.insert(embedsArray, currentEmbed)
                            currentEmbed = {
                                title = "🚨 Flagged PET DETECTED! (Continued)",
                                color = 16711680,
                                fields = {},
                                footer = {text = "Demonscan • " .. os.date("%Y-%m-%d %H:%M:%S")},
                                timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
                            }
                        end
                        table.insert(currentEmbed.fields, {name = name, value = val, inline = false})
                    end
                    if showExtraWebhookInfo then
                        local function chunkList(list, maxLen)
                            local chunks = {}
                            local currentStr = ""
                            for _, item in ipairs(list) do
                                if #currentStr + #item + 1 > maxLen then
                                    table.insert(chunks, currentStr)
                                    currentStr = item .. "\n"
                                else
                                    currentStr = currentStr .. item .. "\n"
                                end
                            end
                            if currentStr ~= "" then table.insert(chunks, currentStr) end
                            return chunks
                        end
                        local secChunks = chunkList(secFiltered, 1000)
                        local legChunks = chunkList(legFiltered, 1000)
                        local excChunks = chunkList(excFiltered, 1000)
                        
                        local threshStr = (webhookMinValue >= 1000 and (webhookMinValue / 1000) .. "k" or tostring(webhookMinValue))
                        for i, chunk in ipairs(secChunks) do addSafeField(i == 1 and "🔴 Secrets >" .. threshStr or "🔴 Secrets >" .. threshStr .. " (Cont.)", chunk) end
                        for i, chunk in ipairs(legChunks) do addSafeField(i == 1 and "🟡 Legendaries >" .. threshStr or "🟡 Legendaries >" .. threshStr .. " (Cont.)", chunk) end
                        for i, chunk in ipairs(excChunks) do addSafeField(i == 1 and "🟣 Exclusives >" .. threshStr or "🟣 Exclusives >" .. threshStr .. " (Cont.)", chunk) end
                    end
                    
                    table.insert(embedsArray, currentEmbed)
                    
                    local function sendEmbeds(embedGroup)
                        pcall(function()
                            requestFunc({
                                Url = webhookUrl, Method = "POST", Headers = {["Content-Type"] = "application/json"},
                                Body = HttpService:JSONEncode({
                                    content = "@everyone",
                                    embeds = embedGroup
                                })
                            })
                        end)
                    end
                    
                    local currentPayload = {}
                    for _, emb in ipairs(embedsArray) do
                        table.insert(currentPayload, emb)
                        if #currentPayload == 10 then
                            sendEmbeds(currentPayload)
                            currentPayload = {}
                            task.wait(1.5)
                        end
                    end
                    if #currentPayload > 0 then
                        sendEmbeds(currentPayload)
                    end
                end
            end
        end
        
        scannedCount = scannedCount + 1
        updateScanCounter(scannedCount, totalToScan)
        
        if i < totalToScan then
            SetStatus("Delaying 4s for " .. plr.Name .. "'s inventory...", true)
            task.wait(4)
        end
    end
    
    if newPetsFound > 0 then
        Rayfield:Notify({Title = "API Queue Update", Content = newPetsFound .. " new/missing-value pets queued for sync.", Duration = 5})
    end
    
    -- Processing API Queue
    local qList = {}
    for base in pairs(syncQueue) do table.insert(qList, base) end
    
    if #qList > 0 then
        SetStatus("Syncing " .. #qList .. " pets via API...", true)
        local totalAdded = 0
        for i, base in ipairs(qList) do
            if not isScanning then break end
            SetStatus("API Sync: " .. i .. "/" .. #qList .. " (" .. base .. ")", true)
            local success, thisAdded = syncVariants(base)
            totalAdded = totalAdded + thisAdded
            SetStatus("API Sync: " .. i .. "/" .. #qList .. " (" .. base .. ") - Added " .. thisAdded .. " (Total new: " .. totalAdded .. ")", true)
            task.wait(apiSyncDelay)
        end
    end
    
    saveData()
    refreshUI()
    SetStatus("Status: Idle", false)
    isScanning = false
    
    if autoHop then
        task.wait(1)
        hopServer()
    end
end

-- ===========================
-- SCANNER TAB
-- ===========================
PlayerDrop = ScanTab:CreateDropdown({Name = "Select Player", Options = {"Loading..."}, Callback = function(opt) SelectedLive = Players:FindFirstChild(opt[1]) end})
ScanTab:CreateButton({Name = "Scan Selected Player", Callback = function() if SelectedLive then RunScanner({SelectedLive}) end end})
ScanTab:CreateButton({Name = "Scan Entire Server", Callback = function() RunScanner(Players:GetPlayers()) end})
ScanTab:CreateToggle({Name = "Auto-Scan Server On Join/Execute (AFK)", CurrentValue = autoScanOnJoin, Callback = function(v) autoScanOnJoin = v; saveData(); end})
ScanTab:CreateToggle({Name = "Auto-Scan New Joins", CurrentValue = autoScanNewJoins, Callback = function(v) autoScanNewJoins = v; saveData(); end})
ScanTab:CreateToggle({Name = "Skip Already Scanned", CurrentValue = skipAlreadyScanned, Callback = function(v) skipAlreadyScanned = v; saveData(); end})

-- ===========================
-- SHARKING TAB
-- ===========================
local SharkListLabel = SharkTab:CreateLabel("Shark List: Empty")
local function updateSharkLabel() SharkListLabel:Set("Shark List:\n" .. table.concat(sharkList, "\n")) end
updateSharkLabel()
local sharkPetName, sharkRarity, sharkXL = "", "Normal", false
SharkTab:CreateInput({Name = "Pet Name", PlaceholderText = "e.g. Borealis Elk", Callback = function(v) sharkPetName = v end})
SharkTab:CreateDropdown({Name = "Rarity", Options = {"Normal", "Shiny", "Mythic", "Shiny Mythic"}, Callback = function(v) sharkRarity = v[1] end})
SharkTab:CreateToggle({Name = "Is XL?", Callback = function(v) sharkXL = v end})
SharkTab:CreateButton({
    Name = "Add Pet to Shark List",
    Callback = function()
        local prefix = ""
        if sharkRarity == "Shiny" then prefix = "shiny " end
        if sharkRarity == "Mythic" then prefix = "mythic " end
        if sharkRarity == "Shiny Mythic" then prefix = "shiny mythic " end
        local full = prefix .. (sharkXL and "xl " or "") .. sharkPetName:lower()
        if not table.find(sharkList, full) then
            table.insert(sharkList, full); saveData(); updateSharkLabel()
        end
    end
})
SharkTab:CreateButton({ Name = "Clear Shark List", Callback = function() sharkList = {}; saveData(); updateSharkLabel() end })

SharkTab:CreateSection("Sharking Settings")
SharkTab:CreateInput({Name = "Discord Webhook URL", CurrentValue = webhookUrl, PlaceholderText = "https://discord.com/api/webhooks/...", Callback = function(v) webhookUrl = v; saveData(); end})
SharkTab:CreateToggle({
    Name = "Show Extra Webhook Info (Value/Secrets/Filtered)", CurrentValue = showExtraWebhookInfo,
    Callback = function(v) showExtraWebhookInfo = v; saveData(); end
})
SharkTab:CreateToggle({
    Name = "Enable Shark Alerts (+ Webhook)", CurrentValue = sharkEnabled,
    Callback = function(v)
        sharkEnabled = v; saveData()
        if isUiLoaded and v then
            local oldSkip = skipAlreadyScanned
            skipAlreadyScanned = false
            RunScanner(Players:GetPlayers())
            skipAlreadyScanned = oldSkip
        end
    end
})
SharkTab:CreateToggle({
    Name = "Enable Server Hopping", CurrentValue = autoHop,
    Callback = function(v)
        autoHop = v; saveData()
        if isUiLoaded and v then
            sharkEnabled = true
            local oldSkip = skipAlreadyScanned
            skipAlreadyScanned = false
            RunScanner(Players:GetPlayers())
            skipAlreadyScanned = oldSkip
        end
    end
})

SharkTab:CreateSection("Webhook Value Filter")
SharkTab:CreateSlider({
    Name = "Min Webhook Pet Value",
    Range = {0, 100000},
    Increment = 100,
    Suffix = " Val",
    CurrentValue = math.clamp(webhookMinValue, 0, 100000),
    Flag = "WebhookMinValSlider",
    Callback = function(Value)
        webhookMinValue = Value
        saveData()
    end,
})
SharkTab:CreateInput({
    Name = "Custom Min Value (Overrides Slider)",
    PlaceholderText = "e.g. 150000",
    Callback = function(v)
        local parsed = tonumber(v)
        if parsed then
            webhookMinValue = parsed
            saveData()
            Rayfield:Notify({Title = "Filter Updated", Content = "Webhook min value set to " .. parsed, Duration = 3})
        end
    end
})

SharkTab:CreateSection("Unmapped Pets Cache")
PendingPetsLabel = SharkTab:CreateLabel("Pending Unmapped Pets: 0")
SharkTab:CreateButton({
    Name = "Map Pending Pets to DB",
    Callback = function()
        if isScanning or isResyncing then return Rayfield:Notify({Title = "Wait", Content = "Script is currently busy."}) end
        isResyncing = true
        task.spawn(function()
            -- Phase 1: Clean up pets already in database
            local cleanedCount = 0
            local toRemove = {}
            for baseName in pairs(pendingUnmappedSet) do
                local possibleKeys = {
                    baseName:lower(),
                    "shiny " .. baseName:lower(),
                    "mythic " .. baseName:lower(),
                    "shiny mythic " .. baseName:lower(),
                    "xl " .. baseName:lower(),
                    "shiny xl " .. baseName:lower(),
                    "mythic xl " .. baseName:lower(),
                    "shiny mythic xl " .. baseName:lower(),
                }
                local exists = false
                for _, key in ipairs(possibleKeys) do
                    if petCache[key] and petCache[key].value and petCache[key].value > 0 then
                        exists = true
                        break
                    end
                end
                if exists then
                    table.insert(toRemove, baseName)
                    cleanedCount = cleanedCount + 1
                end
            end
            -- Remove already mapped
            for _, base in ipairs(toRemove) do
                pendingUnmappedSet[base] = nil
            end
            if cleanedCount > 0 then
                Rayfield:Notify({
                    Title = "Cleaned Up",
                    Content = "Removed " .. cleanedCount .. " already existing pet(s) from pending list",
                    Duration = 4
                })
                UpdatePendingCounter()
                saveData()
            end
            
            -- Phase 2: Sync remaining pets
            local qList = {}
            for base in pairs(pendingUnmappedSet) do table.insert(qList, base) end
            
            if #qList == 0 then
                Rayfield:Notify({Title = "Done", Content = "No pets left to map (all already in DB)", Duration = 4})
                isResyncing = false
                SetStatus("Status: Idle", false)
                return
            end
            
            Rayfield:Notify({Title = "Syncing", Content = "Mapping " .. #qList .. " remaining pet(s)...", Duration = 4})
            local totalAdded = 0
            for i, base in ipairs(qList) do
                if not isResyncing then break end
                SetStatus("API Sync: " .. i .. "/" .. #qList .. " (" .. base .. ")", true)
                local success, thisAdded = syncVariants(base)
                totalAdded = totalAdded + thisAdded
                if success and thisAdded > 0 then
                    pendingUnmappedSet[base] = nil
                    UpdatePendingCounter()
                    saveData() -- incremental save
                end
                SetStatus("API Sync: " .. i .. "/" .. #qList .. " (" .. base .. ") - Added " .. thisAdded, true)
                task.wait(apiSyncDelay)
            end
            
            saveData()
            refreshUI()
            local remaining = 0 for _ in pairs(pendingUnmappedSet) do remaining = remaining + 1 end
            Rayfield:Notify({
                Title = "Mapping Complete",
                Content = "Added " .. totalAdded .. " new variant(s)\nPending pets remaining: " .. remaining,
                Duration = 6
            })
            isResyncing = false
            SetStatus("Status: Idle", false)
        end)
    end
})

-- ===========================
-- DATABASE TAB
-- ===========================
DBStatsLabel = DBTab:CreateLabel("Database: Loading...")
DBTab:CreateButton({Name = "Refresh Stats", Callback = refreshUI})

local ResyncLabel = DBTab:CreateLabel("Background Task Status: Idle")
DBTab:CreateSection("API Sync Settings")
DBTab:CreateSlider({
    Name = "API Sync Delay (Seconds)",
    Range = {0, 5},
    Increment = 0.01,
    Suffix = "s",
    CurrentValue = apiSyncDelay,
    Flag = "ApiSyncDelaySlider",
    Callback = function(Value)
        apiSyncDelay = Value
        saveData()
    end,
})

DBTab:CreateSection("Maintenance")
DBTab:CreateButton({
    Name = "Resync Entire Database (Full API Fetch)",
    Callback = function()
        if isResyncing then return end
        isResyncing = true
        task.spawn(function()
            petCache = {}
            local page, totalPages, fetchedPets = 1, 1, 0
            while page <= totalPages do
                if not isResyncing then break end
                ResyncLabel:Set("Fetching page " .. page .. "/" .. totalPages .. "...")
                local data = fetchApi("https://api.bgsi.gg/api/items?page=" .. page)
                if data and data.pets then
                    totalPages = data.pages or totalPages
                    for _, petData in ipairs(data.pets) do
                        local added = processPet(petData)
                        if petData.allVariants then for _, v in ipairs(petData.allVariants) do added = added + processPet(v) end end
                        fetchedPets = fetchedPets + added
                    end
                else
                    break
                end
                page = page + 1; task.wait(apiSyncDelay)
            end
            saveData(); refreshDBLabel(); isResyncing = false
            ResyncLabel:Set("Full resync complete (" .. fetchedPets .. " pets).")
        end)
    end
})
DBTab:CreateButton({ Name = "Stop Tasks", Callback = function() isResyncing = false end })

-- ===========================
-- HISTORY TAB
-- ===========================
HistDrop = HistoryTab:CreateDropdown({Name = "Select Scanned Person", Options = {}, Callback = function(opt) SelectedHistory = opt[1] end})
HistoryTab:CreateButton({
    Name = "Copy Selected Inventory (Value Sorted)",
    Callback = function()
        if SelectedHistory then
            safeClipboard(formatInventoryForClipboard(SelectedHistory))
            Rayfield:Notify({Title = "Copied!", Content = "Inventory of " .. SelectedHistory .. " copied.", Duration = 4})
        end
    end
})
HistoryTab:CreateButton({
    Name = "Clear Scan History",
    Callback = function()
        scanHistory = {}
        saveData()
        refreshUI()
        Rayfield:Notify({Title = "Cleared!", Content = "Scan history has been wiped. You can now scan everyone again.", Duration = 4})
    end
})

-- ===========================
-- MISC TAB (Cleaned Up Extras)
-- ===========================
MiscTab:CreateSection("Server Management")
MiscTab:CreateButton({
    Name = "Copy Current Server Join Link",
    Callback = function()
        safeClipboard("https://www.roblox.com/games/start?placeId=" .. game.PlaceId .. "&gameInstanceId=" .. game.JobId)
        Rayfield:Notify({Title = "Copied!", Content = "Server join link copied to clipboard.", Duration = 4})
    end
})
MiscTab:CreateButton({
    Name = "Copy Current JobID",
    Callback = function()
        safeClipboard(game.JobId)
        Rayfield:Notify({Title = "Copied!", Content = "JobID copied to clipboard.", Duration = 4})
    end
})
local customJobId = ""
MiscTab:CreateInput({Name = "Custom JobId to Join", PlaceholderText = "Enter JobId", Callback = function(v) customJobId = v end})
MiscTab:CreateButton({
    Name = "Join Custom JobId",
    Callback = function()
        if customJobId ~= "" then
            TeleportService:TeleportToPlaceInstance(game.PlaceId, customJobId)
        end
    end
})

MiscTab:CreateSection("Minigames")
MiscTab:CreateToggle({
    Name = "Auto Guess Pet (Minigame)", CurrentValue = AutoGuess,
    Callback = function(v) AutoGuess = v; saveData(); end
})

MiscTab:CreateSection("Exist Checker")
local ExistBox = MiscTab:CreateLabel("Exists: Waiting...")
local eN, eR, eX = "", "Normal", false
MiscTab:CreateInput({Name = "Pet Name", PlaceholderText = "e.g. Borealis Elk", Callback = function(v) eN = v end})
MiscTab:CreateDropdown({Name = "Rarity", Options = {"Normal","Shiny","Mythic","Shiny Mythic"}, Callback = function(v) eR = v[1] end})
MiscTab:CreateToggle({Name = "XL?", Callback = function(v) eX = v end})
MiscTab:CreateButton({
    Name = "Check Existence",
    Callback = function()
        local query = (eX and "XL " or "") .. (eR ~= "Normal" and eR .. " " or "") .. eN
        ExistBox:Set("Checking " .. query .. "...")
        task.spawn(function()
            local ok, res = pcall(function() return RemoteFunction:InvokeServer("GetExisting", query) end)
            ExistBox:Set(ok and query .. ": " .. tostring(res) or "Error checking existence")
        end)
    end
})

-- Background Event Listeners
Players.PlayerAdded:Connect(function(newPlayer)
    if autoScanNewJoins and not isScanning and (not skipAlreadyScanned or not scanHistory[newPlayer.Name]) then
        task.spawn(function()
            SetStatus("Auto-scanning new join: " .. newPlayer.Name, true)
            RunScanner({newPlayer})
        end)
    end
end)

RemoteEvent.OnClientEvent:Connect(function(action, data)
    if AutoGuess and action == "GuessPetStateChanged" and type(data) == "table" and data.State == "Guessing" then
        RemoteEvent:FireServer("GuessPet", data.CurrentPet)
    end
end)

-- Initialize Server Tracking
totalServersJoinedLifetime = totalServersJoinedLifetime + 1
saveData()
UpdateStatsUI()
UpdateAdminWebhook()

-- UI is completely finished loading
isUiLoaded = true
UpdatePendingCounter()

-- Auto Execute Initializer
if autoScanOnJoin then
    task.spawn(function()
        task.wait(5)
        RunScanner(Players:GetPlayers())
    end)
end
