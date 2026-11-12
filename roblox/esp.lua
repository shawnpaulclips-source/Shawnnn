-- Skorpio Engine client: ESP (box, health, skeleton) + aimbot (FOV wheel) + no recoil
-- INSERT toggles the menu. Everything is client-side.
--
-- Dump findings this is built against:
--   * Teams.Attackers / Teams.Defenders / Teams.Spec (spectators, skipped as targets)
--   * Character rigs are mixed: R15 (UpperTorso/LowerTorso) and R6 (Torso/"Left Arm")
--   * Recoil: SE_Client Recoil() calls :shove() on SpringModule tables u11 (camera) and u10 (viewmodel)
--   * Camera is driven at RenderPriority.Camera (cameraRenderUpdate); SpecModule overrides CameraSubject

if getgenv().__mara_unload then pcall(getgenv().__mara_unload) end

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local Teams            = game:GetService("Teams")

local LocalPlayer = Players.LocalPlayer
local Camera      = workspace.CurrentCamera

local Conns = {}
local function track(conn)
    Conns[#Conns + 1] = conn
    return conn
end

track(workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    Camera = workspace.CurrentCamera
end))

------------------------------------------------------------------------
-- settings
------------------------------------------------------------------------

local SKELETON_PALETTE = {
    Color3.fromRGB(240, 240, 240),
    Color3.fromRGB(120, 200, 255),
    Color3.fromRGB(150, 255, 150),
    Color3.fromRGB(255, 210, 110),
}

local Settings = {
    Enabled      = true,
    Boxes        = true,
    HealthBars   = true,
    Skeleton     = true,
    TeamCheck    = true,
    BoxColor     = Color3.fromRGB(235, 92, 72),
    SkeletonIdx  = 1,

    Aimbot       = false,
    AimKey       = Enum.UserInputType.MouseButton2,
    ShowFOV      = true,
    AimFOV       = 90,
    Smoothing    = 0.15,

    NoRecoil     = false,
}

local TargetColor = Color3.fromRGB(255, 200, 60)

local function skeletonColor()
    return SKELETON_PALETTE[Settings.SkeletonIdx]
end

local function keyDown(key)
    if typeof(key) == "EnumItem" and key.EnumType == Enum.UserInputType then
        return UserInputService:IsMouseButtonPressed(key)
    end
    return UserInputService:IsKeyDown(key)
end

local function keyName(key)
    if key.EnumType == Enum.UserInputType then
        return ({
            [Enum.UserInputType.MouseButton1] = "LMB",
            [Enum.UserInputType.MouseButton2] = "RMB",
            [Enum.UserInputType.MouseButton3] = "MMB",
        })[key] or key.Name
    end
    return key.Name
end

------------------------------------------------------------------------
-- team / state helpers
------------------------------------------------------------------------

local function isSpectator(player)
    return player.Team ~= nil and player.Team == Teams:FindFirstChild("Spec")
end

local function isTeammate(player)
    if not Settings.TeamCheck then return false end
    if not LocalPlayer.Team or not player.Team then return false end
    return player.Team == LocalPlayer.Team
end

local function humanoidOf(player)
    local char = player.Character
    return char and char:FindFirstChildOfClass("Humanoid")
end

local function isAlive(player)
    local hum = humanoidOf(player)
    return hum ~= nil and hum.Health > 0
end

------------------------------------------------------------------------
-- esp drawing pool
------------------------------------------------------------------------

local function newDrawing(kind, props)
    local d = Drawing.new(kind)
    for k, v in pairs(props) do d[k] = v end
    return d
end

local R15_BONES = {
    { "Head", "UpperTorso" }, { "UpperTorso", "LowerTorso" },
    { "UpperTorso", "LeftUpperArm" }, { "LeftUpperArm", "LeftLowerArm" }, { "LeftLowerArm", "LeftHand" },
    { "UpperTorso", "RightUpperArm" }, { "RightUpperArm", "RightLowerArm" }, { "RightLowerArm", "RightHand" },
    { "LowerTorso", "LeftUpperLeg" }, { "LeftUpperLeg", "LeftLowerLeg" }, { "LeftLowerLeg", "LeftFoot" },
    { "LowerTorso", "RightUpperLeg" }, { "RightUpperLeg", "RightLowerLeg" }, { "RightLowerLeg", "RightFoot" },
}

local R6_BONES = {
    { "Head", "Torso" }, { "Torso", "Left Arm" }, { "Torso", "Right Arm" },
    { "Torso", "Left Leg" }, { "Torso", "Right Leg" },
}

local MAX_BONES = #R15_BONES

local Esp = {}

local function createEsp(player)
    if player == LocalPlayer or Esp[player] then return end
    local bones = {}
    for i = 1, MAX_BONES do
        bones[i] = newDrawing("Line", { Thickness = 1, Color = skeletonColor(), Visible = false })
    end
    Esp[player] = {
        BoxOutline = newDrawing("Square", { Thickness = 3, Color = Color3.new(0, 0, 0), Filled = false, Visible = false }),
        Box        = newDrawing("Square", { Thickness = 1, Color = Settings.BoxColor, Filled = false, Visible = false }),
        BarBack    = newDrawing("Square", { Thickness = 1, Color = Color3.new(0, 0, 0), Filled = true, Visible = false }),
        Bar        = newDrawing("Square", { Thickness = 1, Filled = true, Visible = false }),
        Bones      = bones,
    }
end

local function destroyEsp(player)
    local e = Esp[player]
    if not e then return end
    for k, d in pairs(e) do
        if k == "Bones" then
            for _, line in ipairs(d) do line:Remove() end
        else
            d:Remove()
        end
    end
    Esp[player] = nil
end

local function hideEsp(e)
    e.Box.Visible = false
    e.BoxOutline.Visible = false
    e.Bar.Visible = false
    e.BarBack.Visible = false
    for _, line in ipairs(e.Bones) do line.Visible = false end
end

for _, p in ipairs(Players:GetPlayers()) do createEsp(p) end
track(Players.PlayerAdded:Connect(createEsp))
track(Players.PlayerRemoving:Connect(destroyEsp))

------------------------------------------------------------------------
-- fov wheel
------------------------------------------------------------------------

local FOVCircle = newDrawing("Circle", {
    Thickness    = 1.5,
    Color        = Settings.BoxColor,
    Filled       = false,
    NumSides     = 64,
    Transparency = 0.6,
    Visible      = false,
})

------------------------------------------------------------------------
-- aimbot target
------------------------------------------------------------------------

local aimTarget = nil

local function pickAimTarget()
    if not Settings.Aimbot then return nil end
    if isSpectator(LocalPlayer) or not isAlive(LocalPlayer) then return nil end

    local vp = Camera.ViewportSize
    local cx, cy = vp.X / 2, vp.Y / 2
    local best, bestDist = nil, Settings.AimFOV

    for _, player in ipairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        if isSpectator(player) or isTeammate(player) or not isAlive(player) then continue end

        local char = player.Character
        local head = char and char:FindFirstChild("Head")
        if not head then continue end

        local sp, onScreen = Camera:WorldToViewportPoint(head.Position)
        if not onScreen then continue end

        local dist = math.sqrt((sp.X - cx) ^ 2 + (sp.Y - cy) ^ 2)
        if dist < bestDist then
            bestDist = dist
            best = player
        end
    end

    return best
end

------------------------------------------------------------------------
-- no recoil
-- Recoil() shoves two SpringModule tables (camera u11, viewmodel u10).
-- Each spring's shove is a closure on its own table, so we find them
-- with getgc and wrap shove to drop the impulse while NoRecoil is on.
------------------------------------------------------------------------

local hookedSprings = setmetatable({}, { __mode = "k" })
local recoilScanning = true

local function isSkorpioSpring(t)
    return type(rawget(t, "shove")) == "function"
        and type(rawget(t, "update")) == "function"
        and typeof(rawget(t, "Target")) == "Vector3"
        and typeof(rawget(t, "Velocity")) == "Vector3"
        and rawget(t, "Damping") ~= nil
end

local function hookSprings()
    for _, t in ipairs(getgc(true)) do
        if type(t) == "table" and hookedSprings[t] == nil and isSkorpioSpring(t) then
            local original = rawget(t, "shove")
            hookedSprings[t] = original
            rawset(t, "shove", function(self, impulse, ...)
                if Settings.NoRecoil then return end
                return original(self, impulse, ...)
            end)
        end
    end
end

task.spawn(function()
    while recoilScanning do
        pcall(hookSprings)
        task.wait(3)
    end
end)

local function unhookSprings()
    recoilScanning = false
    for t, original in pairs(hookedSprings) do
        rawset(t, "shove", original)
    end
    table.clear(hookedSprings)
end

------------------------------------------------------------------------
-- frame: esp + skeleton + aimbot + fov
-- bound at Camera+1 so it runs after the game's camera step for the frame
------------------------------------------------------------------------

local RED, GREEN = Color3.fromRGB(230, 60, 60), Color3.fromRGB(80, 220, 110)
local BIND_NAME  = "mara_frame"
local statusLabel -- set once the menu exists

local function drawSkeleton(e, char, hum, col)
    local bones = (hum.RigType == Enum.HumanoidRigType.R15) and R15_BONES or R6_BONES
    for i, line in ipairs(e.Bones) do
        local pair = bones[i]
        local a = pair and char:FindFirstChild(pair[1])
        local b = pair and char:FindFirstChild(pair[2])
        if a and b then
            local pa, va = Camera:WorldToViewportPoint(a.Position)
            local pb, vb = Camera:WorldToViewportPoint(b.Position)
            if va and vb then
                line.From = Vector2.new(pa.X, pa.Y)
                line.To = Vector2.new(pb.X, pb.Y)
                line.Color = col
                line.Visible = Settings.Skeleton
            else
                line.Visible = false
            end
        else
            line.Visible = false
        end
    end
    for i = #bones + 1, MAX_BONES do
        e.Bones[i].Visible = false
    end
end

local function frame()
    Camera = workspace.CurrentCamera
    local vp = Camera.ViewportSize
    local cx, cy = vp.X / 2, vp.Y / 2

    FOVCircle.Position = Vector2.new(cx, cy)
    FOVCircle.Radius   = Settings.AimFOV
    FOVCircle.Color    = Settings.BoxColor
    FOVCircle.Visible  = Settings.Aimbot and Settings.ShowFOV

    aimTarget = pickAimTarget()

    if aimTarget and Settings.Aimbot and keyDown(Settings.AimKey) then
        local head = aimTarget.Character and aimTarget.Character:FindFirstChild("Head")
        if head then
            local targetCF = CFrame.lookAt(Camera.CFrame.Position, head.Position)
            local alpha    = 1 - math.clamp(Settings.Smoothing, 0, 0.95)
            Camera.CFrame  = Camera.CFrame:Lerp(targetCF, alpha)
        end
    end

    for player, e in pairs(Esp) do
        local char = player.Character
        local hrp  = char and char:FindFirstChild("HumanoidRootPart")
        local hum  = char and char:FindFirstChildOfClass("Humanoid")

        if not Settings.Enabled or not hrp or not hum or hum.Health <= 0
            or isSpectator(player) or isTeammate(player) then
            hideEsp(e)
            continue
        end

        local _, onScreen = Camera:WorldToViewportPoint(hrp.Position)
        if not onScreen then
            hideEsp(e)
            continue
        end

        local top    = Camera:WorldToViewportPoint(hrp.Position + Vector3.new(0, 3, 0))
        local bottom = Camera:WorldToViewportPoint(hrp.Position - Vector3.new(0, 3.5, 0))
        local h    = math.abs(bottom.Y - top.Y)
        local w    = h * 0.55
        local pos  = Vector2.new(top.X - w / 2, top.Y)
        local size = Vector2.new(w, h)

        local isTarget = player == aimTarget
        local boxCol   = isTarget and TargetColor or Settings.BoxColor

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

        drawSkeleton(e, char, hum, skeletonColor())
    end

    if statusLabel then
        if not Settings.Aimbot then
            statusLabel.Text = "off"
        elseif aimTarget then
            statusLabel.Text = aimTarget.DisplayName or aimTarget.Name
        else
            statusLabel.Text = "no target"
        end
    end
end

RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 1, frame)

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
    Danger = Color3.fromRGB(190, 60, 70),
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
    return c
end

local function label(parent, props)
    local t = Instance.new("TextLabel")
    t.BackgroundTransparency = 1
    t.Font = props.Font or Enum.Font.GothamMedium
    t.TextSize = props.TextSize or 13
    t.TextColor3 = props.Color or Theme.Text
    t.TextXAlignment = props.Align or Enum.TextXAlignment.Left
    t.Text = props.Text or ""
    t.Size = props.Size or UDim2.new(1, 0, 1, 0)
    t.Position = props.Position or UDim2.fromOffset(0, 0)
    t.Parent = parent
    return t
end

local Main = Instance.new("Frame")
Main.Size = UDim2.fromOffset(280, 470)
Main.Position = UDim2.new(0, 40, 0.5, -235)
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
Header.Size = UDim2.new(1, 0, 0, 40)
Header.BackgroundTransparency = 1
Header.Parent = Main

label(Header, { Text = "mara", Font = Enum.Font.GothamBold, TextSize = 15, Position = UDim2.fromOffset(14, 0), Size = UDim2.new(0.5, 0, 1, 0) })
label(Header, { Text = "skorpio · client", Font = Enum.Font.Gotham, TextSize = 10, Color = Theme.Muted, Position = UDim2.fromOffset(14, 20), Size = UDim2.new(0.6, 0, 0, 14) })
label(Header, { Text = "INS", Font = Enum.Font.GothamMedium, TextSize = 11, Color = Theme.Muted, Align = Enum.TextXAlignment.Right, Size = UDim2.new(1, -14, 1, 0) })

local AccentLine = Instance.new("Frame")
AccentLine.Size = UDim2.new(1, -28, 0, 1)
AccentLine.Position = UDim2.fromOffset(14, 40)
AccentLine.BackgroundColor3 = Theme.Accent
AccentLine.BorderSizePixel = 0
AccentLine.Parent = Main

local Scroll = Instance.new("ScrollingFrame")
Scroll.Size = UDim2.new(1, -12, 1, -50)
Scroll.Position = UDim2.fromOffset(6, 48)
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
local slow = TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

local function section(text, order)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 24)
    row.BackgroundTransparency = 1
    row.LayoutOrder = order
    row.Parent = Scroll
    label(row, { Text = string.upper(text), Font = Enum.Font.GothamBold, TextSize = 10, Color = Theme.Muted, Position = UDim2.fromOffset(4, 0), Size = UDim2.new(1, -8, 1, 0) })
end

local function rowFrame(order, height, bg)
    local row = Instance.new("TextButton")
    row.Size = UDim2.new(1, 0, 0, height or 34)
    row.BackgroundColor3 = bg or Theme.Panel
    row.AutoButtonColor = false
    row.Text = ""
    row.LayoutOrder = order
    row.Parent = Scroll
    corner(row, 6)
    return row
end

local function hoverable(row, base)
    row.MouseEnter:Connect(function()
        TweenService:Create(row, fast, { BackgroundColor3 = Theme.Hover }):Play()
    end)
    row.MouseLeave:Connect(function()
        TweenService:Create(row, fast, { BackgroundColor3 = base or Theme.Panel }):Play()
    end)
end

------------------------------------------------------------------------
-- toggle
------------------------------------------------------------------------

local function toggle(text, key, order, onChange)
    local row = rowFrame(order)
    label(row, { Text = text, Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -60, 1, 0) })

    local track_ = Instance.new("Frame")
    track_.Size = UDim2.fromOffset(32, 16)
    track_.Position = UDim2.new(1, -44, 0.5, -8)
    track_.BorderSizePixel = 0
    track_.Parent = row
    corner(track_, 8)

    local knob = Instance.new("Frame")
    knob.Size = UDim2.fromOffset(12, 12)
    knob.BackgroundColor3 = Theme.Text
    knob.BorderSizePixel = 0
    knob.Parent = track_
    corner(knob, 6)

    local function render(animate)
        local on = Settings[key]
        local goalTrack = on and Theme.Accent or Theme.Off
        local goalKnob  = on and UDim2.fromOffset(18, 2) or UDim2.fromOffset(2, 2)
        if animate then
            TweenService:Create(track_, fast, { BackgroundColor3 = goalTrack }):Play()
            TweenService:Create(knob, fast, { Position = goalKnob }):Play()
        else
            track_.BackgroundColor3 = goalTrack
            knob.Position = goalKnob
        end
    end
    render(false)

    hoverable(row)
    row.MouseButton1Down:Connect(function()
        TweenService:Create(knob, fast, { Size = UDim2.fromOffset(14, 12) }):Play()
    end)
    row.MouseButton1Up:Connect(function()
        TweenService:Create(knob, fast, { Size = UDim2.fromOffset(12, 12) }):Play()
    end)
    row.MouseButton1Click:Connect(function()
        Settings[key] = not Settings[key]
        render(true)
        if onChange then onChange(Settings[key]) end
    end)
end

------------------------------------------------------------------------
-- slider
------------------------------------------------------------------------

local function slider(text, key, min, max, step, order)
    local row = rowFrame(order, 48)
    label(row, { Text = text, Position = UDim2.fromOffset(12, 4), Size = UDim2.new(1, -60, 0, 20) })

    local valLabel = label(row, { Font = Enum.Font.GothamMedium, TextSize = 12, Color = Theme.Accent, Align = Enum.TextXAlignment.Right, Position = UDim2.new(1, -52, 0, 4), Size = UDim2.fromOffset(40, 20) })

    local track_ = Instance.new("Frame")
    track_.Size = UDim2.new(1, -24, 0, 6)
    track_.Position = UDim2.fromOffset(12, 32)
    track_.BackgroundColor3 = Theme.Off
    track_.BorderSizePixel = 0
    track_.Parent = row
    corner(track_, 3)

    local fill = Instance.new("Frame")
    fill.Size = UDim2.new(0, 0, 1, 0)
    fill.BackgroundColor3 = Theme.Accent
    fill.BorderSizePixel = 0
    fill.Parent = track_
    corner(fill, 3)

    local knob = Instance.new("Frame")
    knob.Size = UDim2.fromOffset(12, 12)
    knob.AnchorPoint = Vector2.new(0.5, 0.5)
    knob.BackgroundColor3 = Theme.Text
    knob.BorderSizePixel = 0
    knob.Parent = track_
    corner(knob, 6)

    local function render()
        local frac = (Settings[key] - min) / (max - min)
        fill.Size = UDim2.new(frac, 0, 1, 0)
        knob.Position = UDim2.new(frac, 0, 0.5, 0)
        valLabel.Text = step >= 1 and tostring(math.floor(Settings[key])) or string.format("%.2f", Settings[key])
    end
    render()

    local dragging = false
    local function update(x)
        local frac = math.clamp((x - track_.AbsolutePosition.X) / track_.AbsoluteSize.X, 0, 1)
        local raw = min + frac * (max - min)
        Settings[key] = math.clamp(math.floor(raw / step + 0.5) * step, min, max)
        render()
    end

    track(track_.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            update(input.Position.X)
        end
    end))
    track(UserInputService.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            update(input.Position.X)
        end
    end))
    track(UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
    end))
end

------------------------------------------------------------------------
-- keybind (click, then press a key or mouse button; Esc cancels)
------------------------------------------------------------------------

local function keybind(text, key, order)
    local row = rowFrame(order)
    label(row, { Text = text, Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -110, 1, 0) })

    local chip = Instance.new("Frame")
    chip.Size = UDim2.fromOffset(88, 22)
    chip.Position = UDim2.new(1, -98, 0.5, -11)
    chip.BackgroundColor3 = Theme.Off
    chip.BorderSizePixel = 0
    chip.Parent = row
    corner(chip, 5)

    local chipText = label(chip, { Font = Enum.Font.GothamBold, TextSize = 11, Color = Theme.Text, Align = Enum.TextXAlignment.Center })

    local capturing = false
    local function render()
        chipText.Text = capturing and "press key…" or keyName(Settings[key])
        chip.BackgroundColor3 = capturing and Theme.Accent or Theme.Off
    end
    render()

    hoverable(row)
    row.MouseButton1Click:Connect(function()
        capturing = true
        render()
    end)

    track(UserInputService.InputBegan:Connect(function(input, _)
        if not capturing then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement then return end
        capturing = false
        if input.KeyCode == Enum.KeyCode.Escape then
            render()
            return
        end
        if input.UserInputType == Enum.UserInputType.Keyboard then
            Settings[key] = input.KeyCode
        else
            Settings[key] = input.UserInputType
        end
        render()
    end))
end

------------------------------------------------------------------------
-- cycle button (colour swatch)
------------------------------------------------------------------------

local function cycle(text, order, onClick, getColor)
    local row = rowFrame(order)
    label(row, { Text = text, Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -60, 1, 0) })

    local swatch = Instance.new("Frame")
    swatch.Size = UDim2.fromOffset(18, 18)
    swatch.Position = UDim2.new(1, -30, 0.5, -9)
    swatch.BackgroundColor3 = getColor()
    swatch.BorderSizePixel = 0
    swatch.Parent = row
    corner(swatch, 9)

    hoverable(row)
    row.MouseButton1Click:Connect(function()
        onClick()
        TweenService:Create(swatch, fast, { BackgroundColor3 = getColor() }):Play()
    end)
    return swatch
end

------------------------------------------------------------------------
-- readout (live status)
------------------------------------------------------------------------

local function readout(text, order)
    local row = rowFrame(order, 30, Theme.Bg)
    label(row, { Text = text, Font = Enum.Font.Gotham, TextSize = 11, Color = Theme.Muted, Position = UDim2.fromOffset(12, 0), Size = UDim2.new(0.5, 0, 1, 0) })
    local v = label(row, { Font = Enum.Font.GothamMedium, TextSize = 11, Color = Theme.Text, Align = Enum.TextXAlignment.Right, Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.new(0.5, -12, 1, 0) })
    return v
end

------------------------------------------------------------------------
-- build menu
------------------------------------------------------------------------

section("visuals", 1)
toggle("Enabled",      "Enabled",    2)
toggle("Box ESP",      "Boxes",      3)
toggle("Health bars",  "HealthBars", 4)
toggle("Skeleton",     "Skeleton",   5)
toggle("Team check",   "TeamCheck",  6)
cycle("Skeleton colour", 7,
    function()
        Settings.SkeletonIdx = Settings.SkeletonIdx % #SKELETON_PALETTE + 1
    end,
    skeletonColor)

section("combat", 10)
toggle("Aimbot",       "Aimbot",     11)
keybind("Aim key",     "AimKey",     12)
toggle("Show FOV",     "ShowFOV",    13)
slider("FOV radius",   "AimFOV",     20, 300, 5, 14)
slider("Smoothing",    "Smoothing",  0, 0.95, 0.05, 15)
statusLabel = readout("Target", 16)

section("misc", 20)
toggle("No recoil",    "NoRecoil",   21)

local unloadRow = rowFrame(22, 34, Theme.Danger)
label(unloadRow, { Text = "Unload", Font = Enum.Font.GothamBold, TextSize = 13, Align = Enum.TextXAlignment.Center })
hoverable(unloadRow, Theme.Danger)
unloadRow.MouseButton1Click:Connect(function()
    if getgenv().__mara_unload then getgenv().__mara_unload() end
end)

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
    track(UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
    end))
    track(UserInputService.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local d = input.Position - dragStart
            Main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end))
end

------------------------------------------------------------------------
-- INSERT: collapse / expand
------------------------------------------------------------------------

local open = true
local fullSize = Main.Size

track(UserInputService.InputBegan:Connect(function(input, processed)
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
end))

------------------------------------------------------------------------
-- unload
------------------------------------------------------------------------

getgenv().__mara_unload = function()
    pcall(RunService.UnbindFromRenderStep, RunService, BIND_NAME)
    for _, c in ipairs(Conns) do c:Disconnect() end
    table.clear(Conns)
    unhookSprings()
    FOVCircle:Remove()
    for p in pairs(Esp) do destroyEsp(p) end
    Gui:Destroy()
    getgenv().__mara_unload = nil
end
