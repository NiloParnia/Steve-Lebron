-- Assumes 'char' is the character model passed into the function
local function DashAndAnimate(char)
    local hum = char:FindFirstChildOfClass("Humanoid")
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hum or not hrp then return end

    -- Load Animation (use Animator for R15 and future compatibility)
    local animator = hum:FindFirstChildOfClass("Animator")
    if not animator then
        animator = Instance.new("Animator")
        animator.Parent = hum
    end
    local anim = Instance.new("Animation")
    anim.AnimationId = "rbxassetid://110397380149359"
    local track = animator:LoadAnimation(anim)
    track:Play()

    -- Dash movement burst (use AssemblyLinearVelocity for physics consistency)
    local dodgeForce = 50
    local moveDir = hum.MoveDirection
    if moveDir.Magnitude > 0 then
        hrp.AssemblyLinearVelocity = moveDir.Unit * dodgeForce
    end
end

return {
    DashAndAnimate = DashAndAnimate
}

