-- mara: ESP (box, health, skeleton), head expander, triggerbot. Menu via mara_ui.lua (INSERT).

if getgenv().__mara_unload then pcall(getgenv().__mara_unload) end

local Players   = game:GetService("Players")
local RunService = game:GetService("RunService")

local MaraUI = getgenv().MaraUI or loadstring(readfile("mara_ui.lua"))()

local LocalPlayer = Players.LocalPlayer
local Camera      = workspace.CurrentCamera
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    Camera = workspace.CurrentCamera
end)

local Settings = {
    Enabled      = true,
    Boxes        = true,
    HealthBars   = true,
    Skeleton     = true,
    Color        = Color3.fromRGB(232, 96, 74),
    HeadExpander = false,
    HeadSize     = 6,
    TriggerBot   = false,
}

local schema = {
    { name = "visuals", rows = {
        { type = "toggle", key = "Enabled",    label = "ESP" },
        { type = "toggle", key = "Boxes",      label = "Box" },
        { type = "toggle", key = "HealthBars", label = "Health bar" },
        { type = "toggle", key = "Skeleton",   label = "Skeleton" },
    }},
    { name = "hitbox", rows = {
        { type = "toggle", key = "HeadExpander", label = "Head expander" },
        { type = "slider", key = "HeadSize",     label = "Head size", min = 2, max = 12, step = 0.5 },
    }},
    { name = "combat", rows = {
        { type = "toggle", key = "TriggerBot", label = "Triggerbot" },
    }},
}

local menu = MaraUI.new(Settings, schema)

------------------------------------------------------------------------
-- enemy resolution. Characters live under workspace.Characters; a player
-- can have two models, the real one carries the Player attribute.
------------------------------------------------------------------------

local function enemyModels()
    local out, chars = {}, workspace:FindFirstChild("Characters")
    if not chars then return out end
    local own = LocalPlayer.Character
    for _, m in ipairs(chars:GetChildren()) do
        if m:IsA("Model") and m ~= own and m:FindFirstChildOfClass("Humanoid") then
            if m:GetAttribute("Player") ~= nil or m.Name ~= LocalPlayer.Name then
                table.insert(out, m)
            end
        end
    end
    return out
end

local function isAlive(m)
    local hum = m and m:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return false end
    if m:GetAttribute("Ghost") == true then return false end
    if m:FindFirstChildOfClass("ForceField") then return false end
    if hum:HasTag("Dead") then return false end
    return true
end

------------------------------------------------------------------------
-- esp drawings
------------------------------------------------------------------------

local R15Bones = {
    { "Head", "UpperTorso" }, { "UpperTorso", "LowerTorso" },
    { "UpperTorso", "LeftUpperArm" }, { "LeftUpperArm", "LeftLowerArm" }, { "LeftLowerArm", "LeftHand" },
    { "UpperTorso", "RightUpperArm" }, { "RightUpperArm", "RightLowerArm" }, { "RightLowerArm", "RightHand" },
    { "LowerTorso", "LeftUpperLeg" }, { "LeftUpperLeg", "LeftLowerLeg" }, { "LeftLowerLeg", "LeftFoot" },
    { "LowerTorso", "RightUpperLeg" }, { "RightUpperLeg", "RightLowerLeg" }, { "RightLowerLeg", "RightFoot" },
}
local R6Bones = {
    { "Head", "Torso" },
    { "Torso", "Left Arm" }, { "Torso", "Right Arm" },
    { "Torso", "Left Leg" }, { "Torso", "Right Leg" },
}
local MAX_BONES = #R15Bones

local function drawing(kind, props)
    local d = Drawing.new(kind)
    for k, v in pairs(props) do d[k] = v end
    return d
end

local Esp = {}

local function newEntry()
    local bones = {}
    for i = 1, MAX_BONES do
        bones[i] = drawing("Line", { Thickness = 1.2, Color = Settings.Color, Transparency = 0.9, Visible = false })
    end
    return {
        Outline = drawing("Square", { Thickness = 3, Color = Color3.new(0, 0, 0), Filled = false, Visible = false }),
        Box     = drawing("Square", { Thickness = 1, Color = Settings.Color, Filled = false, Visible = false }),
        BarBack = drawing("Square", { Thickness = 1, Color = Color3.new(0, 0, 0), Filled = true, Visible = false }),
        Bar     = drawing("Square", { Thickness = 1, Filled = true, Visible = false }),
        Bones   = bones,
    }
end

local function destroyEntry(e)
    for k, d in pairs(e) do
        if k == "Bones" then
            for _, l in ipairs(d) do l:Remove() end
        else
            d:Remove()
        end
    end
end

local function hideEntry(e)
    e.Outline.Visible, e.Box.Visible = false, false
    e.BarBack.Visible, e.Bar.Visible = false, false
    for _, l in ipairs(e.Bones) do l.Visible = false end
end

local function projectBox(model)
    local root = model:FindFirstChild("HumanoidRootPart")
    local head = model:FindFirstChild("Head")
    if not root or not head then return nil end
    local top, topOn = Camera:WorldToViewportPoint(head.Position + Vector3.new(0, 0.7, 0))
    local bot, botOn = Camera:WorldToViewportPoint(root.Position - Vector3.new(0, 3, 0))
    if not (topOn and botOn) or top.Z <= 0 or bot.Z <= 0 then return nil end
    local h = math.abs(bot.Y - top.Y)
    local w = h * 0.55
    return Vector2.new(top.X - w / 2, top.Y), Vector2.new(w, h)
end

local RED, GREEN = Color3.fromRGB(230, 60, 60), Color3.fromRGB(80, 220, 110)

local function updateEsp(model, e)
    local hum = model:FindFirstChildOfClass("Humanoid")
    if not Settings.Enabled or not isAlive(model) then
        hideEntry(e)
        return
    end

    local pos, size = projectBox(model)
    if not pos then
        hideEntry(e)
        return
    end

    e.Outline.Visible = Settings.Boxes
    e.Box.Visible     = Settings.Boxes
    if Settings.Boxes then
        e.Outline.Position, e.Outline.Size = pos, size
        e.Box.Position, e.Box.Size = pos, size
        e.Box.Color = Settings.Color
    end

    e.BarBack.Visible = Settings.HealthBars
    e.Bar.Visible     = Settings.HealthBars
    if Settings.HealthBars then
        local frac = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
        local barX = pos.X - 6
        e.BarBack.Position = Vector2.new(barX - 1, pos.Y - 1)
        e.BarBack.Size     = Vector2.new(4, size.Y + 2)
        e.Bar.Position     = Vector2.new(barX, pos.Y + size.Y * (1 - frac))
        e.Bar.Size         = Vector2.new(2, size.Y * frac)
        e.Bar.Color        = RED:Lerp(GREEN, frac)
    end

    local bones = hum.RigType == Enum.HumanoidRigType.R15 and R15Bones or R6Bones
    for i, line in ipairs(e.Bones) do
        local pair = bones[i]
        local a = pair and model:FindFirstChild(pair[1])
        local b = pair and model:FindFirstChild(pair[2])
        if Settings.Skeleton and a and b then
            local pa, oa = Camera:WorldToViewportPoint(a.Position)
            local pb, ob = Camera:WorldToViewportPoint(b.Position)
            if oa and ob and pa.Z > 0 and pb.Z > 0 then
                line.From = Vector2.new(pa.X, pa.Y)
                line.To = Vector2.new(pb.X, pb.Y)
                line.Color = Settings.Color
                line.Visible = true
            else
                line.Visible = false
            end
        else
            line.Visible = false
        end
    end
end

------------------------------------------------------------------------
-- head expander. Client-side only: the audit found the client sends the
-- hit instance to the server, server acceptance of a resized head is unverified.
-- Limbs and root are never touched, so nothing gets anchored or frozen.
------------------------------------------------------------------------

local headState = setmetatable({}, { __mode = "k" })

local function applyHead(model)
    local head = model:FindFirstChild("Head")
    if not head or not head:IsA("BasePart") then return end
    local st = headState[head]
    if not st then
        st = { size = head.Size, collide = head.CanCollide, massless = head.Massless }
        headState[head] = st
    end
    if Settings.HeadExpander then
        local s = Settings.HeadSize
        local target = Vector3.new(s, s, s)
        if head.Size ~= target then head.Size = target end
        head.CanCollide = false
        head.Massless = true
    elseif head.Size ~= st.size then
        head.Size = st.size
        head.CanCollide = st.collide
        head.Massless = st.massless
    end
end

local function restoreHeads()
    for head, st in pairs(headState) do
        if head.Parent then
            head.Size = st.size
            head.CanCollide = st.collide
            head.Massless = st.massless
        end
    end
    table.clear(headState)
end

------------------------------------------------------------------------
-- triggerbot. Ray from the crosshair; the first thing hit must be an
-- enemy head/limb, and the shot only fires when the client math says
-- that hit kills. Server decides the real outcome.
------------------------------------------------------------------------

local FIRE_INTERVAL = 1 / 0.8
local lastShot = 0

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function killsOnHit(model, part)
    local hum = model:FindFirstChildOfClass("Humanoid")
    if not hum then return false end
    local strikesMax = hum:GetAttribute("HStrikesMax")
    if strikesMax then
        return (hum:GetAttribute("HStrikes") or 0) + 1 >= strikesMax
    end
    if part.Name == "Head" then return true end
    local dmg = (part.Name == "Left Leg" or part.Name == "Right Leg") and 75 or 100
    return hum.Health - dmg <= 0
end

local function enemyOwnerOf(part, chars)
    local cur = part
    while cur and cur.Parent do
        if cur.Parent == chars then return cur end
        cur = cur.Parent
    end
    return nil
end

local function triggerTick()
    if not (Settings.TriggerBot and Settings.Enabled) then return end
    if not isAlive(LocalPlayer.Character) then return end
    if os.clock() - lastShot < FIRE_INTERVAL then return end

    local chars = workspace:FindFirstChild("Characters")
    if not chars then return end

    rayParams.FilterDescendantsInstances = {
        LocalPlayer.Character, workspace.CurrentCamera, workspace:FindFirstChild("Debris"),
    }
    local cf = Camera.CFrame
    local res = workspace:Raycast(cf.Position, cf.LookVector * 1000, rayParams)
    if not res or not res.Instance then return end

    local model = enemyOwnerOf(res.Instance, chars)
    if not model or not model:IsA("Model") or model == LocalPlayer.Character then return end
    if not isAlive(model) then return end
    if not killsOnHit(model, res.Instance) then return end

    lastShot = os.clock()
    if mouse1click then mouse1click() end
end

------------------------------------------------------------------------
-- loops
------------------------------------------------------------------------

local heartConn = RunService.Heartbeat:Connect(function()
    local live = {}
    for _, m in ipairs(enemyModels()) do
        live[m] = true
        applyHead(m)
    end
    for m, e in pairs(Esp) do
        if not live[m] or not m.Parent then
            destroyEntry(e)
            Esp[m] = nil
        end
    end
end)

local renderConn = RunService.RenderStepped:Connect(function()
    for _, m in ipairs(enemyModels()) do
        local e = Esp[m]
        if not e then
            e = newEntry()
            Esp[m] = e
        end
        updateEsp(m, e)
    end
    triggerTick()
end)

getgenv().__mara_unload = function()
    renderConn:Disconnect()
    heartConn:Disconnect()
    for m, e in pairs(Esp) do
        destroyEntry(e)
        Esp[m] = nil
    end
    restoreHeads()
    menu:Destroy()
end
