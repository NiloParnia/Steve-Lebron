-- ServerScriptService/HorseService.lua
-- Robust horse spawner/manager. Finds RS.Horses.Default, parents into Workspace.Horses,
-- tags with attributes, auto-mounts, and logs loudly if anything goes wrong.

local Players   = game:GetService("Players")
local RS        = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local HorseService = {}
local ACTIVE = {} -- [Player] = Model

local DEBUG = true
local HORSES_FOLDER_NAME = "Horses" -- live horses go under Workspace/Horses

local function log(...) if DEBUG then print("[HorseService]", ...) end end

-- Workspace/Horses container (many firewalls whitelist folders)
local function getOrCreateHorsesFolder()
	local f = Workspace:FindFirstChild(HORSES_FOLDER_NAME)
	if not f then
		f = Instance.new("Folder")
		f.Name = HORSES_FOLDER_NAME
		f.Parent = Workspace
		log("Created Workspace." .. HORSES_FOLDER_NAME)
	end
	return f
end

-- Preferred template locations:
-- 1) ReplicatedStorage/Horses/Default
-- 2) ReplicatedStorage/Default
-- 3) ReplicatedStorage/HorseTemplate
-- 4) Any descendant with IsHorseTemplate=true
-- 5) Any descendant named "Default"
local function findTemplate()
	local horses = RS:FindFirstChild("Horses")
	if horses and horses:IsA("Folder") then
		local d = horses:FindFirstChild("Default")
		if d and d:IsA("Model") then log("Using template:", d:GetFullName()); return d end
	end

	do
		local d = RS:FindFirstChild("Default")
		if d and d:IsA("Model") then log("Using template:", d:GetFullName()); return d end
	end

	do
		local t = RS:FindFirstChild("HorseTemplate")
		if t and t:IsA("Model") then log("Using template:", t:GetFullName()); return t end
	end

	for _, m in ipairs(RS:GetDescendants()) do
		if m:IsA("Model") and m:GetAttribute("IsHorseTemplate") == true then
			log("Using attributed template:", m:GetFullName())
			return m
		end
	end

	for _, m in ipairs(RS:GetDescendants()) do
		if m:IsA("Model") and m.Name == "Default" then
			log("Using fallback 'Default':", m:GetFullName())
			return m
		end
	end

	warn("[HorseService] No horse template found. Put a Model at ReplicatedStorage/Horses/Default.")
	return nil
end

local function ensureSeat(m)
	-- Prefer a seat already named SaddleSeat; else rename first Seat found
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("Seat") and d.Name == "SaddleSeat" then return d end
	end
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("Seat") then d.Name = "SaddleSeat"; return d end
	end
	warn("[HorseService] No Seat found; mounting will fail.")
	return nil
end

local function ensureHumanoid(m)
	local hum = m:FindFirstChildOfClass("Humanoid")
	if not hum then hum = Instance.new("Humanoid", m) end
	hum.AutoRotate = false
	hum.UseJumpPower = true
	return hum
end

local function setPrimaryPartIfPossible(m)
	if m.PrimaryPart and m.PrimaryPart:IsA("BasePart") then return m.PrimaryPart end
	local hrp = m:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then m.PrimaryPart = hrp; return hrp end
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then m.PrimaryPart = d; return d end
	end
	return nil
end

function HorseService.GetActive(p)
	local m = ACTIVE[p]
	if m and m.Parent then return m end
	return nil
end

function HorseService.GetHorseName(p)
	local m = HorseService.GetActive(p)
	return (m and (m:GetAttribute("HorseName") or m.Name)) or "Horse"
end

function HorseService.Despawn(p)
	local m = ACTIVE[p]
	ACTIVE[p] = nil
	if m and m.Parent then m:Destroy() end
end

function HorseService.SummonTo(p, cf, autoMount)
	-- Derive a CFrame if not provided
	if not cf then
		local char = p and p.Character
		local r = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
		cf = r and r.CFrame or CFrame.new(0, 8, 0)
	end

	local template = findTemplate()
	if not template then return nil end

	-- Replace any existing horse
	if HorseService.GetActive(p) then HorseService.Despawn(p) end

	local h = template:Clone()
	h.Name = template.Name

	-- Attributes for guards/mount code
	h:SetAttribute("IsHorse", true)         -- HorseMountServer uses this
	h:SetAttribute("IsMount", true)         -- generic mount tag
	h:SetAttribute("OwnerUserId", p.UserId) -- for any ownership filters
	h:SetAttribute("BaseSpeed", 32)
	h:SetAttribute("HorseJumpPower", 30)
	h:SetAttribute("HorseJumpImpulse", 60)
	h:SetAttribute("SurfaceYawOffsetDeg", -90) -- your rig prefers Left

	-- Parent into Workspace/Horses (safer than Workspace root)
	local stable = getOrCreateHorsesFolder()
	h.Parent = stable

	-- Position (Model:PivotTo works without PrimaryPart)
	local okPivot, errPivot = pcall(function() h:PivotTo(cf) end)
	if not okPivot then warn("[HorseService] PivotTo error:", errPivot) end

	-- Unanchor all parts (some templates are saved anchored)
	local partCount = 0
	for _, d in ipairs(h:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
			partCount += 1
		end
	end

	local seat = ensureSeat(h)
	local hum  = ensureHumanoid(h)
	local pp   = setPrimaryPartIfPossible(h)
	if pp then pcall(function() pp:SetNetworkOwner(nil) end) end

	ACTIVE[p] = h
	log(("Spawned horse for %s → %s"):format(p.Name, h:GetFullName()))

	-- Auto-mount after physics settle
	if autoMount ~= false and seat and seat:IsA("Seat") then
		local char = p.Character
		local riderHum = char and char:FindFirstChildOfClass("Humanoid")
		if riderHum then
			task.defer(function()
				local ok, err = pcall(function() seat:Sit(riderHum) end)
				if not ok then warn("[HorseService] seat:Sit error:", err) end
			end)
		end
	end

	-- If something deletes it right away, complain loudly
	task.delay(0.2, function()
		if not h.Parent then
			warn("[HorseService] Horse destroyed immediately after spawn (firewall?). Whitelist Workspace."..HORSES_FOLDER_NAME..".")
		end
	end)

	-- Keep ACTIVE clean
	h.AncestryChanged:Connect(function(_, parent)
		if parent == nil and ACTIVE[p] == h then ACTIVE[p] = nil end
	end)

	return h
end

Players.PlayerRemoving:Connect(function(p)
	HorseService.Despawn(p)
	ACTIVE[p] = nil
end)

return HorseService
