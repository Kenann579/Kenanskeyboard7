-- Mobile Virtual Keyboard (fixed)
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local StarterGui = game:GetService("StarterGui")

pcall(function()
    StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, true)
end)

-- Safe parent (executor hidden UI -> CoreGui -> PlayerGui)
local function getParent()
    local ok, ui = pcall(function() return gethui and gethui() end)
    if ok and ui then return ui end
    local ok2, cg = pcall(function() return game:GetService("CoreGui") end)
    if ok2 and cg then return cg end
    return Players.LocalPlayer:WaitForChild("PlayerGui")
end

local Parent = getParent()
local old = Parent:FindFirstChild("MobileKeyboard")
if old then old:Destroy() end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "MobileKeyboard"
ScreenGui.ResetOnSpawn = false
ScreenGui.IgnoreGuiInset = true
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = Parent

local COLOR_KEY = Color3.fromRGB(45, 45, 55)
local COLOR_PRESS = Color3.fromRGB(50, 200, 100)
local COLOR_SPAWN = Color3.fromRGB(120, 80, 220)

---------------------------------------------------------------------
-- Key sending
---------------------------------------------------------------------
local held = {}

local function send(keyCode, down)
    pcall(function()
        VirtualInputManager:SendKeyEvent(down, keyCode, false, game)
    end)
end

local function pressKey(k)
    if not k then return end
    held[k] = (held[k] or 0) + 1
    if held[k] == 1 then send(k, true) end
end

local function releaseKey(k)
    if not k or not held[k] then return end
    held[k] = held[k] - 1
    if held[k] <= 0 then
        held[k] = nil
        send(k, false)
    end
end

---------------------------------------------------------------------
-- Pointer tracking (touch + mouse)
---------------------------------------------------------------------
local function isPointer(input)
    return input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseButton1
end

local entries = {}

local function register(input, onEnd)
    local e = { input = input, onEnd = onEnd }
    table.insert(entries, e)
    return e
end

UserInputService.InputEnded:Connect(function(input)
    if not isPointer(input) then return end
    for i = #entries, 1, -1 do
        local e = entries[i]
        local same = e.input == input
            or (input.UserInputType == Enum.UserInputType.MouseButton1
                and e.input.UserInputType == Enum.UserInputType.MouseButton1)
        if same then
            table.remove(entries, i)
            e.onEnd()
        end
    end
end)

local function releaseAll()
    for i = #entries, 1, -1 do
        local e = entries[i]
        table.remove(entries, i)
        e.onEnd()
    end
    for k in pairs(held) do send(k, false) end
    held = {}
end

local function pos2(input)
    return Vector2.new(input.Position.X, input.Position.Y)
end

---------------------------------------------------------------------
-- Dragging (tap detection so dragging never toggles)
---------------------------------------------------------------------
local DRAG_THRESHOLD = 10

local function makeDraggable(gui, onTap)
    local entry, dragStart, startPos, moved

    gui.InputBegan:Connect(function(input)
        if not isPointer(input) or entry then return end
        dragStart = pos2(input)
        startPos = gui.Position
        moved = false
        entry = register(input, function()
            local wasTap = not moved
            entry = nil
            if wasTap and onTap then onTap() end
        end)
    end)

    UserInputService.InputChanged:Connect(function(input)
        if not entry then return end
        if input == entry.input or input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = pos2(input) - dragStart
            if not moved and delta.Magnitude > DRAG_THRESHOLD then moved = true end
            if moved then
                gui.Position = UDim2.new(
                    startPos.X.Scale, startPos.X.Offset + delta.X,
                    startPos.Y.Scale, startPos.Y.Offset + delta.Y
                )
            end
        end
    end)
end

---------------------------------------------------------------------
-- Toggle button + keyboard panel
---------------------------------------------------------------------
local ToggleButton = Instance.new("TextButton")
ToggleButton.Name = "CenterToggleBtn"
ToggleButton.Size = UDim2.new(0, 50, 0, 50)
ToggleButton.Position = UDim2.new(0.5, -25, 0, 10)
ToggleButton.BackgroundColor3 = Color3.fromRGB(80, 150, 255)
ToggleButton.BorderSizePixel = 0
ToggleButton.AutoButtonColor = false
ToggleButton.Text = "⌨"
ToggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
ToggleButton.TextSize = 22
ToggleButton.ZIndex = 100
ToggleButton.Active = true
ToggleButton.Parent = ScreenGui
Instance.new("UICorner", ToggleButton).CornerRadius = UDim.new(0, 10)

local KeyboardFrame = Instance.new("Frame")
KeyboardFrame.Name = "FullKeyboardPanel"
KeyboardFrame.Size = UDim2.new(0, 680, 0, 190)
KeyboardFrame.AnchorPoint = Vector2.new(0.5, 0)
KeyboardFrame.Position = UDim2.new(0.5, 0, 0, 70)
KeyboardFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
KeyboardFrame.BorderSizePixel = 0
KeyboardFrame.Visible = false
KeyboardFrame.ZIndex = 99
KeyboardFrame.Active = true
KeyboardFrame.Parent = ScreenGui
Instance.new("UICorner", KeyboardFrame).CornerRadius = UDim.new(0, 8)

-- Shrink to fit phone screens
local Scale = Instance.new("UIScale")
Scale.Parent = KeyboardFrame
local cam = workspace.CurrentCamera
if cam then
    Scale.Scale = math.clamp((cam.ViewportSize.X - 20) / 680, 0.4, 1)
end

local isOpen = false
local function setOpen(state)
    isOpen = state
    KeyboardFrame.Visible = isOpen
    ToggleButton.BackgroundColor3 = isOpen and COLOR_PRESS or Color3.fromRGB(80, 150, 255)
    if not isOpen then releaseAll() end
end

makeDraggable(ToggleButton, function() setOpen(not isOpen) end)
makeDraggable(KeyboardFrame)

---------------------------------------------------------------------
-- Spawned ("+") keys on the screen (Made smaller)
---------------------------------------------------------------------
local isAddingMode = false
local spawnCount = 0

local function spawnKey(text, keyCode, w, h)
    spawnCount += 1
    local off = (spawnCount % 6) * 14
    -- Smaller multiplier applied here
    w = math.max((w or 50) * 1.2, 55)
    h = math.max((h or 40) * 1.3, 45)

    local btn = Instance.new("TextButton")
    btn.Name = "CustomSpawnedBtn"
    btn.Size = UDim2.new(0, w, 0, h)
    btn.Position = UDim2.new(0.5, -w / 2 + off, 0.5, -h / 2 + off)
    btn.BackgroundColor3 = COLOR_SPAWN
    btn.BackgroundTransparency = 0.2
    btn.BorderSizePixel = 0
    btn.AutoButtonColor = false
    btn.Text = text
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.TextSize = 16
    btn.ZIndex = 110
    btn.Active = true
    btn.Parent = ScreenGui
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)

    -- small X delete button
    local closeBtn = Instance.new("TextButton")
    closeBtn.Name = "DeleteBtn"
    closeBtn.Size = UDim2.new(0, 14, 0, 14)
    closeBtn.Position = UDim2.new(1, -9, 0, -5)
    closeBtn.BackgroundColor3 = Color3.fromRGB(220, 50, 50)
    closeBtn.BorderSizePixel = 0
    closeBtn.AutoButtonColor = false
    closeBtn.Text = "X"
    closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    closeBtn.TextSize = 8
    closeBtn.ZIndex = 115
    closeBtn.Active = true
    closeBtn.Parent = btn
    Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(1, 0)

    local entry, dragStart, startPos, moved
    local pressed = false

    local function release()
        if pressed then
            pressed = false
            releaseKey(keyCode)
            btn.BackgroundColor3 = COLOR_SPAWN
        end
    end

    btn.InputBegan:Connect(function(input)
        if not isPointer(input) or entry then return end
        dragStart = pos2(input)
        startPos = btn.Position
        moved = false
        entry = register(input, function()
            entry = nil
            release()
        end)
        if keyCode then
            pressed = true
            pressKey(keyCode)
            btn.BackgroundColor3 = COLOR_PRESS
        end
    end)

    local moveConn = UserInputService.InputChanged:Connect(function(input)
        if not entry then return end
        if input == entry.input or input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = pos2(input) - dragStart
            if not moved and delta.Magnitude > DRAG_THRESHOLD then
                moved = true
                release()
            end
            if moved then
                btn.Position = UDim2.new(
                    startPos.X.Scale, startPos.X.Offset + delta.X,
                    startPos.Y.Scale, startPos.Y.Offset + delta.Y
                )
            end
        end
    end)

    closeBtn.Activated:Connect(function()
        release()
        btn:Destroy()
    end)

    btn.Destroying:Connect(function()
        release()
        moveConn:Disconnect()
    end)
end

---------------------------------------------------------------------
-- Keyboard keys
---------------------------------------------------------------------
local function createKey(name, text, keyCode, w, h, x, y)
    local btn = Instance.new("TextButton")
    btn.Name = name
    btn.Size = UDim2.new(0, w, 0, h)
    btn.Position = UDim2.new(0, x, 0, y)
    btn.BackgroundColor3 = COLOR_KEY
    btn.BorderSizePixel = 0
    btn.AutoButtonColor = false
    btn.Text = text
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.TextSize = 11
    btn.ZIndex = 100
    btn.Active = true
    btn.Parent = KeyboardFrame
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)

    local entry
    btn.InputBegan:Connect(function(input)
        if not isPointer(input) or entry then return end
        if isAddingMode then
            spawnKey(text, keyCode, w, h)
            return
        end
        if not keyCode then return end
        pressKey(keyCode)
        btn.BackgroundColor3 = COLOR_PRESS
        entry = register(input, function()
            entry = nil
            releaseKey(keyCode)
            btn.BackgroundColor3 = COLOR_KEY
        end)
    end)
    return btn
end

local function row(y, h, gap, items)
    local x = 10
    for _, it in ipairs(items) do
        createKey(it[1] .. y .. x, it[1], it[2], it[3], h, x, y)
        x = x + it[3] + gap
    end
end

local KC = Enum.KeyCode

row(8, 24, 5, {
    {"Esc", KC.Escape, 40},
    {"F1", KC.F1, 35}, {"F2", KC.F2, 35}, {"F3", KC.F3, 35}, {"F4", KC.F4, 35},
    {"F5", KC.F5, 35}, {"F6", KC.F6, 35}, {"F7", KC.F7, 35}, {"F8", KC.F8, 35},
    {"F9", KC.F9, 35}, {"F10", KC.F10, 35}, {"F11", KC.F11, 35}, {"F12", KC.F12, 35},
})

row(36, 26, 3, {
    {"`", KC.Backquote, 38}, {"1", KC.One, 38}, {"2", KC.Two, 38}, {"3", KC.Three, 38},
    {"4", KC.Four, 38}, {"5", KC.Five, 38}, {"6", KC.Six, 38}, {"7", KC.Seven, 38},
    {"8", KC.Eight, 38}, {"9", KC.Nine, 38}, {"0", KC.Zero, 38},
    {"-", KC.Minus, 38}, {"=", KC.Equals, 38},
})

row(64, 26, 3, {
    {"Tab", KC.Tab, 50},
    {"Q", KC.Q, 38}, {"W", KC.W, 38}, {"E", KC.E, 38}, {"R", KC.R, 38}, {"T", KC.T, 38},
    {"Y", KC.Y, 38}, {"U", KC.U, 38}, {"I", KC.I, 38}, {"O", KC.O, 38}, {"P", KC.P, 38},
    {"[", KC.LeftBracket, 38}, {"]", KC.RightBracket, 38}, {"\\", KC.BackSlash, 45},
})

row(92, 26, 3, {
    {"Caps", KC.CapsLock, 58},
    {"A", KC.A, 38}, {"S", KC.S, 38}, {"D", KC.D, 38}, {"F", KC.F, 38}, {"G", KC.G, 38},
    {"H", KC.H, 38}, {"J", KC.J, 38}, {"K", KC.K, 38}, {"L", KC.L, 38},
    {";", KC.Semicolon, 38}, {"'", KC.Quote, 38},
    {"Enter", KC.Return, 75},
})

row(120, 26, 3, {
    {"Shift", KC.LeftShift, 70},
    {"Z", KC.Z, 38}, {"X", KC.X, 38}, {"C", KC.C, 38}, {"V", KC.V, 38}, {"B", KC.B, 38},
    {"N", KC.N, 38}, {"M", KC.M, 38}, {",", KC.Comma, 38}, {".", KC.Period, 38},
    {"/", KC.Slash, 38},
    {"RShift", KC.RightShift, 70},
})

row(148, 26, 3, {
    {"Ctrl", KC.LeftControl, 55}, {"Alt", KC.LeftAlt, 50},
    {"Spacebar", KC.Space, 220},
    {"Alt", KC.RightAlt, 50}, {"Ctrl", KC.RightControl, 55},
    {"◄", KC.Left, 38}, {"▼", KC.Down, 38}, {"►", KC.Right, 38},
})

---------------------------------------------------------------------
-- "+" button: toggles key-generation mode
---------------------------------------------------------------------
local AddButton = Instance.new("TextButton")
AddButton.Name = "AddBtn"
AddButton.Size = UDim2.new(0, 40, 0, 24)
AddButton.Position = UDim2.new(0, 535, 0, 8)
AddButton.BackgroundColor3 = Color3.fromRGB(150, 50, 200)
AddButton.BorderSizePixel = 0
AddButton.AutoButtonColor = false
AddButton.Text = "+"
AddButton.TextColor3 = Color3.fromRGB(255, 255, 255)
AddButton.TextSize = 14
AddButton.ZIndex = 100
AddButton.Active = true
AddButton.Parent = KeyboardFrame
Instance.new("UICorner", AddButton).CornerRadius = UDim.new(0, 4)

AddButton.Activated:Connect(function()
    isAddingMode = not isAddingMode
    AddButton.BackgroundColor3 = isAddingMode
        and Color3.fromRGB(220, 180, 50)
        or Color3.fromRGB(150, 50, 200)
end)
