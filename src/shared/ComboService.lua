local ComboService = {}

---------------------------------------------------------------------
-- ComboService
-- Tracks consecutive light-attack hits and triggers a finisher.
-- Works for both Players and NPC Models.
---------------------------------------------------------------------

------------------------------ SERVICES
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DamageService     = require(ReplicatedStorage:WaitForChild("DamageService"))
local KnockbackService  = require(ReplicatedStorage:WaitForChild("KnockbackService"))
local StunService       = require(ReplicatedStorage:WaitForChild("StunService"))
local CooldownService   = require(ReplicatedStorage:WaitForChild("CooldownService"))

------------------------------ REMOTES (optional FX / UI hooks)
local RemoteEvents      = ReplicatedStorage:WaitForChild("RemoteEvents")
local ComboBurst        = RemoteEvents:FindFirstChild("ComboBurst") -- may be nil

------------------------------ TUNING
local COMBO_RESET        = 3.0   -- seconds before combo times out
local HIT_MAX            = 5     -- # of M1 hits before finisher
local FINISHER_RADIUS    = 7     -- damage radius
local KB_RADIUS          = 6     -- knockback/stagger radius

-- New: brief recovery after a finisher (locks common actions)
local FINISHER_RECOVERY_SEC = 1.0
local FINISHER_LOCK_MOVES   = { "Punch", "Heavy", "Dodge", "BlockStart" }

-- Legacy: specific punch cooldown (kept; harmless if duplicated with recovery)
local FINISHER_PUNCH_CD  = 3.0

local FINISHER_DMG       = { guard = 0, hp = 6.6, chip = 0, nodeName = "ComboFinisher" }
local KB_FORCE           = 90
local KB_DUR             = 0.25
local FINISHER_STUN      = 0.3   -- mild stagger after burst

------------------------------ STATE
local comboCount  = {}    -- [attacker(Player|Model)] = hits
local lastHitTime = {}    -- [attacker] = tick()

------------------------------ HELPERS
local function asModel(ent)
	if typeof(ent) ~= "Instance" then return nil end
	if ent:IsA("Player") then return ent.Character end
	if ent:IsA("Model") then return ent end
	return nil
end

local function rootOf(ent)
	local mdl = asModel(ent)
	return mdl and mdl:FindFirstChild("HumanoidRootPart") or nil
end

local function isPlayer(ent)
	return typeof(ent) == "Instance" and ent:IsA("Player")
end

local function iterTargetsAround(origin, radius)
	local oModel = asModel(origin)
	local oRoot  = rootOf(origin)
	if not oModel or not oRoot then return {} end

	local found = {}
	local seen  = {}  -- dedupe by model instance

	for _, inst in ipairs(workspace:GetDescendants()) do
		if inst:IsA("Humanoid") then
			local mdl = inst.Parent
			if mdl and mdl:IsA("Model") and mdl ~= oModel then
				local hrp = mdl:FindFirstChild("HumanoidRootPart")
				if hrp and (hrp.Position - oRoot.Position).Magnitude <= radius then
					if not seen[mdl] then
						seen[mdl] = true
						local plr = Players:GetPlayerFromCharacter(mdl)
						table.insert(found, plr or mdl)
					end
				end
			end
		end
	end

	return found
end

------------------------------ API
function ComboService.RegisterHit(attacker)
	local now = tick()

	if (lastHitTime[attacker] or 0) + COMBO_RESET < now then
		comboCount[attacker] = 0
	end

	comboCount[attacker] = (comboCount[attacker] or 0) + 1
	lastHitTime[attacker] = now

	if comboCount[attacker] >= HIT_MAX then
		ComboService.Finish(attacker)
	end
end

function ComboService.Finish(attacker)
	comboCount[attacker]  = 0
	lastHitTime[attacker] = tick()

	local oModel = asModel(attacker)
	local oRoot  = rootOf(attacker)
	if not oModel or not oRoot then return end

	-- Brief recovery: lock common actions for 1s (players & NPCs)
	for _, key in ipairs(FINISHER_LOCK_MOVES) do
		pcall(CooldownService.Apply, attacker, key, FINISHER_RECOVERY_SEC)
	end

	-- Keep specific punch cooldown (no harm if redundant)
	if isPlayer(attacker) then
		CooldownService.Apply(attacker, "Punch", FINISHER_PUNCH_CD)
	end

	-- Finisher damage (respects Guard/Parry/I-frames/Hyper-Armor)
	for _, tgt in ipairs(iterTargetsAround(attacker, FINISHER_RADIUS)) do
		DamageService.DealDamage(tgt, FINISHER_DMG, attacker)
	end

	-- Knockback + brief stagger
	for _, tgt in ipairs(iterTargetsAround(attacker, KB_RADIUS)) do
		local tRoot = rootOf(tgt)
		if tRoot then
			local dir = (tRoot.Position - oRoot.Position)
			KnockbackService.Apply(tgt, dir, KB_FORCE, KB_DUR)
			StunService.Apply(tgt, FINISHER_STUN)
		end
	end

	-- Optional FX
	if ComboBurst then
		local plr = isPlayer(attacker) and attacker or nil
		if plr then
			ComboBurst:FireAllClients(plr)
		else
			ComboBurst:FireAllClients()
		end
	end
end

function ComboService.GetCount(attacker)
	return comboCount[attacker] or 0
end

function ComboService.Reset(attacker)
	comboCount[attacker]  = 0
	lastHitTime[attacker] = nil
end

return ComboService
