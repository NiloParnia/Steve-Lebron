-- ScreenGui/LocalScript  — CLEAN VERSION (no unlock stuff)

---------------- Services ----------------
local Players       = game:GetService("Players")
local Replicated    = game:GetService("ReplicatedStorage")
local TweenService  = game:GetService("TweenService")
local RunService    = game:GetService("RunService")
local StarterGui    = game:GetService("StarterGui")
local UIS           = game:GetService("UserInputService")
local TS            = game:GetService("TweenService")

local player = Players.LocalPlayer
local gui    = script.Parent  -- your existing ScreenGui instance
if gui:IsA("ScreenGui") then
	gui.IgnoreGuiInset = true -- normalize across Studio/live, center math stays true
end

---------------- Menu Pieces (placement only; toggle is at bottom) ----------------
local SmallIcon  = gui:WaitForChild("SmallIcon")
local MenuFrame  = gui:WaitForChild("MenuFrame")

-- small icon: always bottom-right
SmallIcon.AnchorPoint = Vector2.new(1,1)
SmallIcon.Position    = UDim2.new(1, -16, 1, -16) -- margin tweakable

-- menu: centered when open, dumped below screen when closed
MenuFrame.AnchorPoint = Vector2.new(0.5, 0.5)
local OPEN_POS   = UDim2.fromScale(0.5, 0.5)   -- camera/screen center
local CLOSED_POS = UDim2.new(0.5, 0, 1.2, 0)   -- dump below screen
MenuFrame.Position = CLOSED_POS
MenuFrame.Visible  = false

-- global-ish menu state for other blocks
local isMenuOpen = false

----------------------------------------------------------------
--                      HUD: COOLDOWNS (robust clocks + visible)
----------------------------------------------------------------
local RemoteEvents   = Replicated:WaitForChild("RemoteEvents")
local CooldownNotice = RemoteEvents:WaitForChild("CooldownNotice")

-- Toggle this to bypass unlockables filtering for testing
local ONLY_UNLOCKABLES = true

-- Live allow-list from ReplicatedStorage/Unlockables
local UNLOCKABLES_SET = {}
local function refreshUnlockablesClient()
	table.clear(UNLOCKABLES_SET)
	local f = Replicated:FindFirstChild("Unlockables")
	if f then
		for _, sv in ipairs(f:GetChildren()) do
			if sv:IsA("StringValue") and sv.Value ~= "" then
				UNLOCKABLES_SET[sv.Value] = true
			end
		end
	end
end
refreshUnlockablesClient()
local uf = Replicated:FindFirstChild("Unlockables")
if uf then
	uf.ChildAdded:Connect(refreshUnlockablesClient)
	uf.ChildRemoved:Connect(refreshUnlockablesClient)
end

-- Container (top-right)
local cdContainer = Instance.new("Frame")
cdContainer.Name = "CooldownStack"
cdContainer.AnchorPoint = Vector2.new(1,0)
cdContainer.Position = UDim2.new(1, -12, 0, 12)
cdContainer.Size = UDim2.new(0, 260, 1, -24)
cdContainer.BackgroundTransparency = 1
cdContainer.Visible = false
cdContainer.Parent = gui

local cdList = Instance.new("UIListLayout")
cdList.FillDirection = Enum.FillDirection.Vertical
cdList.HorizontalAlignment = Enum.HorizontalAlignment.Right
cdList.VerticalAlignment = Enum.VerticalAlignment.Top
cdList.SortOrder = Enum.SortOrder.LayoutOrder
cdList.Padding = UDim.new(0, 6)
cdList.Parent = cdContainer

local cdItems = {} -- [name] = {frame,label,bar,endsAtClock,duration}

local function setCdContainerVisible()
	for _ in pairs(cdItems) do
		cdContainer.Visible = true
		return
	end
	cdContainer.Visible = false
end

local function createCdItem(name: string)
	local f = Instance.new("Frame")
	f.Name = name
	f.Size = UDim2.new(0, 260, 0, 34)
	f.BackgroundColor3 = Color3.fromRGB(25,25,25)
	f.BackgroundTransparency = 0.15
	f.BorderSizePixel = 0
	f.Parent = cdContainer

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, -10, 1, -14)
	title.Position = UDim2.new(0, 10, 0, 2)
	title.Font = Enum.Font.GothamSemibold
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Color3.new(1,1,1)
	title.TextScaled = true
	title.Text = name .. ": 0.0s"
	title.Parent = f

	local barBg = Instance.new("Frame")
	barBg.BorderSizePixel = 0
	barBg.BackgroundColor3 = Color3.fromRGB(50,50,50)
	barBg.Size = UDim2.new(1, -12, 0, 4)
	barBg.Position = UDim2.new(0, 6, 1, -6)
	barBg.Parent = f

	local bar = Instance.new("Frame")
	bar.BorderSizePixel = 0
	bar.BackgroundColor3 = Color3.fromRGB(120,200,255)
	bar.Size = UDim2.new(0, 0, 1, 0)
	bar.Parent = barBg

	cdItems[name] = {frame=f, label=title, bar=bar, endsAtClock=0, duration=0}
	setCdContainerVisible()
	return cdItems[name]
end

local function destroyCdItem(name)
	local it = cdItems[name]
	if not it then return end
	if it.frame then it.frame:Destroy() end
	cdItems[name] = nil
	setCdContainerVisible()
end

-- Convert whatever the server sends into "remaining seconds"
local function computeRemaining(payload, duration)
	if payload and tonumber(payload.remaining) then
		return math.max(0, tonumber(payload.remaining))
	end
	if payload and tonumber(payload.endsAtEpoch) then
		return math.max(0, tonumber(payload.endsAtEpoch) - time())
	end
	if payload and tonumber(payload.started) and tonumber(payload.started) > 1e6 then
		return math.max(0, (tonumber(payload.started) + duration) - time())
	end
	return math.max(0, duration)
end

CooldownNotice.OnClientEvent:Connect(function(payload)
	if not payload or not payload.name then
		warn("[Cooldown] Missing payload/name:", payload)
		return
	end

	local name = tostring(payload.name)

	if ONLY_UNLOCKABLES and not UNLOCKABLES_SET[name] then
		warn(("[Cooldown] '%s' ignored (not in Unlockables)."):format(name))
		return
	end

	local duration = tonumber(payload.duration) or 0
	local remaining = computeRemaining(payload, duration)

	local it = cdItems[name] or createCdItem(name)
	it.duration = duration > 0 and duration or math.max(remaining, 0.001)
	it.endsAtClock = os.clock() + remaining  -- convert to client's clock domain

	local r = math.max(0, it.endsAtClock - os.clock())
	it.label.Text = string.format("%s: %.1fs", name, r)
	it.bar.Size   = UDim2.new(1 - (r / it.duration), 0, 1, 0)
	it.frame.LayoutOrder = math.floor(r * 1000)

	print(("[Cooldown] show '%s' for %.2fs (dur=%.2f)"):format(name, r, it.duration))
end)

RunService.RenderStepped:Connect(function()
	local nowClock = os.clock()
	for name, it in pairs(cdItems) do
		local remaining = math.max(0, it.endsAtClock - nowClock)
		local dur = it.duration > 0 and it.duration or 1

		it.label.Text = remaining > 0 and string.format("%s: %.1fs", name, remaining) or (name .. ": READY")
		it.bar.Size   = UDim2.new(1 - (remaining/dur), 0, 1, 0)

		if remaining <= 0 then
			it.bar.BackgroundColor3 = Color3.fromRGB(120,255,170)
		elseif remaining <= 1.5 then
			it.bar.BackgroundColor3 = Color3.fromRGB(255,200,120)
		else
			it.bar.BackgroundColor3 = Color3.fromRGB(120,200,255)
		end

		it.frame.LayoutOrder = math.floor(remaining * 1000)

		if remaining <= 0 then
			local stamp = nowClock
			task.delay(0.35, function()
				local cur = cdItems[name]
				if cur and cur.endsAtClock <= stamp then
					destroyCdItem(name)
				end
			end)
		end
	end
end)

----------------------------------------------------------------
--                HUD: HEALTH (top-middle)
----------------------------------------------------------------
StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)

local healthFrame = Instance.new("Frame")
healthFrame.Name = "HealthBar"
healthFrame.AnchorPoint = Vector2.new(0.5, 0)
healthFrame.Position = UDim2.new(0.5, 0, 0, 12)
healthFrame.Size = UDim2.new(0, 220, 0, 20)
healthFrame.BackgroundColor3 = Color3.fromRGB(25,25,25)
healthFrame.BackgroundTransparency = 0.2
healthFrame.BorderSizePixel = 0
healthFrame.Parent = gui

local hbBg = Instance.new("Frame")
hbBg.Size = UDim2.new(1, -8, 1, -8)
hbBg.Position = UDim2.new(0, 4, 0, 4)
hbBg.BackgroundColor3 = Color3.fromRGB(50,50,50)
hbBg.BorderSizePixel = 0
hbBg.Parent = healthFrame

local hbFill = Instance.new("Frame")
hbFill.Name = "Fill"
hbFill.Size = UDim2.new(1, 0, 1, 0)
hbFill.BackgroundColor3 = Color3.fromRGB(120,255,170)
hbFill.BorderSizePixel = 0
hbFill.Parent = hbBg

local hbLabel = Instance.new("TextLabel")
hbLabel.BackgroundTransparency = 1
hbLabel.Size = UDim2.new(1, 0, 1, 0)
hbLabel.TextXAlignment = Enum.TextXAlignment.Center
hbLabel.Font = Enum.Font.GothamBold
hbLabel.TextColor3 = Color3.new(1,1,1)
hbLabel.TextScaled = true
hbLabel.Text = "100 / 100"
hbLabel.Parent = healthFrame

local function hookHumanoid(hum)
	if not hum then return end
	local function refreshHP()
		local hp  = math.max(0, hum.Health)
		local max = math.max(1, hum.MaxHealth)
		local t   = hp / max
		hbFill.Size = UDim2.new(t, 0, 1, 0)
		hbLabel.Text = string.format("%d / %d", math.floor(hp + 0.5), math.floor(max + 0.5))
		if t <= 0.25 then
			hbFill.BackgroundColor3 = Color3.fromRGB(255,110,110)
		elseif t <= 0.5 then
			hbFill.BackgroundColor3 = Color3.fromRGB(255,200,120)
		else
			hbFill.BackgroundColor3 = Color3.fromRGB(120,255,170)
		end
	end
	refreshHP()
	hum:GetPropertyChangedSignal("Health"):Connect(refreshHP)
	hum:GetPropertyChangedSignal("MaxHealth"):Connect(refreshHP)
end

local function onCharacter(char)
	local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid")
	hookHumanoid(hum)
end

if player.Character then onCharacter(player.Character) end
player.CharacterAdded:Connect(onCharacter)

----------------------------------------------------------------
--                HUD: DODGE CHARGES (under health)
----------------------------------------------------------------
local DodgeEvt = RemoteEvents:WaitForChild("DodgeCharges")

local chargesFrame = Instance.new("Frame")
chargesFrame.Name = "DodgeCharges"
chargesFrame.AnchorPoint = Vector2.new(0.5, 0)
chargesFrame.Position = UDim2.new(0.5, 0, 0, 36)   -- just under health bar
chargesFrame.Size = UDim2.new(0, 120, 0, 10)
chargesFrame.BackgroundTransparency = 1
chargesFrame.Parent = gui

local hlist = Instance.new("UIListLayout")
hlist.FillDirection = Enum.FillDirection.Horizontal
hlist.HorizontalAlignment = Enum.HorizontalAlignment.Center
hlist.VerticalAlignment = Enum.VerticalAlignment.Top
hlist.Padding = UDim.new(0, 6)
hlist.Parent = chargesFrame

local dodgeBars = {}
for i=1,3 do
	local slot = Instance.new("Frame")
	slot.Size = UDim2.new(0, 32, 1, 0)
	slot.BackgroundColor3 = Color3.fromRGB(40,100,255)
	slot.BackgroundTransparency = 0.35
	slot.BorderSizePixel = 0
	slot.Parent = chargesFrame

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(1, 0, 1, 0)
	fill.BackgroundColor3 = Color3.fromRGB(90,170,255)
	fill.BorderSizePixel = 0
	fill.Parent = slot

	dodgeBars[i] = slot
end

local function setDodgeCount(n)
	for i=1,3 do
		local active = i <= n
		local slot = dodgeBars[i]
		if active then
			slot.Fill.Visible = true
			slot.BackgroundTransparency = 0.15
		else
			slot.Fill.Visible = false
			slot.BackgroundTransparency = 0.85
		end
	end
end

DodgeEvt.OnClientEvent:Connect(function(current, max)
	setDodgeCount(tonumber(current) or 0)
end)

setDodgeCount(3) -- default to full; server will correct

----------------------------------------------------------------
--                DIALOGUE (inline, minimal) — low middle, no clipping
----------------------------------------------------------------
local Remotes         = Replicated:WaitForChild("RemoteEvents")
local BeginDialogue   = Remotes:WaitForChild("BeginDialogue")
local ChooseOption    = Remotes:WaitForChild("ChooseOption")
local DialogueUpdate  = Remotes:WaitForChild("DialogueUpdate")

-- container
local dlgGui = Instance.new("Frame")
dlgGui.Name = "Dialogue"
dlgGui.AnchorPoint = Vector2.new(0.5, 1)          -- bottom-aligned
dlgGui.Position = UDim2.fromScale(0.5, 0.95)      -- low middle by default
dlgGui.Size = UDim2.new(0.62, 0, 0, 180)
dlgGui.BackgroundTransparency = 0.05
dlgGui.Visible = false
dlgGui.Parent = gui

local dlgCorner = Instance.new("UICorner"); dlgCorner.CornerRadius = UDim.new(0, 16); dlgCorner.Parent = dlgGui
local dlgPad = Instance.new("UIPadding"); dlgPad.PaddingTop = UDim.new(0,12); dlgPad.PaddingBottom = UDim.new(0,12); dlgPad.PaddingLeft = UDim.new(0,12); dlgPad.PaddingRight = UDim.new(0,12); dlgPad.Parent = dlgGui

local dlgText = Instance.new("TextLabel")
dlgText.BackgroundTransparency = 1
dlgText.Size = UDim2.new(1, 0, 0, 86)
dlgText.TextWrapped = true
dlgText.TextXAlignment = Enum.TextXAlignment.Left
dlgText.TextYAlignment = Enum.TextYAlignment.Top
dlgText.Font = Enum.Font.Gotham
dlgText.TextSize = 20
dlgText.TextColor3 = Color3.new(125,125,125)
dlgText.Text = ""
dlgText.Parent = dlgGui

local optsHolder = Instance.new("Frame")
optsHolder.Position = UDim2.new(0, 0, 0, 90)
optsHolder.Size = UDim2.new(1, 0, 1, -90)
optsHolder.BackgroundTransparency = 1
optsHolder.Parent = dlgGui

local optsList = Instance.new("UIListLayout")
optsList.Padding = UDim.new(0, 6)
optsList.FillDirection = Enum.FillDirection.Vertical
optsList.HorizontalAlignment = Enum.HorizontalAlignment.Left
optsList.Parent = optsHolder

local function clearOptions()
	for _, c in ipairs(optsHolder:GetChildren()) do
		if c:IsA("TextButton") then c:Destroy() end
	end
end

local function makeOption(label, onClick)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, 0, 0, 34)
	b.Font = Enum.Font.GothamSemibold
	b.TextSize = 18
	b.TextColor3 = Color3.new(255,255,255)
	b.Text = label
	b.AutoButtonColor = true
	b.BackgroundTransparency = 0.15
	local ic = Instance.new("UICorner"); ic.CornerRadius = UDim.new(0, 10); ic.Parent = b
	b.Parent = optsHolder
	b.MouseButton1Click:Connect(onClick)
end

local activeStoryId, activeNodeId

local function closeDialogue()
	dlgGui.Visible = false
	dlgText.Text = ""
	clearOptions()
	activeStoryId, activeNodeId = nil, nil
end

-- viewport-safe positioning
local function updateDialoguePosition()
	local cam = workspace.CurrentCamera
	if not cam then return end
	local vpY = cam.ViewportSize.Y > 0 and cam.ViewportSize.Y or 1080
	local bottomMargin = 24 -- px above bottom edge
	local halfH = dlgGui.AbsoluteSize.Y * 0.5
	local safeScale = 1 - math.max(bottomMargin, halfH) / vpY
	local yScale = 1 - (bottomMargin / vpY)
	dlgGui.Position = UDim2.fromScale(0.5, math.min(yScale, safeScale))
end

local function hookCam(cam)
	if not cam then return end
	cam:GetPropertyChangedSignal("ViewportSize"):Connect(updateDialoguePosition)
end
hookCam(workspace.CurrentCamera)
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	hookCam(workspace.CurrentCamera)
	updateDialoguePosition()
end)
task.defer(updateDialoguePosition)

local function openDialogue(text, options, storyId, nodeId)
	dlgGui.Visible = true
	dlgText.Text = text or ""
	clearOptions()
	activeStoryId, activeNodeId = storyId, nodeId
	for i, opt in ipairs(options or {}) do
		makeOption(tostring(opt.label or ("Option "..i)), function()
			ChooseOption:FireServer(storyId, nodeId, i)
		end)
	end
	updateDialoguePosition()
end

DialogueUpdate.OnClientEvent:Connect(function(payload)
	print("[Client] DialogueUpdate", payload and payload.storyId, payload and payload.nodeId, "isEnd=", payload and payload.isEnd)
	if not payload then return end
	if payload.isEnd then
		closeDialogue()
		return
	end
	openDialogue(payload.text or "", payload.options or {}, payload.storyId, payload.nodeId)
end)

BeginDialogue.OnClientEvent:Connect(function(storyId, startNode)
	BeginDialogue:FireServer(storyId, startNode)
end)

----------------------------------------------------------------
-- KEYBINDS (5-slot system; menu tween-in; robust initial refresh)
----------------------------------------------------------------
local RE  = Replicated:WaitForChild("RemoteEvents")
local ActivateNode = RE:WaitForChild("ActivateNode")
local GetKeybinds  = RE:WaitForChild("GetKeybinds")
local SetKeybind   = RE:WaitForChild("SetKeybind")
local GetUnlocked  = RE:WaitForChild("GetUnlockedNodes")

-- Use KeyCode.Name strings everywhere (server expects these)
local KEYNAME_TO_KEYCODE = {
	One=Enum.KeyCode.One, Two=Enum.KeyCode.Two, Three=Enum.KeyCode.Three, Four=Enum.KeyCode.Four, Five=Enum.KeyCode.Five,
	Six=Enum.KeyCode.Six, Seven=Enum.KeyCode.Seven, Eight=Enum.KeyCode.Eight, Nine=Enum.KeyCode.Nine, Zero=Enum.KeyCode.Zero,
	Z=Enum.KeyCode.Z, X=Enum.KeyCode.X, C=Enum.KeyCode.C, V=Enum.KeyCode.V, B=Enum.KeyCode.B, N=Enum.KeyCode.N, M=Enum.KeyCode.M,
}
local KEYNAME_TO_LABEL = {
	One="1", Two="2", Three="3", Four="4", Five="5",
	Six="6", Seven="7", Eight="8", Nine="9", Zero="0",
	Z="Z", X="X", C="C", V="V", B="B", N="N", M="M",
}

-- UI: 5 slots at bottom center (hidden until menu is open)
local bar = Instance.new("Frame")
bar.Name = "KeybindBar"
bar.AnchorPoint = Vector2.new(0.5, 1)
local KB_OPEN_POS  = UDim2.new(0.5, 0, 1, -72)
local KB_CLOSED_POS= UDim2.new(0.5, 0, 1,  20)
bar.Position = KB_CLOSED_POS
bar.Size = UDim2.new(0, 520, 0, 48)
bar.BackgroundTransparency = 1 -- start hidden (we tween to 0.2 on open)
bar.BackgroundColor3 = Color3.fromRGB(25,25,25)
bar.Visible = false
bar.Parent = gui

local barCorner = Instance.new("UICorner"); barCorner.CornerRadius = UDim.new(0, 12); barCorner.Parent = bar
local list = Instance.new("UIListLayout")
list.FillDirection = Enum.FillDirection.Horizontal
list.Padding = UDim.new(0, 8)
list.HorizontalAlignment = Enum.HorizontalAlignment.Center
list.Parent = bar

local slots = {} -- { [1..5] = {frame, keyLabel, nodeLabel, btn, delBtn, keyCode?, keyName?, nodeName?} }
for i=1,5 do
	local f = Instance.new("Frame"); f.Size = UDim2.new(0, 96, 1, -8); f.Position = UDim2.new(0,0,0,4)
	f.BackgroundColor3 = Color3.fromRGB(40,40,40); f.BackgroundTransparency = 1; f.Parent = bar
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,10); c.Parent = f

	local key = Instance.new("TextLabel")
	key.Size = UDim2.new(0, 30, 1, 0); key.Position = UDim2.new(0, 6, 0, 0)
	key.BackgroundTransparency = 1; key.Font = Enum.Font.GothamBlack; key.TextSize = 18
	key.TextColor3 = Color3.fromRGB(255,255,255); key.TextXAlignment = Enum.TextXAlignment.Left
	key.TextTransparency = 1
	key.Text = "-"
	key.Parent = f

	local node = Instance.new("TextLabel")
	node.Size = UDim2.new(1, -62, 1, 0); node.Position = UDim2.new(0, 40, 0, 0)
	node.BackgroundTransparency = 1; node.Font = Enum.Font.Gotham; node.TextSize = 16
	node.TextColor3 = Color3.fromRGB(245,245,255); node.TextXAlignment = Enum.TextXAlignment.Left
	node.TextTransparency = 1
	node.Text = "Empty"
	node.Parent = f

	-- click area to (re)bind
	local btn = Instance.new("TextButton")
	btn.BackgroundTransparency = 1
	btn.Size = UDim2.new(1, -24, 1, 0) -- leave room for delete ✕
	btn.Text = ""
	btn.Parent = f

	-- delete / unbind (✕) button
	local del = Instance.new("TextButton")
	del.Size = UDim2.new(0, 20, 0, 20)
	del.Position = UDim2.new(1, -22, 0.5, -10)
	del.BackgroundColor3 = Color3.fromRGB(70,70,70)
	del.BackgroundTransparency = 1
	del.Text = "✕"
	del.Font = Enum.Font.GothamBold
	del.TextSize = 14
	del.TextColor3 = Color3.fromRGB(245,245,255)
	del.TextTransparency = 1
	del.Visible = false
	del.Parent = f
	local dc = Instance.new("UICorner"); dc.CornerRadius = UDim.new(1,0); dc.Parent = del

	slots[i] = {frame=f, keyLabel=key, nodeLabel=node, btn=btn, delBtn=del, keyCode=nil, keyName=nil, nodeName=nil}
end

-- Overlay chooser
local overlay = Instance.new("Frame")
overlay.Visible = false
overlay.AnchorPoint = Vector2.new(0.5, 0.5)
overlay.Position = UDim2.new(0.5, 0, 0.5, 0)
overlay.Size = UDim2.new(0, 360, 0, 300)
overlay.BackgroundColor3 = Color3.fromRGB(20,20,20)
overlay.BackgroundTransparency = 0.1
overlay.Parent = gui
local oc = Instance.new("UICorner"); oc.CornerRadius = UDim.new(0,12); oc.Parent = overlay
local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1; title.Size = UDim2.new(1, -16, 0, 28); title.Position = UDim2.new(0, 8, 0, 8)
title.Font = Enum.Font.GothamBold; title.TextSize = 18; title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = Color3.fromRGB(245,245,255)
title.Text = "Press a key (1-0 or Z-M)…"
title.Parent = overlay

-- Unbind + Cancel row
local actions = Instance.new("Frame")
actions.BackgroundTransparency = 1
actions.Size = UDim2.new(1, -16, 0, 28)
actions.Position = UDim2.new(0, 8, 1, -36)
actions.Parent = overlay
local cancel = Instance.new("TextButton")
cancel.Size = UDim2.new(0, 100, 1, 0); cancel.Position = UDim2.new(1, -108, 0, 0)
cancel.BackgroundTransparency = 0.2; cancel.BackgroundColor3 = Color3.fromRGB(60,60,60)
cancel.Font = Enum.Font.GothamSemibold; cancel.TextSize = 16; cancel.TextColor3 = Color3.fromRGB(245,245,255)
cancel.Text = "Cancel"; cancel.Parent = actions
local oc2 = Instance.new("UICorner"); oc2.CornerRadius = UDim.new(0,8); oc2.Parent = cancel
local unbindBtn = Instance.new("TextButton")
unbindBtn.Size = UDim2.new(0, 110, 1, 0); unbindBtn.Position = UDim2.new(0, 0, 0, 0)
unbindBtn.BackgroundTransparency = 0.2; unbindBtn.BackgroundColor3 = Color3.fromRGB(80,50,50)
unbindBtn.Font = Enum.Font.GothamSemibold; unbindBtn.TextSize = 16; unbindBtn.TextColor3 = Color3.fromRGB(255,235,235)
unbindBtn.Text = "Unbind Key"; unbindBtn.Parent = actions
local oc3 = Instance.new("UICorner"); oc3.CornerRadius = UDim.new(0,8); oc3.Parent = unbindBtn

local scroll = Instance.new("ScrollingFrame")
scroll.Position = UDim2.new(0, 8, 0, 40); scroll.Size = UDim2.new(1, -16, 0, 220)
scroll.BackgroundTransparency = 1; scroll.CanvasSize = UDim2.new(0,0,0,0); scroll.ScrollBarThickness = 6
scroll.Parent = overlay
local sl = Instance.new("UIListLayout"); sl.Padding = UDim.new(0,6); sl.Parent = scroll

-- State
local activeMap = {} -- [KeyCode] = nodeName
local listeningSlot = nil
local pendingKeyName = nil

-- Render
local function renderBinds(map)
	table.clear(activeMap)
	local items = {}
	for k,v in pairs(map) do table.insert(items, {key=k, node=v}) end
	table.sort(items, function(a,b) return a.key < b.key end)
	for i=1,5 do
		local s = slots[i]
		local item = items[i]
		if item then
			local kc = KEYNAME_TO_KEYCODE[item.key]
			s.keyCode = kc; s.keyName = item.key; s.nodeName = item.node
			s.keyLabel.Text = KEYNAME_TO_LABEL[item.key] or item.key
			s.nodeLabel.Text = item.node
			if kc then activeMap[kc] = item.node end
			s.delBtn.Visible = true
		else
			s.keyCode = nil; s.keyName = nil; s.nodeName = nil
			s.keyLabel.Text = "-"
			s.nodeLabel.Text = "Empty"
			s.delBtn.Visible = false
		end
	end
end

-- Safe refresh (with pcall)
local function refresh()
	local ok, serverMap = pcall(function() return GetKeybinds:InvokeServer() end)
	renderBinds(ok and serverMap or {})
end

-- Boot-time extra refresh attempts (handles profile not-ready)
task.defer(function()
	refresh()
	task.wait(0.4); refresh()
	task.wait(0.8); refresh()
end)

local function closeOverlay()
	overlay.Visible = false
	listeningSlot = nil
	pendingKeyName = nil
end

local function openChooser(slotIndex)
	if not isMenuOpen then return end
	listeningSlot = slotIndex
	pendingKeyName = nil
	title.Text = "Press a key (1-0 or Z-M)…"
	for _, child in ipairs(scroll:GetChildren()) do
		if child:IsA("TextButton") or child:IsA("TextLabel") then child:Destroy() end
	end
	overlay.Visible = true
end

cancel.MouseButton1Click:Connect(closeOverlay)

-- Unbind current pending key (after a key is chosen)
unbindBtn.MouseButton1Click:Connect(function()
	if not pendingKeyName then return end
	local res = SetKeybind:InvokeServer({ key = pendingKeyName, node = "" })
	closeOverlay()
	if res and res.binds then renderBinds(res.binds) else refresh() end
end)

-- Populate node list for chosen key (unlockables only)
local function populateNodesForKey()
	title.Text = string.format("Select node for key [%s]", KEYNAME_TO_LABEL[pendingKeyName] or pendingKeyName)
	for _, child in ipairs(scroll:GetChildren()) do
		if child:IsA("TextButton") or child:IsA("TextLabel") then child:Destroy() end
	end

	local ok, unlocked = pcall(function() return GetUnlocked:InvokeServer() end)
	unlocked = ok and unlocked or {}

	-- Safety: also local-filter against RS/Unlockables in case server changes
	local f = Replicated:FindFirstChild("Unlockables")
	local localSet = {}
	if f then
		for _, sv in ipairs(f:GetChildren()) do
			if sv:IsA("StringValue") and sv.Value ~= "" then localSet[sv.Value] = true end
		end
	end

	for _, name in ipairs(unlocked) do
		if localSet[name] then
			local b = Instance.new("TextButton")
			b.Size = UDim2.new(1, -8, 0, 28)
			b.BackgroundTransparency = 0.2
			b.BackgroundColor3 = Color3.fromRGB(45,45,45)
			b.Font = Enum.Font.GothamSemibold
			b.TextSize = 16
			b.TextXAlignment = Enum.TextXAlignment.Left
			b.TextColor3 = Color3.fromRGB(245,245,255)
			b.Text = name
			b.Parent = scroll
			local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0,8); bc.Parent = b
			b.MouseButton1Click:Connect(function()
				local res = SetKeybind:InvokeServer({ key = pendingKeyName, node = name })
				closeOverlay()
				if res and res.binds then renderBinds(res.binds) else refresh() end
			end)
		end
	end
	scroll.CanvasSize = UDim2.new(0,0,0, (#unlocked)*34)
end

-- Slot click: open chooser / delete
for i=1,5 do
	slots[i].btn.MouseButton1Click:Connect(function()
		openChooser(i)
	end)
	slots[i].delBtn.MouseButton1Click:Connect(function()
		local s = slots[i]
		if not s.keyName then return end
		local res = SetKeybind:InvokeServer({ key = s.keyName, node = "" })
		if res and res.binds then renderBinds(res.binds) else refresh() end
	end)
end

-- Input handling: choose key, Backspace to unbind, normal activation
UIS.InputBegan:Connect(function(input, gp)
	if gp or input.UserInputType ~= Enum.UserInputType.Keyboard then return end
	local kc = input.KeyCode

	-- If chooser open: accept key or allow Backspace to unbind
	if listeningSlot then
		if kc == Enum.KeyCode.Backspace then
			if pendingKeyName then
				local res = SetKeybind:InvokeServer({ key = pendingKeyName, node = "" })
				closeOverlay()
				if res and res.binds then renderBinds(res.binds) else refresh() end
			end
			return
		end

		local name = kc.Name -- "One","Two","Z",...
		if KEYNAME_TO_KEYCODE[name] then
			pendingKeyName = name
			populateNodesForKey()
		end
		return
	end

	-- Normal play: trigger bound node (send camera dir + camera right)
	local node = activeMap[kc]
	if node and node ~= "" then
		local cam = workspace.CurrentCamera
		local dir = cam and cam.CFrame.LookVector or nil
		local right = cam and cam.CFrame.RightVector or nil
		ActivateNode:FireServer(node, dir, right)
	end
end)

-- ======= Keybind bar tweens =======
local function tweenBarIn()
	bar.Visible = true
	bar.Position = KB_CLOSED_POS
	bar.BackgroundTransparency = 1
	for _, s in ipairs(slots) do
		s.frame.BackgroundTransparency = 1
		s.keyLabel.TextTransparency = 1
		s.nodeLabel.TextTransparency = 1
		s.delBtn.TextTransparency = 1
		s.delBtn.BackgroundTransparency = 1
	end

	TS:Create(bar, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = KB_OPEN_POS,
		BackgroundTransparency = 0.2
	}):Play()

	for _, s in ipairs(slots) do
		TS:Create(s.frame, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundTransparency = 0.1
		}):Play()
		TS:Create(s.keyLabel, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			TextTransparency = 0
		}):Play()
		TS:Create(s.nodeLabel, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			TextTransparency = 0
		}):Play()
		if s.delBtn.Visible then
			TS:Create(s.delBtn, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				TextTransparency = 0,
				BackgroundTransparency = 0.2
			}):Play()
		end
	end
end

local function tweenBarOut()
	TS:Create(bar, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Position = KB_CLOSED_POS,
		BackgroundTransparency = 1
	}):Play()
	for _, s in ipairs(slots) do
		TS:Create(s.frame, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			BackgroundTransparency = 1
		}):Play()
		TS:Create(s.keyLabel, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			TextTransparency = 1
		}):Play()
		TS:Create(s.nodeLabel, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			TextTransparency = 1
		}):Play()
		TS:Create(s.delBtn, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			TextTransparency = 1,
			BackgroundTransparency = 1
		}):Play()
	end
	task.delay(0.26, function()
		if bar then bar.Visible = false end
	end)
end

----------------------------------------------------------------
--       FINAL MENU TOGGLE (single handler, bulletproof hide)
----------------------------------------------------------------
do
	local state = "closed" -- "closed","opening","open","closing"
	local tween  : Tween? = nil
	local doneCn : RBXScriptConnection? = nil
	local OPEN_T  = 0.4
	local CLOSE_T = 0.25

	local function stopTween()
		if tween then tween:Cancel(); tween = nil end
		if doneCn then doneCn:Disconnect(); doneCn = nil end
	end

	local function openMenu()
		stopTween()
		state = "opening"
		isMenuOpen = true
		MenuFrame.Visible = true
		tween = TweenService:Create(MenuFrame, TweenInfo.new(OPEN_T, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = OPEN_POS
		})
		doneCn = tween.Completed:Connect(function(pb)
			if pb and pb ~= Enum.PlaybackState.Completed then return end
			state = "open"
		end)
		tween:Play()

		-- keybind hooks
		pcall(refresh)
		tweenBarIn()
	end

	local function closeMenu()
		stopTween()
		state = "closing"
		isMenuOpen = false
		MenuFrame.Visible = true -- keep visible during tween out
		tween = TweenService:Create(MenuFrame, TweenInfo.new(CLOSE_T, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = CLOSED_POS
		})
		doneCn = tween.Completed:Connect(function(pb)
			if pb and pb ~= Enum.PlaybackState.Completed then return end
			state = "closed"
			MenuFrame.Visible = false
		end)
		tween:Play()

		-- keybind hooks
		tweenBarOut()
		closeOverlay()

		-- fallback: hide even if Completed never fires
		task.delay(CLOSE_T + 0.05, function()
			if state ~= "open" and tween == nil then
				state = "closed"
				MenuFrame.Visible = false
			end
		end)
	end

	SmallIcon.MouseButton1Click:Connect(function()
		if state == "open" or state == "opening" then
			closeMenu()
		else
			openMenu()
		end
	end)

	-- optional helper if you ever need to force-close from elsewhere:
	_G.ForceCloseMenu = function()
		stopTween()
		state = "closed"
		isMenuOpen = false
		MenuFrame.Position = CLOSED_POS
		MenuFrame.Visible = false
		tweenBarOut()
		closeOverlay()
	end
end
