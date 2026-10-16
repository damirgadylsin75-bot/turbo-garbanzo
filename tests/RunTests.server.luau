--!strict
-- Запуск тестов TestEZ в Studio.
-- Установи TestEZ (https://github.com/Roblox/testez) в ReplicatedStorage.TestEZ,
-- затем нажми Play в месте, где есть этот скрипт (или встави его в Studio вручную).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local ok, TestEZ = pcall(function()
	return require(ReplicatedStorage:WaitForChild("TestEZ", 5))
end)

if not ok or not TestEZ then
	warn("[tests] TestEZ не найден в ReplicatedStorage.TestEZ — установи его, чтобы гонять тесты")
	return
end

local Tests = ServerStorage:WaitForChild("Tests")

local results = TestEZ.TestBootstrap:run(
	{ Tests },
	TestEZ.Reporters.TextReporterQuiet
)

if results.failureCount > 0 then
	error(string.format("[tests] провалов: %d", results.failureCount))
else
	print(string.format("[tests] зелёные, проверено %d", results.successCount))
end
