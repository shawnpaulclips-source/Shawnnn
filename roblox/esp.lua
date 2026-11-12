-- ESP + aimbot + no recoil for Skorpio Engine game
-- INSERT toggles menu | all features have menu toggles
-- game uses: Teams.Attackers / Teams.Defenders, Humanoid.Health/MaxHealth
-- recoil: Skorpio Engine springs u10 (gun) + u11 (cam), camRecoilMod on u68

if getgenv().__esp_unload then pcall(getgenv().__esp_unload) end

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local Camera      = workspace.CurrentCamera
local Mouse       = LocalPlayer:GetMouse()

workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    Camera = workspace.CurrentCamera
end)

------------------------------------------------------------------------
-- settings
------------------------------------------------------------------------

local Settings = {
    -- esp
    Enabled    = true,
    Boxes      = true,
    HealthBars = true,
    TeamCheck  = true,
    BoxColor   = Color3.fromRGB(235, 92, 72),
    -- aimbot
    Aimbot     = false,
    AimFOV     = 90,        -- pixel radius
    Smoothing  = 0.15,      -- 0 = instant snap, 1 = barely moves
    ShowFOV    = true,
    -- no recoil
    NoRecoil   = false,
}

------------------------------------------------------------------------
-- drawing objects for esp
------------------------------------------------------------------------

local function newDrawing(kind, props)
    local d = Drawing.new(kind)
    for k, v in pairs(props) do d[k] = v end
    return d
end

local Esp = {}

local function createEsp(player)
    if player == LocalPlayer or Esp[player] then return end
    Esp[player] = {
        BoxOutline = newDrawing("Square", { Thickness = 3, Color = Color3.new(0, 0, 0), Filled = false, Visible = false }),
        Box        = newDrawing("Square", { Thickness = 1, Color = Settings.BoxColor, Filled = false, Visible = false }),
        BarBack    = newDrawing("Square", { Thickness = 1, Color = Color3.new(0, 0, 0), Filled = true, Visible = false }),
        Bar        = newDrawing("Square", { Thickness = 1, Filled = true, Visible = false }),
    }
end

local function removeEsp(player)
    local e = Esp[player]
    if not e then return end
    for _, d in pairs(e) do d:Remove() end
    Esp[player] = nil
end

local function hide(e)
    for _, d in pairs(e) do d.Visible = false end
end

for _, p in ipairs(Players:GetPlayers()) do createEsp(p) end
Players.PlayerAdded:Connect(createEsp)
Players.PlayerRemoving:Connect(removeEsp)

------------------------------------------------------------------------
-- FOV circle (Drawing)
------------------------------------------------------------------------

local FOVCircle = newDrawing("Circle", {
    Thickness = 1.5,
    Color     = Color3.fromRGB(235, 92, 72),
    Filled    = false,
    NumSides  = 64,
    Visible   = false,
    Transparency = 0.6,
})

------------------------------------------------------------------------
-- helpers
------------------------------------------------------------------------

local function isTeammate(player)
    if not Settings.TeamCheck then return false end
    if not LocalPlayer.Team or not player.Team then return false end
    return player.Team == LocalPlayer.Team
end

local function isAlive(player)
    local char = player.Character
    if not char then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    return hum and hum.Health > 0
end

local function getHead(player)
    local char = player.Character
    return char and char:FindFirstChild("Head")
end

------------------------------------------------------------------------
-- aimbot target selection
------------------------------------------------------------------------

local function getAimbotTarget()
    if not Settings.Aimbot then return nil end
    if not isAlive(LocalPlayer) then return nil end

    local vp    = Camera.ViewportSize
    local cx, cy = vp.X / 2, vp.Y / 2
    local best, bestDist = nil, Settings.AimFOV

    for _, player in ipairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        if isTeammate(player) then continue end
        if not isAlive(player) then continue end

        local head = getHead(player)
        if not head then continue end

        local screenPos, onScreen = Camera:WorldToViewportPoint(head.Position)
        if not onScreen then continue end

        local dist = math.sqrt((screenPos.X - cx)^2 + (screenPos.Y - cy)^2)
        if dist < bestDist then
            bestDist = dist
            best = player
        end
    end

    return best
end

------------------------------------------------------------------------
-- no recoil: hook into Skorpio Engine's recoil mod table
------------------------------------------------------------------------

------------------------------------------------------------------------
-- render loop (esp + aimbot + fov circle + no recoil)
------------------------------------------------------------------------

local RED, GREEN = Color3.fromRGB(230, 60, 60), Color3.fromRGB(80, 220, 110)
local aimTarget = nil

local renderConn = RunService.RenderStepped:Connect(function(dt)
    -- FOV circle
    local vp = Camera.ViewportSize
    local cx, cy = vp.X / 2, vp.Y / 2
    FOVCircle.Position = Vector2.new(cx, cy)
    FOVCircle.Radius   = Settings.AimFOV
    FOVCircle.Visible  = Settings.Aimbot and Settings.ShowFOV

    -- aimbot
    aimTarget = getAimbotTarget()

    if aimTarget and Settings.Aimbot and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
        local head = getHead(aimTarget)
        if head then
            local targetCF = CFrame.lookAt(Camera.CFrame.Position, head.Position)
            local smooth   = 1 - math.clamp(Settings.Smoothing, 0, 0.95)
            Camera.CFrame  = Camera.CFrame:Lerp(targetCF, smooth)
        end
    end

    -- ESP
    for player, e in pairs(Esp) do
        local char = player.Character
        local hrp  = char and char:FindFirstChild("HumanoidRootPart")
        local hum  = char and char:FindFirstChildOfClass("Humanoid")

        if not Settings.Enabled or not hrp or not hum or hum.Health <= 0
            or isTeammate(player) then
            hide(e)
            continue
        end

        local _, onScreen = Camera:WorldToViewportPoint(hrp.Position)
        if not onScreen then
            hide(e)
            continue
        end

        local top    = Camera:WorldToViewportPoint(hrp.Position + Vector3.new(0, 3, 0))
        local bottom = Camera:WorldToViewportPoint(hrp.Position - Vector3.new(0, 3.5, 0))
        local h = math.abs(bottom.Y - top.Y)
        local w = h * 0.55
        local pos = Vector2.new(top.X - w / 2, top.Y)
        local size = Vector2.new(w, h)

        -- highlight aimbot target
        local isTarget = (player == aimTarget)
        local boxCol = isTarget and Color3.fromRGB(255, 200, 60) or Settings.BoxColor

        e.Box.Visible, e.BoxOutline.Visible = Settings.Boxes, Settings.Boxes
        if Settings.Boxes then
            e.Box.Position, e.Box.Size = pos, size
            e.Box.Color = boxCol
            e.BoxOutline.Position, e.BoxOutline.Size = pos, size
        end

        e.Bar.Visible, e.BarBack.Visible = Settings.HealthBars, Settings.HealthBars
        if Settings.HealthBars then
            local frac = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
            local barX = pos.X - 6
            e.BarBack.Position = Vector2.new(barX - 1, pos.Y - 1)
            e.BarBack.Size     = Vector2.new(4, h + 2)
            e.Bar.Position     = Vector2.new(barX, pos.Y + h * (1 - frac))
            e.Bar.Size         = Vector2.new(2, h * frac)
            e.Bar.Color        = RED:Lerp(GREEN, frac)
        end
    end
end)

------------------------------------------------------------------------
-- no recoil: hookfunction approach for Skorpio Engine
-- overwrites the Recoil() upvalue references so shove() receives zero
------------------------------------------------------------------------

local recoilHookConn = nil

local function startNoRecoilHook()
    if recoilHookConn then return end
    -- method: each frame, find all SpringModule instances and zero their position
    -- more reliable: hookfunction the spring's shove if the executor supports it
    -- fallback: we use a Heartbeat connection that fires after Recoil()
    -- and counteracts the camera rotation it applied

    local lastCamCF = nil
    local shooting  = false

    -- detect shooting: MB1 held
    recoilHookConn = RunService.Heartbeat:Connect(function()
        if not Settings.NoRecoil then return end

        local mb1 = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
        if not mb1 then
            shooting = false
            lastCamCF = nil
            return
        end

        if not shooting then
            -- first frame of firing: snapshot the camera
            lastCamCF = Camera.CFrame
            shooting = true
            return
        end

        -- while shooting: if aimbot is NOT active, lock camera pitch/yaw
        -- if aimbot IS active, the aimbot lerp already handles aim
        if not (Settings.Aimbot and aimTarget) then
            if lastCamCF then
                -- preserve the camera's position but restore the orientation
                -- this strips the recoil rotation the engine applied this frame
                local pos = Camera.CFrame.Position
                Camera.CFrame = CFrame.new(pos) * (lastCamCF - lastCamCF.Position)
            end
        end

        -- update snapshot so slow drift still works (prevents jarring snap)
        -- allow tiny fraction of natural movement through
        lastCamCF = Camera.CFrame
    end)
end

local function stopNoRecoilHook()
    if recoilHookConn then
        recoilHookConn:Disconnect()
        recoilHookConn = nil
    end
end

startNoRecoilHook()

------------------------------------------------------------------------
-- menu
------------------------------------------------------------------------

local Theme = {
    Bg     = Color3.fromRGB(18, 17, 22),
    Panel  = Color3.fromRGB(28, 26, 34),
    Hover  = Color3.fromRGB(38, 35, 46),
    Text   = Color3.fromRGB(232, 228, 238),
    Muted  = Color3.fromRGB(128, 122, 140),
    Accent = Color3.fromRGB(235, 92, 72),
    Off    = Color3.fromRGB(58, 54, 66),
    Yellow = Color3.fromRGB(255, 200, 60),
}

local guiParent = (gethui and gethui()) or game:GetService("CoreGui")
local Gui = Instance.new("ScreenGui")
Gui.Name = tostring(math.random(1e6, 9e6))
Gui.ResetOnSpawn = false
Gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
Gui.Parent = guiParent

local function corner(obj, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r)
    c.Parent = obj
end

-- menu has two sections now: visuals (4 toggles) + combat (3 toggles + 1 slider)
-- total rows: 7 toggles + 1 slider + 2 section headers = ~340px
local Main = Instance.new("Frame")
Main.Size = UDim2.fromOffset(260, 410)
Main.Position = UDim2.new(0, 40, 0.5, -205)
Main.BackgroundColor3 = Theme.Bg
Main.BorderSizePixel = 0
Main.ClipsDescendants = true
Main.Parent = Gui
corner(Main, 8)

local stroke = Instance.new("UIStroke")
stroke.Color = Theme.Off
stroke.Thickness = 1
stroke.Parent = Main

local Header = Instance.new("Frame")
Header.Size = UDim2.new(1, 0, 0, 36)
Header.BackgroundTransparency = 1
Header.Parent = Main

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -24, 1, 0)
Title.Position = UDim2.fromOffset(14, 0)
Title.BackgroundTransparency = 1
Title.Font = Enum.Font.GothamBold
Title.TextSize = 14
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.TextColor3 = Theme.Text
Title.Text = "mara"
Title.Parent = Header

local Hint = Instance.new("TextLabel")
Hint.Size = UDim2.new(1, -14, 1, 0)
Hint.BackgroundTransparency = 1
Hint.Font = Enum.Font.Gotham
Hint.TextSize = 11
Hint.TextXAlignment = Enum.TextXAlignment.Right
Hint.TextColor3 = Theme.Muted
Hint.Text = "INS"
Hint.Parent = Header

local AccentLine = Instance.new("Frame")
AccentLine.Size = UDim2.new(1, -28, 0, 1)
AccentLine.Position = UDim2.fromOffset(14, 36)
AccentLine.BackgroundColor3 = Theme.Accent
AccentLine.BorderSizePixel = 0
AccentLine.Parent = Main

local Scroll = Instance.new("ScrollingFrame")
Scroll.Size = UDim2.new(1, -12, 1, -48)
Scroll.Position = UDim2.fromOffset(6, 44)
Scroll.BackgroundTransparency = 1
Scroll.ScrollBarThickness = 3
Scroll.ScrollBarImageColor3 = Theme.Muted
Scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
Scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
Scroll.BorderSizePixel = 0
Scroll.Parent = Main

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 4)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = Scroll

local pad = Instance.new("UIPadding")
pad.PaddingLeft = UDim.new(0, 4)
pad.PaddingRight = UDim.new(0, 4)
pad.PaddingTop = UDim.new(0, 2)
pad.PaddingBottom = UDim.new(0, 6)
pad.Parent = Scroll

local fast = TweenInfo.new(0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

------------------------------------------------------------------------
-- menu: section header
------------------------------------------------------------------------

local function section(label, order)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 24)
    row.BackgroundTransparency = 1
    row.LayoutOrder = order
    row.Parent = Scroll

    local text = Instance.new("TextLabel")
    text.Size = UDim2.new(1, -8, 1, 0)
    text.Position = UDim2.fromOffset(4, 0)
    text.BackgroundTransparency = 1
    text.Font = Enum.Font.GothamBold
    text.TextSize = 11
    text.TextXAlignment = Enum.TextXAlignment.Left
    text.TextColor3 = Theme.Muted
    text.Text = string.upper(label)
    text.Parent = row
end

------------------------------------------------------------------------
-- menu: toggle
------------------------------------------------------------------------

local function toggle(label, key, order)
    local row = Instance.new("TextButton")
    row.Size = UDim2.new(1, 0, 0, 34)
    row.BackgroundColor3 = Theme.Panel
    row.AutoButtonColor = false
    row.Text = ""
    row.LayoutOrder = order
    row.Parent = Scroll
    corner(row, 6)

    local text = Instance.new("TextLabel")
    text.Size = UDim2.new(1, -60, 1, 0)
    text.Position = UDim2.fromOffset(12, 0)
    text.BackgroundTransparency = 1
    text.Font = Enum.Font.GothamMedium
    text.TextSize = 13
    text.TextXAlignment = Enum.TextXAlignment.Left
    text.TextColor3 = Theme.Text
    text.Text = label
    text.Parent = row

    local track = Instance.new("Frame")
    track.Size = UDim2.fromOffset(32, 16)
    track.Position = UDim2.new(1, -44, 0.5, -8)
    track.BorderSizePixel = 0
    track.Parent = row
    corner(track, 8)

    local knob = Instance.new("Frame")
    knob.Size = UDim2.fromOffset(12, 12)
    knob.BackgroundColor3 = Theme.Text
    knob.BorderSizePixel = 0
    knob.Parent = track
    corner(knob, 6)

    local function render(animate)
        local on = Settings[key]
        local goalTrack = { BackgroundColor3 = on and Theme.Accent or Theme.Off }
        local goalKnob  = { Position = on and UDim2.fromOffset(18, 2) or UDim2.fromOffset(2, 2) }
        if animate then
            TweenService:Create(track, fast, goalTrack):Play()
            TweenService:Create(knob, fast, goalKnob):Play()
        else
            track.BackgroundColor3 = goalTrack.BackgroundColor3
            knob.Position = goalKnob.Position
        end
    end
    render(false)

    row.MouseEnter:Connect(function()
        TweenService:Create(row, fast, { BackgroundColor3 = Theme.Hover }):Play()
    end)
    row.MouseLeave:Connect(function()
        TweenService:Create(row, fast, { BackgroundColor3 = Theme.Panel }):Play()
    end)
    row.MouseButton1Down:Connect(function()
        TweenService:Create(knob, fast, { Size = UDim2.fromOffset(14, 12) }):Play()
    end)
    row.MouseButton1Up:Connect(function()
        TweenService:Create(knob, fast, { Size = UDim2.fromOffset(12, 12) }):Play()
    end)
    row.MouseButton1Click:Connect(function()
        Settings[key] = not Settings[key]
        render(true)
    end)
end

------------------------------------------------------------------------
-- menu: slider
------------------------------------------------------------------------

local function slider(label, key, min, max, step, order)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 48)
    row.BackgroundColor3 = Theme.Panel
    row.LayoutOrder = order
    row.Parent = Scroll
    corner(row, 6)

    local text = Instance.new("TextLabel")
    text.Size = UDim2.new(1, -60, 0, 20)
    text.Position = UDim2.fromOffset(12, 4)
    text.BackgroundTransparency = 1
    text.Font = Enum.Font.GothamMedium
    text.TextSize = 13
    text.TextXAlignment = Enum.TextXAlignment.Left
    text.TextColor3 = Theme.Text
    text.Text = label
    text.Parent = row

    local valLabel = Instance.new("TextLabel")
    valLabel.Size = UDim2.new(0, 40, 0, 20)
    valLabel.Position = UDim2.new(1, -52, 0, 4)
    valLabel.BackgroundTransparency = 1
    valLabel.Font = Enum.Font.GothamMedium
    valLabel.TextSize = 12
    valLabel.TextXAlignment = Enum.TextXAlignment.Right
    valLabel.TextColor3 = Theme.Accent
    valLabel.Parent = row

    local track = Instance.new("Frame")
    track.Size = UDim2.new(1, -24, 0, 6)
    track.Position = UDim2.fromOffset(12, 32)
    track.BackgroundColor3 = Theme.Off
    track.BorderSizePixel = 0
    track.Parent = row
    corner(track, 3)

    local fill = Instance.new("Frame")
    fill.Size = UDim2.new(0, 0, 1, 0)
    fill.BackgroundColor3 = Theme.Accent
    fill.BorderSizePixel = 0
    fill.Parent = track
    corner(fill, 3)

    local knob = Instance.new("Frame")
    knob.Size = UDim2.fromOffset(12, 12)
    knob.AnchorPoint = Vector2.new(0.5, 0.5)
    knob.Position = UDim2.new(0, 0, 0.5, 0)
    knob.BackgroundColor3 = Theme.Text
    knob.BorderSizePixel = 0
    knob.Parent = track
    corner(knob, 6)

    local function render()
        local frac = (Settings[key] - min) / (max - min)
        fill.Size = UDim2.new(frac, 0, 1, 0)
        knob.Position = UDim2.new(frac, 0, 0.5, 0)
        local display = step >= 1 and tostring(math.floor(Settings[key])) or string.format("%.2f", Settings[key])
        valLabel.Text = display
    end
    render()

    local dragging = false

    local function update(inputX)
        local abs = track.AbsolutePosition.X
        local w   = track.AbsoluteSize.X
        local frac = math.clamp((inputX - abs) / w, 0, 1)
        local raw  = min + frac * (max - min)
        Settings[key] = math.floor(raw / step + 0.5) * step
        Settings[key] = math.clamp(Settings[key], min, max)
        render()
    end

    track.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            update(input.Position.X)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            update(input.Position.X)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)
end

------------------------------------------------------------------------
-- build menu
------------------------------------------------------------------------

section("visuals", 1)
toggle("Enabled",      "Enabled",    2)
toggle("Box ESP",      "Boxes",      3)
toggle("Health bars",  "HealthBars", 4)
toggle("Team check",   "TeamCheck",  5)

section("combat", 10)
toggle("Aimbot",       "Aimbot",     11)
toggle("Show FOV",     "ShowFOV",    12)
slider("FOV radius",   "AimFOV",     20, 300, 5, 13)
slider("Smoothing",    "Smoothing",  0, 0.95, 0.05, 14)
toggle("No recoil",    "NoRecoil",   15)

------------------------------------------------------------------------
-- drag by header
------------------------------------------------------------------------

do
    local dragging, dragStart, startPos
    Header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging, dragStart, startPos = true, input.Position, Main.Position
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local d = input.Position - dragStart
            Main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
end

------------------------------------------------------------------------
-- INSERT: fade + collapse
------------------------------------------------------------------------

local open = true
local fullSize = Main.Size
local slow = TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

UserInputService.InputBegan:Connect(function(input, processed)
    if processed or input.KeyCode ~= Enum.KeyCode.Insert then return end
    open = not open
    if open then
        Main.Visible = true
        TweenService:Create(Main, slow, { Size = fullSize, BackgroundTransparency = 0 }):Play()
        TweenService:Create(stroke, slow, { Transparency = 0 }):Play()
    else
        local t = TweenService:Create(Main, slow, { Size = UDim2.fromOffset(fullSize.X.Offset, 0), BackgroundTransparency = 1 })
        TweenService:Create(stroke, slow, { Transparency = 1 }):Play()
        t:Play()
        t.Completed:Connect(function()
            if not open then Main.Visible = false end
        end)
    end
end)

------------------------------------------------------------------------
-- cleanup hook
------------------------------------------------------------------------

getgenv().__esp_unload = function()
    renderConn:Disconnect()
    stopNoRecoilHook()
    FOVCircle:Remove()
    for p in pairs(Esp) do removeEsp(p) end
    Gui:Destroy()
end
