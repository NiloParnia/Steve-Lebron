-- 00_MountedFirewall.server.lua
-- Global, future-proof block for actions while mounted.
-- Patches NodeFactory.Create and DamageService.DealDamage at runtime.
-- Hardened to accept attacker as Player/Model/Humanoid/BasePart or table context.

local RS      = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- ===== CONFIG =====
local DEBUG = false
local function dprint(...) if DEBUG then print("[MountedFirewall]", ...) end end

-- Nodes allowed while mounted (e.g., emotes)
local ALLOW_WHILE_MOUNTED: {[string]: boolean} = {
	-- ["WaveEmote"] = true,
}

-- ---------- Helpers ----------
local function characterFromInstance(inst: Instance?)
	if not inst then return nil end
	if inst:IsA("Model") then return inst end
	if inst:IsA("Humanoid") then return inst.Parent end
	if inst:IsA("BasePart") then return inst:FindFirstAncestorOfClass("Model") end
	return nil
end

local function playerFromAnything(x): Player?
	if typeof(x) == "Instance" then
		if x:IsA("Player") then return x end
		local char = characterFromInstance(x)
		if char then return Players:GetPlayerFromCharacter(char) end
	elseif typeof(x) == "table" then
		-- Common table fields we might see from services
		local pCands = { x.player, x.Player, x.AttackerPlayer, x.Owner, x.SourcePlayer, x.Source }
		for _, p in ipairs(pCands) do
			if typeof(p) == "Instance" and p:IsA("Player") then return p end
		end
		local cCands = { x.Character, x.char, x.AttackerChar, x.AttackerCharacter, x.SourceCharacter, x.SourceChar, x.CharacterModel, x.Model, x.RootPart }
		for _, c in ipairs(cCands) do
			if typeof(c) == "Instance" then
				if c:IsA("Player") then return c end
				local char = characterFromInstance(c) or (c:IsA("Model") and c or nil)
				if char then
					local plr = Players:GetPlayerFromCharacter(char)
					if plr then return plr end
				end
			end
		end
	end
	return nil
end

local function characterFromAnything(x): Model?
	if typeof(x) == "Instance" then
		return characterFromInstance(x)
	elseif typeof(x) == "table" then
		local cCands = { x.Character, x.char, x.AttackerChar, x.AttackerCharacter, x.SourceCharacter, x.SourceChar, x.CharacterModel, x.Model, x.RootPart }
		for _, c in ipairs(cCands) do
			if typeof(c) == "Instance" then
				local ch = characterFromInstance(c) or (c:IsA("Model") and c or nil)
				if ch then return ch end
			end
		end
	end
	return nil
end

local function isMountedPlayer(plr: Player?): boolean
	if not plr then return false end
	local hum = plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")
	return hum and hum:GetAttribute("Mounted") == true
end

local function isMountedAnything(x): boolean
	local plr = playerFromAnything(x)
	if plr then return isMountedPlayer(plr) end
	local char = characterFromAnything(x)
	if not char then return false end
	local hum = char:FindFirstChildOfClass("Humanoid")
	return hum and hum:GetAttribute("Mounted") == true
end

-- ---------- Patch NodeFactory.Create (guards every node function) ----------
local NodeFactory = require(RS:WaitForChild("NodeFactory"))

do
	local __wrappedCache = setmetatable({}, { __mode = "k" })
	local __fnCache      = setmetatable({}, { __mode = "k" })

	local function guardFunc(nodeTbl, key, fn)
		local nodeFns = __fnCache[nodeTbl]; if not nodeFns then nodeFns = {}; __fnCache[nodeTbl] = nodeFns end
		if nodeFns[key] then return nodeFns[key] end

		local wrapped = function(...)
			-- Resolve caller from either form:
			--   node.OnStart(player, dir) OR node.Execute(player, dir)
			--   node:Execute(rootPart, extra)
			local a1, a2 = ...
			local plr = playerFromAnything(a1) or playerFromAnything(a2)
			local name = tostring(nodeTbl.Name or key or "?")
			local allowed = ALLOW_WHILE_MOUNTED[name] or nodeTbl.AllowWhileMounted

			if plr and (not allowed) and isMountedPlayer(plr) then
				dprint(("BLOCK node=%s fn=%s while mounted"):format(name, key))
				return
			end
			return fn(...)
		end
		nodeFns[key] = wrapped
		return wrapped
	end

	local function wrapNode(nodeTbl)
		if type(nodeTbl) ~= "table" then return nodeTbl end
		if __wrappedCache[nodeTbl] then return __wrappedCache[nodeTbl] end

		local proxy = setmetatable({}, {
			__index = function(_, k)
				local v = nodeTbl[k]
				if type(v) == "function" then
					return guardFunc(nodeTbl, k, v)
				else
					return v
				end
			end,
			__newindex = function(_, k, v) nodeTbl[k] = v end,
			__pairs = function() return pairs(nodeTbl) end,
			__ipairs = function() return ipairs(nodeTbl) end,
		})
		__wrappedCache[nodeTbl] = proxy
		return proxy
	end

	if type(NodeFactory) == "table" and type(NodeFactory.Create) == "function" then
		local oldCreate = NodeFactory.Create
		NodeFactory.Create = function(cfg)
			local raw = oldCreate(cfg)
			return wrapNode(raw)
		end
		dprint("Patched NodeFactory.Create")
	else
		warn("[MountedFirewall] NodeFactory.Create not found; cannot patch")
	end
end

-- ---------- Patch DamageService.DealDamage (belt-and-suspenders) ----------
do
	local ok, DamageService = pcall(function() return require(RS:WaitForChild("DamageService")) end)
	if ok and type(DamageService) == "table" and type(DamageService.DealDamage) == "function" then
		local old = DamageService.DealDamage
		DamageService.DealDamage = function(targetChar, dmg, attacker, ...)
			if isMountedAnything(attacker) then
				dprint("BLOCK damage while mounted")
				return
			end
			return old(targetChar, dmg, attacker, ...)
		end
		dprint("Patched DamageService.DealDamage")
	else
		warn("[MountedFirewall] Could not patch DamageService.DealDamage")
	end
end