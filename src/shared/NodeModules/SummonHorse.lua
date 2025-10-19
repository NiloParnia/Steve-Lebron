-- ReplicatedStorage/NodeModules/SummonHorse.lua
-- Toggle summon/dismiss, unlock + cooldown gated.

local RS  = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")

local CooldownService = require(RS:WaitForChild("CooldownService"))
local HS  = require(SSS:WaitForChild("HorseService"))

local Remotes        = RS:WaitForChild("RemoteEvents")
local ConfirmSuccess = Remotes:FindFirstChild("ConfirmSuccess")
local CooldownNotice = Remotes:FindFirstChild("CooldownNotice")

local NODE_NAME   = "SummonHorse"
local COOLDOWN_S  = 10
local LEFT_OFFSET = 5
local UNLOCK_ATTR = "HasHorse" -- only blocks if explicitly false

local function toast(p, msg)
	if ConfirmSuccess then ConfirmSuccess:FireClient(p, { ok = true, msg = msg }) end
end

local function pushCD(p)
	if CooldownNotice then
		CooldownNotice:FireClient(p, { name = NODE_NAME, duration = COOLDOWN_S, started = os.clock() })
	end
end

local M = { Name = NODE_NAME }

function M.OnStart(player, dirVec)
	-- unlock gate: if attr missing -> allow; if false -> block
	if player:GetAttribute(UNLOCK_ATTR) == false then
		toast(player, "You haven't unlocked your horse yet.")
		return false
	end

	-- cooldown gate
	if not CooldownService.CanUse(player, NODE_NAME) then return false end
	CooldownService.Apply(player, NODE_NAME, COOLDOWN_S)
	pushCD(player)

	local char = player.Character
	local hrp  = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end

	local active = HS.GetActive and HS.GetActive(player)
	if active then
		HS.Despawn(player)
		toast(player, "Dismissed your horse.")
		return true
	else
		local cf = hrp.CFrame * CFrame.new(-LEFT_OFFSET, 0, 0)
		local horse = HS.SummonTo(player, cf)
		if horse then toast(player, "Summoned your horse.") end
		return horse ~= nil
	end
end

return M
