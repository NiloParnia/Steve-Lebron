-- DamageService.lua  (robust, block-aware, interrupt-aware, NodeSense telemetry)
-- Honors blocking for any blockable move (even when guard=0), parry,
-- I-frames, hyper-armor, and will INTERRUPT the defender's current attack
-- on successful HP damage (unless they have hyper-armor).
-- Optional: dmg.stun / dmg.hitstun / dmg.stagger (seconds) to apply StunService.

local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")

local CombatState        = require(RS:WaitForChild("CombatState"))
local GuardService       = require(RS:WaitForChild("GuardService"))
local IFrameStore        = require(RS:WaitForChild("IFrameStore"))
local ParryService       = require(RS:WaitForChild("ParryService"))
local NodeSense          = require(RS:WaitForChild("NodeSense"))
local AttackStateService = require(RS:WaitForChild("AttackStateService"))
local StunService        = require(RS:WaitForChild("StunService"))

local DamageService = {}

---------------------------------------------------------------------
-- DEBUG
---------------------------------------------------------------------
local DEBUG = false
local function dprint(...) if DEBUG then print("[DamageService]", ...) end end
local function dwarn(...)  if DEBUG then warn("[DamageService]", ...) end end

---------------------------------------------------------------------
-- UTIL
---------------------------------------------------------------------
local function asCharacter(entity)
	if not entity then return nil end
	if typeof(entity) == "Instance" then
		if entity:IsA("Player") then return entity.Character end
		if entity:IsA("Model") and entity:FindFirstChildOfClass("Humanoid") then return entity end
	elseif typeof(entity) == "table" and typeof(entity.Character) == "Instance" then
		return entity.Character
	end
	return nil
end

local function getHumanoid(target)
	if not target then return nil end
	if target:IsA("Player") then
		return target.Character and target.Character:FindFirstChildOfClass("Humanoid")
	elseif target:IsA("Model") then
		return target:FindFirstChildOfClass("Humanoid")
	end
end

local function getRoot(target)
	if not target then return nil end
	if target:IsA("Player") then
		return target.Character and target.Character:FindFirstChild("HumanoidRootPart")
	elseif target:IsA("Model") then
		return target:FindFirstChild("HumanoidRootPart")
	end
end

local function getUserId(entity)
	if not entity or typeof(entity) ~= "Instance" then return nil end
	if entity:IsA("Player") then return entity.UserId end
	if entity:IsA("Model") then
		local plr = Players:GetPlayerFromCharacter(entity)
		return plr and plr.UserId or nil
	end
	return nil
end

-- Accept a number or any table shape and normalize keys.
local function coerceDamageTable(dmg)
	if dmg == nil then return nil end
	-- number → hp
	if typeof(dmg) == "number" then
		return { hp = dmg, guard = 0, chip = 0, parryable = true, blockable = true, nodeName = "Unknown" }
	end
	if typeof(dmg) ~= "table" then
		dwarn("Bad dmg type:", typeof(dmg))
		return nil
	end

	-- accept many synonyms
	local hp    = dmg.hp or dmg.HP or dmg.health or dmg.Health or dmg.damage or dmg.Damage
	local guard = dmg.guard or dmg.Guard or dmg.guardDamage or dmg.GuardDamage
	local chip  = dmg.chip or dmg.Chip or dmg.chipDamage or dmg.ChipDamage
	local stun  = dmg.stun or dmg.hitstun or dmg.stagger or dmg.Stun or dmg.Hitstun or dmg.Stagger

	-- defaults
	hp    = tonumber(hp)    or 0
	guard = tonumber(guard) or 0
	chip  = tonumber(chip)  or 0
	stun  = tonumber(stun)  or 0

	-- parryable defaults to true unless explicitly false anywhere
	local p1 = dmg.parryable; local p2 = dmg.Parryable; local p3 = dmg.isParryable
	local parryable = not (p1 == false or p2 == false or p3 == false)

	-- blockable defaults to true unless explicitly false or "unblockable" is set
	local blockable = true
	if dmg.blockable == false or dmg.Blockable == false or dmg.unblockable == true or dmg.Unblockable == true then
		blockable = false
	end

	-- optional node name for telemetry
	local nodeName = dmg.nodeName or dmg.NodeName or dmg.name or dmg.Name or "Unknown"

	return {
		hp = hp, guard = guard, chip = chip, stun = stun,
		parryable = parryable,
		blockable = blockable,
		nodeName  = tostring(nodeName),
	}
end

---------------------------------------------------------------------
-- CORE
---------------------------------------------------------------------
local function dealDamageCore(defender, dmg, attacker)
	if not defender or not dmg then return end

	local nodeName   = dmg.nodeName or "Unknown"
	local defUserId  = getUserId(defender)

	-- hard blocks (emit Miss for telemetry/AI debug)
	if defender:GetAttribute("Invincible") then
		dprint("Ignored: Invincible:", defender.Name)
		NodeSense.EmitOutcome(attacker, nodeName, "Miss", { targetId = defUserId, reason = "Invincible" })
		return
	end
	if defender:IsA("Player") and IFrameStore.IsActive(defender) then
		dprint("Ignored: I-Frames active:", defender.Name)
		NodeSense.EmitOutcome(attacker, nodeName, "Miss", { targetId = defUserId, reason = "IFrame" })
		return
	end

	-- Parry check (only if parryable)
	if dmg.parryable and ParryService and type(ParryService.Try) == "function" then
		local ok, parried = pcall(ParryService.Try, attacker, defender)
		if ok and parried then
			dprint("Parried by", defender.Name, "against", nodeName)
			-- Interrupt the attacker if they don't have hyper-armor
			AttackStateService.Interrupt(attacker, "Parried")
			NodeSense.EmitOutcome(attacker, nodeName, "Parried", { targetId = defUserId })
			return
		end
	end

	-- Guard interaction (block cancels HP for blockable moves, even if guard=0)
	if dmg.blockable ~= false and GuardService.IsBlocking(defender) then
		local gd = tonumber(dmg.guard) or 0
		local state = GuardService.ApplyGuardDamage(attacker, defender, gd, nodeName)
		if state == "blocked" then
			-- fully blocked: no HP; note that *chip* is only applied on guard break below
			dprint("Blocked (no HP):", defender.Name)
			return
		elseif state == "break" then
			-- guard broke: fold chip into HP
			if dmg.chip and dmg.chip > 0 then
				dprint("Guard break → add chip:", dmg.chip, "→ HP", (dmg.hp or 0) + dmg.chip)
				dmg.hp = (dmg.hp or 0) + dmg.chip
			end
			-- GuardService already emitted "GuardBroken"
		end
	end

	-- HP application → Hit outcome
	if dmg.hp and dmg.hp > 0 then
		local hum = getHumanoid(defender)
		if hum then
			hum:TakeDamage(dmg.hp)
			dprint(("HP -%s → %s"):format(tostring(dmg.hp), hum.Parent and hum.Parent.Name or "Humanoid"))
			NodeSense.EmitOutcome(attacker, nodeName, "Hit", {
				targetId = defUserId,
				damage   = dmg.hp,
			})

			-- Interrupt defender's attack on hit (unless hyper-armor)
			AttackStateService.Interrupt(defender, "Hit")

			-- Optional hit-stun from the damage table (nodes may also call StunService directly)
			if dmg.stun and dmg.stun > 0 then
				StunService.Apply(defender, dmg.stun)
			end
		else
			dwarn("No Humanoid on target", defender.Name)
		end
	end
end

-- Public entry — canonical path
function DamageService.DealDamage(target, dmgIn, source)
	local norm = coerceDamageTable(dmgIn)
	dprint("▶ DealDamage", tostring(target and target.Name), norm and ("hp="..norm.hp.." guard="..norm.guard) or "<nil>")
	if not norm then return end
	dealDamageCore(target, norm, source)
end

-- Back-compat entry that some nodes may still call
function DamageService.Apply(target, dmgIn, source)
	local norm = coerceDamageTable(dmgIn)
	dprint("▶ Apply", tostring(target and target.Name), norm and ("hp="..norm.hp.." guard="..norm.guard) or "<nil>")
	if not norm then return end
	dealDamageCore(target, norm, source)
end

---------------------------------------------------------------------
-- BLOCK WRAPPERS
---------------------------------------------------------------------
function DamageService.StartBlock(p) GuardService.StartBlock(p) end
function DamageService.EndBlock(p)   GuardService.EndBlock(p)   end
function DamageService.BreakBlock(p) GuardService.Break(p)      end

---------------------------------------------------------------------
-- I-FRAMES
---------------------------------------------------------------------
function DamageService.IsIFraming(player) return IFrameStore.IsActive(player) end
function DamageService.GrantIFrames(player, duration) IFrameStore.Grant(player, duration) end

---------------------------------------------------------------------
-- AoE HELPERS
---------------------------------------------------------------------
function DamageService.AreaHit(origin, radius, damage, source)
	local oChar = asCharacter(origin); if not oChar then return {} end
	local oRoot = getRoot(oChar); if not oRoot then return {} end
	local hits = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		if typeof(origin) == "Instance" and origin:IsA("Player") and plr == origin then continue end
		local tChar = plr.Character
		local tRoot = getRoot(tChar)
		if tChar and tRoot and (tRoot.Position - oRoot.Position).Magnitude <= radius then
			DamageService.DealDamage(plr, damage, source or origin)
			table.insert(hits, plr)
		end
	end
	return hits
end

function DamageService.AreaHitCharacter(originChar, radius, damage, source)
	if not originChar then return {} end
	local oRoot = getRoot(originChar); if not oRoot then return {} end
	local hits = {}
	for _, mdl in ipairs(workspace:GetDescendants()) do
		if mdl:IsA("Model") and mdl ~= originChar and getHumanoid(mdl) then
			local tRoot = getRoot(mdl)
			if tRoot and (tRoot.Position - oRoot.Position).Magnitude <= radius then
				local asPlayer = Players:GetPlayerFromCharacter(mdl)
				DamageService.DealDamage(asPlayer or mdl, damage, source or originChar)
				table.insert(hits, asPlayer or mdl)
			end
		end
	end
	return hits
end

---------------------------------------------------------------------
-- TOUCH = HIT helper (one-shot)
---------------------------------------------------------------------
function DamageService.TouchHit(part, damageTable, source)
	if not part or not part:IsA("BasePart") then return end
	local fired = false
	part.Touched:Connect(function(other)
		if fired then return end
		local targetChar = other:FindFirstAncestorWhichIsA("Model")
		if not targetChar then return end
		local targetPlr  = Players:GetPlayerFromCharacter(targetChar)
		if source and targetPlr and targetPlr == source then return end -- don't self-hit
		fired = true
		DamageService.DealDamage(targetPlr or targetChar, damageTable, source)
		part:Destroy()
	end)
end

---------------------------------------------------------------------
-- Simple ray helper (optional)
---------------------------------------------------------------------
function DamageService.RayHit(attackerChar, lookVec, length, dmgTable, source)
	local root = attackerChar and attackerChar:FindFirstChild("HumanoidRootPart")
	if not root then return {} end
	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = { attackerChar }
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.RespectCanCollide = true

	local result = workspace:Raycast(root.Position, lookVec.Unit * length, rayParams)
	local hits = {}
	if result and result.Instance then
		local hitChar = result.Instance:FindFirstAncestorOfClass("Model")
		if hitChar and hitChar ~= attackerChar then
			table.insert(hits, hitChar)
			DamageService.DealDamage(hitChar, dmgTable, source or attackerChar)
		end
	end
	return hits
end

return DamageService
