--!strict
-- AnimDriver. Если Asset ID подключён, играет опубликованную R15-анимацию;
-- иначе запускает авторскую процедурную анимацию стойки, без внешних ассетов.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Moves = require(Shared:WaitForChild("Moves"))

local M = {}
M.ANIMATIONS = {
	jab = "", cross = "", hook_left = "", hook_right = "",
	uppercut_right = "", overhand_right = "", kick_low = "", kick_body = "",
	kick_head = "", block = "", slip = "", duck = "",
	knockdown = "", getup = "", idle = "",
}

-- Собственные позы в градусах: корпус начинает движение до удара,
-- переносит вес в момент контакта и возвращается в стойку на recovery.
local GUARD = {
	Waist = { 0, 0, 0 },
	RightShoulder = { -48, 0, 18 }, RightElbow = { -78, 0, 0 },
	LeftShoulder = { -48, 0, -18 }, LeftElbow = { -78, 0, 0 },
}
local PREP = {
	jab = { Waist = { 0, -8, 0 }, RightShoulder = { -38, 0, 25 } },
	cross = { Waist = { 0, -18, 0 }, LeftShoulder = { -34, 0, -25 } },
	hook_left = { Waist = { 0, -16, 0 }, RightShoulder = { -38, 0, 42 } },
	hook_right = { Waist = { 0, 16, 0 }, LeftShoulder = { -38, 0, -42 } },
	uppercut_right = { Waist = { -7, -12, 0 }, LeftShoulder = { -32, 0, -24 } },
	overhand_right = { Waist = { -12, -16, 0 }, LeftShoulder = { -25, 0, -30 } },
	kick_low = { Waist = { 5, -8, 0 }, RightHip = { -22, 0, 10 }, LeftHip = { 12, 0, 0 } },
	kick_body = { Waist = { 8, -12, 0 }, RightHip = { -30, 0, 12 }, LeftHip = { 15, 0, 0 } },
	kick_head = { Waist = { 12, -14, 0 }, RightHip = { -35, 0, 16 }, LeftHip = { 18, 0, 0 } },
	block = { RightShoulder = { -82, 0, 22 }, RightElbow = { -105, 0, 0 }, LeftShoulder = { -82, 0, -22 }, LeftElbow = { -105, 0, 0 } },
	slip = { Waist = { 0, 12, -12 }, Neck = { 0, -12, 8 } },
	duck = { Waist = { 24, 0, 0 }, RightHip = { -24, 0, 0 }, LeftHip = { -24, 0, 0 } },
}
local IMPACT = {
	jab = { Waist = { 0, 12, 0 }, RightShoulder = { -112, 0, 8 }, RightElbow = { -18, 0, 0 }, LeftShoulder = { -55, 0, -22 } },
	cross = { Waist = { 0, 27, 0 }, LeftShoulder = { -118, 0, -8 }, LeftElbow = { -15, 0, 0 }, RightShoulder = { -58, 0, 22 } },
	hook_left = { Waist = { 0, 28, 0 }, RightShoulder = { -92, 0, 68 }, RightElbow = { -68, 0, 0 } },
	hook_right = { Waist = { 0, -28, 0 }, LeftShoulder = { -92, 0, -68 }, LeftElbow = { -68, 0, 0 } },
	uppercut_right = { Waist = { -12, 20, 0 }, LeftShoulder = { -132, 0, -18 }, LeftElbow = { -48, 0, 0 } },
	overhand_right = { Waist = { -18, 30, 0 }, LeftShoulder = { -145, 0, -32 }, LeftElbow = { -38, 0, 0 } },
	kick_low = { Waist = { 8, 18, 0 }, RightHip = { -68, 0, 12 }, RightKnee = { -28, 0, 0 }, LeftHip = { 18, 0, 0 } },
	kick_body = { Waist = { 14, 20, 0 }, RightHip = { -82, 0, 18 }, RightKnee = { -18, 0, 0 }, LeftHip = { 22, 0, 0 } },
	kick_head = { Waist = { 18, 22, 0 }, RightHip = { -100, 0, 22 }, RightKnee = { -12, 0, 0 }, LeftHip = { 25, 0, 0 } },
	block = PREP.block,
	slip = { Waist = { 0, -18, -22 }, Neck = { 0, 18, 12 } },
	duck = { Waist = { 32, 0, 0 }, RightHip = { -38, 0, 0 }, LeftHip = { -38, 0, 0 } },
}

local cache: { [string]: Animation } = {}
local tracks: { [string]: AnimationTrack } = {}
local joints: { [string]: Motor6D } = {}
local currentTrack: AnimationTrack? = nil
local currentId: string? = nil
local elapsed = 0
local speedMultiplier = 1
local duration = 0
local procedural = false

local function clearPose()
	for _, joint in pairs(joints) do
		joint.Transform = CFrame.identity
	end
end

local function invalidate()
	if currentTrack then currentTrack:Stop(0) end
	tracks = {}
	cache = {}
	joints = {}
	currentTrack = nil
	currentId = nil
	procedural = false
	elapsed = 0
end

local function refreshJoints()
	joints = {}
	local character = Players.LocalPlayer.Character
	if not character then return end
	for _, item in ipairs(character:GetDescendants()) do
		if item:IsA("Motor6D") then joints[item.Name] = item end
	end
end

local function toCFrame(rotation: { number }): CFrame
	return CFrame.Angles(math.rad(rotation[1]), math.rad(rotation[2]), math.rad(rotation[3]))
end

local function blendPose(a: { [string]: { number } }, b: { [string]: { number } }, alpha: number): { [string]: { number } }
	local result = {}
	for name, base in pairs(a) do
		local target = b[name] or base
		result[name] = {
			base[1] + (target[1] - base[1]) * alpha,
			base[2] + (target[2] - base[2]) * alpha,
			base[3] + (target[3] - base[3]) * alpha,
		}
	end
	for name, target in pairs(b) do
		if not result[name] then result[name] = target end
	end
	return result
end

local function applyProceduralPose(dt: number)
	if not procedural or not currentId then return end
	local move = Moves.get(currentId)
	if not move then return end
	elapsed += dt * speedMultiplier
	local frame = elapsed * 60
	local startup = move.timing.startup
	local activeEnd = startup + move.timing.active
	local total = startup + move.timing.active + move.timing.recovery
	if currentId == "block" then total = startup + move.timing.active end
	local prep = PREP[currentId] or GUARD
	local impact = IMPACT[currentId] or GUARD
	local pose
	if currentId == "block" and frame >= startup then
		pose = impact
	elseif frame < startup * 0.72 then
		pose = blendPose(GUARD, prep, math.clamp(frame / math.max(1, startup * 0.72), 0, 1))
	elseif frame < activeEnd then
		pose = blendPose(prep, impact, math.clamp((frame - startup * 0.72) / math.max(1, startup * 0.28 + move.timing.active), 0, 1))
	elseif currentId == "block" then
		pose = impact
	elseif frame < total then
		local recoveryStart = activeEnd
		local alpha = math.clamp((frame - recoveryStart) / math.max(1, total - recoveryStart), 0, 1)
		pose = blendPose(impact, GUARD, alpha)
	else
		clearPose()
		procedural = false
		currentId = nil
		return
	end
	for name, joint in pairs(joints) do
		local rotation = pose[name]
		joint.Transform = rotation and toCFrame(rotation) or CFrame.identity
	end
end

local function getTrack(id: string): AnimationTrack?
	if tracks[id] then return tracks[id] end
	local assetId = M.ANIMATIONS[id]
	if not assetId or assetId == "" then return nil end
	local anim = cache[id]
	if not anim then
		anim = Instance.new("Animation")
		anim.AnimationId = assetId
		cache[id] = anim
	end
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return nil end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	local track = animator:LoadAnimation(anim)
	track.Priority = Enum.AnimationPriority.Action
	tracks[id] = track
	return track
end

function M.start()
	Players.LocalPlayer.CharacterAdded:Connect(function()
		invalidate()
		task.defer(refreshJoints)
	end)
	if Players.LocalPlayer.Character then refreshJoints() end
	RunService.PreSimulation:Connect(applyProceduralPose)
end

function M.reportMissing()
	local missing = {}
	for id, assetId in pairs(M.ANIMATIONS) do
		if assetId == "" then table.insert(missing, id) end
	end
	table.sort(missing)
	if #missing == 0 then
		print("[AnimDriver] все анимации подключены")
	else
		print("[AnimDriver] не подключено (" .. tostring(#missing) .. "): " .. table.concat(missing, ", "))
		print("[AnimDriver] для пустых ID включены встроенные авторские процедурные позы")
	end
end

function M.play(id: string, speed: number?)
	clearPose()
	if currentTrack then currentTrack:Stop(0.06) end
	currentId = id
	elapsed = 0
	local track = getTrack(id)
	if track then
		procedural = false
		track:Play(0.06, 1, speed or 1)
		currentTrack = track
		return
	end
	currentTrack = nil
	procedural = true
	local move = Moves.get(id)
	if move then duration = (move.timing.startup + move.timing.active + move.timing.recovery) / 60 end
end

function M.stop(fadeTime: number?)
	if currentTrack then currentTrack:Stop(fadeTime or 0.1) end
	currentTrack = nil
	currentId = nil
	procedural = false
	clearPose()
end

function M.current(): string?
	return currentId
end

function M.setSpeedMultiplier(multiplier: number)
	speedMultiplier = multiplier
	if currentTrack then currentTrack:AdjustSpeed(multiplier) end
end

return M
