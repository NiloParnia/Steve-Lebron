-- ReplicatedStorage/NodeModules/Gallop.lua
-- Hidden passive unlock used as a durable flag via PlayerDataService.
-- Not clickable, not on hotbar; just marks that the player owns Gallop.
local M = {
	Name = "Gallop",
	Passive = true,
	Hidden = true,          -- NodeManager should ignore it in UI
	AllowWhileMounted = true,
}
function M.OnStart(player)
	-- No direct activation; server HorseMountServer handles it.
	return false
end
return M
