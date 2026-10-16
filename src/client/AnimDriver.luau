--!strict
-- AnimDriver: маппинг "id приёма -> Roblox Animation".
-- Сюда вставляешь assetId анимаций, которые сделал в Blender / купил /
-- сгенерировал через Move.ai-Rokoko и ретаргетнул на R15.
--
-- Ретаргет: BVH/FBX -> Blender (armature = R15-скелет) -> экспорт FBX ->
-- Roblox Studio Animation Editor -> Publish to Roblox -> assetId.

local Players = game:GetService("Players")

local M = {}

-- ЗАПОЛНИ СВОИМИ assetId. Пустая строка = анимация не подключена.
M.ANIMATIONS = {
	jab = "",
	cross = "",
	hook_left = "",
	hook_right = "",
	uppercut_right = "",
	overhand_right = "",
	kick_low = "",
	kick_body = "",
	kick_head = "",
	spinning_back_kick = "",
	knee_clinch = "",
	elbow_clinch = "",
	superman_punch = "",
	block = "",
	slip = "",
	duck = "",
	double_leg = "",
	single_leg = "",
	clinch_trip = "",
	ground_pound_top = "",
	ground_punch_bottom = "",
	escape_guard = "",
	armbar_guard = "",
	transition_mount = "",
	rnc_attempt = "",
	knockdown = "",
	getup = "",
	idle = "",
	walk_fwd = "",
	walk_back = "",
}

local cache: { [string]: Animation } = {}
local tracks: { [string]: AnimationTrack } = {}
local animator: Animator? = nil
local currentTrack: AnimationTrack? = nil
local currentId: string? = nil

local function getAnimator(): Animator?
	local character = Players.LocalPlayer.Character
	if not character then
		return nil
	end
	local hum = character:FindFirstChildOfClass("Humanoid")
	if not hum then
		return nil
	end
	animator = hum:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = hum
	end
	return animator
end

local function getTrack(id: string): AnimationTrack?
	if tracks[id] then
		return tracks[id]
	end
	local assetId = M.ANIMATIONS[id]
	if not assetId or assetId == "" then
		return nil
	end
	local anim = cache[id]
	if not anim then
		anim = Instance.new("Animation")
		anim.AnimationId = assetId
		cache[id] = anim
	end
	local an = getAnimator()
	if not an then
		return nil
	end
	local track = an:LoadAnimation(anim)
	tracks[id] = track
	return track
end

function M.play(id: string, speed: number?)
	local track = getTrack(id)
	if not track then
		return
	end
	if currentTrack and currentTrack ~= track then
		currentTrack:Stop(0.1)
	end
	track:Play(0.08, 1, speed or 1)
	currentTrack = track
	currentId = id
end

function M.stop(fadeTime: number?)
	if currentTrack then
		currentTrack:Stop(fadeTime or 0.12)
		currentTrack = nil
		currentId = nil
	end
end

function M.current(): string?
	return currentId
end

-- Скорость анимации должна совпадать со скоростью симуляции!
-- Иначе кадры мува и кадры анимации разъедутся - это главный баг самодельных файтингов.
function M.setSpeedMultiplier(multiplier: number)
	if currentTrack then
		currentTrack:AdjustSpeed(multiplier)
	end
end

return M
