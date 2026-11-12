-- skeleton esp: box + health bar + team check, INSERT toggles menu
-- game layout (from dump): Player.Character / Humanoid.Health / MaxHealth, Teams.Attackers / Teams.Defenders

if getgenv().__esp_unload then pcall(getgenv().__esp_unload) end

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local Camera      = workspace.CurrentCamera

workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    Camera = workspace.CurrentCamera
end)

local Settings = {
    Enabled    = true,
    Boxes      = true,
    HealthBars = true,
    TeamCheck  = true,
    BoxColor   = Color3.fromRGB(235, 92, 72),
}

------------------------------------------------------------------------
-- drawing objects
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
-- render
------------------------------------------------------------------------

local function isTeammate(player)
    if not LocalPlayer.Team or not player.Team then return false end
    return player.Team == LocalPlayer.Team
end

local RED, GREEN = Color3.fromRGB(230, 60, 60), Color3.fromRGB(80, 220, 110)

local renderConn = RunService.RenderStepped:Connect(function()
    for player, e in pairs(Esp) do
        local char = player.Character
        local hrp  = char and char:FindFirstChild("HumanoidRootPart")
        local hum  = char and char:FindFirstChildOfClass("Humanoid")

        if not Settings.Enabled or not hrp or not hum or hum.Health <= 0
            or (Settings.TeamCheck and isTeammate(player)) then
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

        e.Box.Visible, e.BoxOutline.Visible = Settings.Boxes, Settings.Boxes
        if Settings.Boxes then
            e.Box.Position, e.Box.Size = pos, size
            e.Box.Color = Settings.BoxColor
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

local Main = Instance.new("Frame")
Main.Size = UDim2.fromOffset(240, 208)
Main.Position = UDim2.new(0, 40, 0.5, -104)
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
Title.Text = "visuals"
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

local List = Instance.new("Frame")
List.Size = UDim2.new(1, -20, 1, -48)
List.Position = UDim2.fromOffset(10, 44)
List.BackgroundTransparency = 1
List.Parent = Main

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 4)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = List

local fast = TweenInfo.new(0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

local function toggle(label, key, order)
    local row = Instance.new("TextButton")
    row.Size = UDim2.new(1, 0, 0, 34)
    row.BackgroundColor3 = Theme.Panel
    row.AutoButtonColor = false
    row.Text = ""
    row.LayoutOrder = order
    row.Parent = List
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

toggle("Enabled",     "Enabled",    1)
toggle("Box ESP",     "Boxes",      2)
toggle("Health bars", "HealthBars", 3)
toggle("Team check",  "TeamCheck",  4)

-- drag by header
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

-- INSERT: fade + collapse
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

-- re-exec cleanup hook
getgenv().__esp_unload = function()
    renderConn:Disconnect()
    for p in pairs(Esp) do removeEsp(p) end
    Gui:Destroy()
end
