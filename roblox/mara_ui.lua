-- mara_ui: menu module. INSERT toggles open/close. Schema-driven rows: toggle, slider, keybind, button.

local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")

local UI = {}
UI.__index = UI

local Theme = {
    Bg      = Color3.fromRGB(16, 15, 20),
    Panel   = Color3.fromRGB(26, 24, 32),
    Hover   = Color3.fromRGB(36, 33, 45),
    Press   = Color3.fromRGB(46, 42, 58),
    Text    = Color3.fromRGB(234, 230, 240),
    Muted   = Color3.fromRGB(124, 118, 136),
    Accent  = Color3.fromRGB(232, 96, 74),
    Off     = Color3.fromRGB(56, 52, 66),
    Stroke  = Color3.fromRGB(48, 44, 58),
}

local FAST = TweenInfo.new(0.16, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local SLOW = TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

local function create(class, props, parent)
    local inst = Instance.new(class)
    for k, v in pairs(props) do inst[k] = v end
    if parent then inst.Parent = parent end
    return inst
end

local function corner(parent, radius)
    create("UICorner", { CornerRadius = UDim.new(0, radius) }, parent)
end

local function tween(obj, info, goal)
    local t = TweenService:Create(obj, info, goal)
    t:Play()
    return t
end

local function label(parent, text, size, font, color, pos, align)
    return create("TextLabel", {
        BackgroundTransparency = 1,
        Size = size,
        Position = pos or UDim2.new(),
        Font = font or Enum.Font.GothamMedium,
        TextSize = 13,
        TextColor3 = color or Theme.Text,
        TextXAlignment = align or Enum.TextXAlignment.Left,
        Text = text,
    }, parent)
end

local function guiParent()
    local ok, hui = pcall(function() return gethui and gethui() end)
    if ok and hui then return hui end
    return game:GetService("CoreGui")
end

function UI.new(settings, schema)
    local self = setmetatable({}, UI)
    self.settings = settings
    self.connections = {}
    self.open = true
    self.binding = nil

    local gui = create("ScreenGui", {
        Name = tostring(math.random(1e6, 9e6)),
        ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        IgnoreGuiInset = true,
    }, guiParent())
    self.gui = gui

    local main = create("Frame", {
        Size = UDim2.fromOffset(268, 0),
        Position = UDim2.new(0, 40, 0.5, -210),
        BackgroundColor3 = Theme.Bg,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        AutomaticSize = Enum.AutomaticSize.Y,
    }, gui)
    corner(main, 8)
    local stroke = create("UIStroke", { Color = Theme.Stroke, Thickness = 1 }, main)
    self.main = main
    self.stroke = stroke

    local header = create("Frame", {
        Size = UDim2.new(1, 0, 0, 40),
        BackgroundTransparency = 1,
    }, main)
    label(header, "mara", UDim2.new(1, -90, 1, 0), Enum.Font.GothamBold, Theme.Text, UDim2.fromOffset(14, 0))
    label(header, "INS", UDim2.new(0, 60, 1, 0), Enum.Font.Gotham, Theme.Muted,
        UDim2.new(1, -74, 0, 0), Enum.TextXAlignment.Right).TextSize = 11
    create("Frame", {
        Size = UDim2.new(1, -28, 0, 1),
        Position = UDim2.fromOffset(14, 40),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel = 0,
    }, main)

    local body = create("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        Position = UDim2.fromOffset(0, 46),
        BackgroundTransparency = 1,
        AutomaticSize = Enum.AutomaticSize.Y,
    }, main)
    create("UIListLayout", {
        Padding = UDim.new(0, 6),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, body)
    create("UIPadding", {
        PaddingLeft = UDim.new(0, 10),
        PaddingRight = UDim.new(0, 10),
        PaddingBottom = UDim.new(0, 12),
    }, body)
    self.body = body

    local order = 0
    local function nextOrder()
        order += 1
        return order
    end

    local function section(name)
        local row = label(body, string.upper(name), UDim2.new(1, 0, 0, 22), Enum.Font.GothamBold, Theme.Muted)
        row.TextSize = 11
        row.LayoutOrder = nextOrder()
    end

    local function rowFrame(height)
        local row = create("Frame", {
            Size = UDim2.new(1, 0, 0, height),
            BackgroundColor3 = Theme.Panel,
            BorderSizePixel = 0,
            LayoutOrder = nextOrder(),
        }, body)
        corner(row, 6)
        return row
    end

    local function hoverable(row, onPress)
        local btn = create("TextButton", {
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            Text = "",
            AutoButtonColor = false,
        }, row)
        table.insert(self.connections, btn.MouseEnter:Connect(function()
            tween(row, FAST, { BackgroundColor3 = Theme.Hover })
        end))
        table.insert(self.connections, btn.MouseLeave:Connect(function()
            tween(row, FAST, { BackgroundColor3 = Theme.Panel })
        end))
        table.insert(self.connections, btn.MouseButton1Down:Connect(function()
            tween(row, FAST, { BackgroundColor3 = Theme.Press })
        end))
        table.insert(self.connections, btn.MouseButton1Up:Connect(function()
            tween(row, FAST, { BackgroundColor3 = Theme.Hover })
        end))
        if onPress then
            table.insert(self.connections, btn.MouseButton1Click:Connect(onPress))
        end
        return btn
    end

    local function toggleRow(row_, key, text)
        local row = rowFrame(34)
        label(row, text, UDim2.new(1, -60, 1, 0), nil, Theme.Text, UDim2.fromOffset(12, 0))
        local track = create("Frame", {
            Size = UDim2.fromOffset(32, 16),
            Position = UDim2.new(1, -44, 0.5, -8),
            BorderSizePixel = 0,
        }, row)
        corner(track, 8)
        local knob = create("Frame", {
            Size = UDim2.fromOffset(12, 12),
            BackgroundColor3 = Theme.Text,
            BorderSizePixel = 0,
        }, track)
        corner(knob, 6)

        local function render(animate)
            local on = self.settings[key] == true
            local goalTrack = { BackgroundColor3 = on and Theme.Accent or Theme.Off }
            local goalKnob = { Position = on and UDim2.fromOffset(18, 2) or UDim2.fromOffset(2, 2) }
            if animate then
                tween(track, FAST, goalTrack)
                tween(knob, FAST, goalKnob)
            else
                track.BackgroundColor3 = goalTrack.BackgroundColor3
                knob.Position = goalKnob.Position
            end
        end
        render(false)

        hoverable(row, function()
            self.settings[key] = not self.settings[key]
            render(true)
        end)
        self.refreshers = self.refreshers or {}
        table.insert(self.refreshers, function() render(true) end)
    end

    local function sliderRow(key, text, min, max, step)
        local row = rowFrame(48)
        label(row, text, UDim2.new(1, -60, 0, 20), nil, Theme.Text, UDim2.fromOffset(12, 4))
        local val = label(row, "", UDim2.new(0, 40, 0, 20), Enum.Font.GothamMedium, Theme.Accent,
            UDim2.new(1, -52, 0, 4), Enum.TextXAlignment.Right)
        val.TextSize = 12

        local track = create("Frame", {
            Size = UDim2.new(1, -24, 0, 6),
            Position = UDim2.fromOffset(12, 32),
            BackgroundColor3 = Theme.Off,
            BorderSizePixel = 0,
        }, row)
        corner(track, 3)
        local fill = create("Frame", {
            Size = UDim2.new(0, 0, 1, 0),
            BackgroundColor3 = Theme.Accent,
            BorderSizePixel = 0,
        }, track)
        corner(fill, 3)
        local knob = create("Frame", {
            Size = UDim2.fromOffset(12, 12),
            AnchorPoint = Vector2.new(0.5, 0.5),
            BackgroundColor3 = Theme.Text,
            BorderSizePixel = 0,
        }, track)
        corner(knob, 6)

        local function render(animate)
            local v = self.settings[key]
            local frac = (v - min) / (max - min)
            local goalFill = { Size = UDim2.new(frac, 0, 1, 0) }
            local goalKnob = { Position = UDim2.new(frac, 0, 0.5, 0) }
            if animate then
                tween(fill, FAST, goalFill)
                tween(knob, FAST, goalKnob)
            else
                fill.Size = goalFill.Size
                knob.Position = goalKnob.Position
            end
            val.Text = step >= 1 and tostring(math.floor(v)) or string.format("%.2f", v)
        end
        render(false)

        local dragging = false
        local function update(x)
            local frac = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
            local raw = min + frac * (max - min)
            self.settings[key] = math.clamp(math.floor(raw / step + 0.5) * step, min, max)
            render(false)
        end

        table.insert(self.connections, track.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = true
                update(input.Position.X)
            end
        end))
        table.insert(self.connections, UserInputService.InputChanged:Connect(function(input)
            if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
                update(input.Position.X)
            end
        end))
        table.insert(self.connections, UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = false
            end
        end))
    end

    local function keybindRow(key, text)
        local row = rowFrame(34)
        label(row, text, UDim2.new(1, -110, 1, 0), nil, Theme.Text, UDim2.fromOffset(12, 0))
        local chip = create("TextLabel", {
            Size = UDim2.fromOffset(88, 20),
            Position = UDim2.new(1, -98, 0.5, -10),
            BackgroundColor3 = Theme.Off,
            BorderSizePixel = 0,
            Font = Enum.Font.GothamMedium,
            TextSize = 11,
            TextColor3 = Theme.Text,
        }, row)
        corner(chip, 4)

        local function render()
            local kc = self.settings[key]
            chip.Text = self.binding == key and "press key" or (kc and kc.Name or "none")
            chip.TextColor3 = self.binding == key and Theme.Accent or Theme.Text
        end
        render()
        self.refreshers = self.refreshers or {}
        table.insert(self.refreshers, render)

        hoverable(row, function()
            self.binding = key
            render()
        end)
    end

    local function buttonRow(text, callback)
        local row = rowFrame(34)
        label(row, text, UDim2.new(1, -24, 1, 0), Enum.Font.GothamMedium, Theme.Text, UDim2.fromOffset(12, 0))
        hoverable(row, callback)
    end

    for _, sec in ipairs(schema) do
        section(sec.name)
        for _, r in ipairs(sec.rows) do
            if r.type == "toggle" then
                toggleRow(nil, r.key, r.label)
            elseif r.type == "slider" then
                sliderRow(r.key, r.label, r.min, r.max, r.step)
            elseif r.type == "keybind" then
                keybindRow(r.key, r.label)
            elseif r.type == "button" then
                buttonRow(r.label, r.callback)
            end
        end
    end

    local function setOpen(state)
        self.open = state
        if state then
            main.Visible = true
            tween(main, SLOW, { BackgroundTransparency = 0, Position = UDim2.new(0, 40, 0.5, -210) })
            tween(stroke, SLOW, { Transparency = 0 })
        else
            tween(stroke, SLOW, { Transparency = 1 })
            local t = tween(main, SLOW, { BackgroundTransparency = 1, Position = UDim2.new(0, 28, 0.5, -210) })
            t.Completed:Connect(function()
                if not self.open then main.Visible = false end
            end)
        end
    end
    self.setOpen = setOpen

    -- drag by header
    do
        local dragging, dragStart, startPos
        table.insert(self.connections, header.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging, dragStart, startPos = true, input.Position, main.Position
            end
        end))
        table.insert(self.connections, UserInputService.InputChanged:Connect(function(input)
            if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
                local d = input.Position - dragStart
                main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
            end
        end))
        table.insert(self.connections, UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
        end))
    end

    -- INS toggle, and keybind capture
    table.insert(self.connections, UserInputService.InputBegan:Connect(function(input, processed)
        if self.binding then
            if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
            local key = self.binding
            self.binding = nil
            if input.KeyCode ~= Enum.KeyCode.Escape then
                self.settings[key] = input.KeyCode
            end
            for _, fn in ipairs(self.refreshers or {}) do fn() end
            return
        end
        if processed then return end
        if input.KeyCode == Enum.KeyCode.Insert then
            setOpen(not self.open)
        end
    end))

    setOpen(true)
    return self
end

function UI:IsOpen()
    return self.open
end

function UI:Toggle()
    self.setOpen(not self.open)
end

function UI:Destroy()
    for _, c in ipairs(self.connections) do c:Disconnect() end
    table.clear(self.connections)
    self.gui:Destroy()
end

return UI
