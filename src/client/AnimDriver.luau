--!strict
-- AnimDriver: маппинг "id приёма -> Roblox Animation" (тестовая сборка).
-- Сюда вставляешь assetId анимаций: 12 приёмов стойки + knockdown/getup/idle.
-- Без анимаций игра работает: логика считает кадры по data/moves.json,
-- просто не будет визуала замахов.
--
-- Ретаргет: BVH/FBX -> Blender (armature = R15-скелет) -> экспорт FBX ->
-- Roblox Studio Animation Editor -> Publish to Roblox -> assetId.

local Players = game:GetService("Players")

local M = {}

M.ANIMATION_COUNT = 15

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
	block = "",
	slip = "",
	duck = "",
	knockdown = "",
	getup = "",
	idle = "",
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
	track.Priority = Enum.AnimationPriority.Action
	tracks[id] = track
	return track
end

-- Кэш треков инвалидируется при респавне: треки старого персонажа мертвы
local function invalidate()
	tracks = {}
	cache = {}
	animator = nil
	currentTrack = nil
	currentId = nil
end

function M.start()
	Players.LocalPlayer.CharacterAdded:Connect(function()
		invalidate()
	end)
end

-- Печатает в Output, какие анимации не подключены
function M.reportMissing()
	local missing = {}
	for id, assetId in pairs(M.ANIMATIONS) do
		if assetId == "" then
			table.insert(missing, id)
		end
	end
	table.sort(missing)
	if #missing == 0 then
		print("[AnimDriver] все анимации подключены")
		return
	end
	print("[AnimDriver] не подключено (" .. tostring(#missing) .. "): " .. table.concat(missing, ", "))
	print("[AnimDriver] без анимаций игра работает - логика считает кадры по data/moves.json")
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
