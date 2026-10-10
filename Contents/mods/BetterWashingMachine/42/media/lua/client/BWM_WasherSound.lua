BWM = BWM or {}

local REGISTRY_KEY = "BWM_ActiveWashers"
local RUNNING = "ClothingWasherRunning"
local FINISHED = "ClothingWasherFinished"

local playing = {}

local function key(x, y, z)
    return x .. "," .. y .. "," .. z
end

local function stopLoop(k)
    local entry = playing[k]
    if not entry then return end
    pcall(function() entry.emitter:stopSound(entry.handle) end)
    pcall(function() entry.emitter:stopAll() end)
    playing[k] = nil
end

local function startLoop(x, y, z)
    local k = key(x, y, z)
    if playing[k] then return end
    local ok, err = pcall(function()
        local emitter = getWorld():getFreeEmitter(x + 0.5, y + 0.5, z)
        local handle = emitter:playSoundLooped(RUNNING)
        emitter:tick()
        playing[k] = { emitter = emitter, handle = handle }
    end)
    if not ok then print("[BWM][Sound] start failed: " .. tostring(err)) end
end

local FINISHED_MAX_MS = 2500
local finishing = {}

local function stopFinished(entry)
    pcall(function() entry.emitter:stopSound(entry.handle) end)
    pcall(function() entry.emitter:stopAll() end)
end

-- The Finished FMOD event repeats on its own, so it is cut after a short time.
local function onFinishedTick()
    local now = getTimestampMs()
    for i = #finishing, 1, -1 do
        local entry = finishing[i]
        if now >= entry.stopAt then
            stopFinished(entry)
            table.remove(finishing, i)
        end
    end
    if #finishing == 0 then Events.OnTick.Remove(onFinishedTick) end
end

local function playFinished(x, y, z)
    local ok, err = pcall(function()
        local emitter = getWorld():getFreeEmitter(x + 0.5, y + 0.5, z)
        local handle = emitter:playSound(FINISHED)
        emitter:tick()
        if #finishing == 0 then Events.OnTick.Add(onFinishedTick) end
        finishing[#finishing + 1] = { emitter = emitter, handle = handle, stopAt = getTimestampMs() + FINISHED_MAX_MS }
    end)
    if not ok then print("[BWM][Sound] finished failed: " .. tostring(err)) end
end

function BWM.onSoundEvent(args)
    local k = key(args.x, args.y, args.z)
    if args.state == "start" then
        startLoop(args.x, args.y, args.z)
    else
        stopLoop(k)
        if args.state == "finish" then playFinished(args.x, args.y, args.z) end
    end
end

Events.OnServerCommand.Add(function(module, command, args)
    if module == "BWM" and command == "sound" then
        BWM.onSoundEvent(args)
    end
end)

-- Resumes the loop after loading a save (single player / host, where the registry is local).
local function reconcile()
    local registry = ModData.getOrCreate(REGISTRY_KEY)
    for _, entry in pairs(registry) do
        local k = key(entry.x, entry.y, entry.z)
        local square = getCell():getGridSquare(entry.x, entry.y, entry.z)
        if square and not playing[k] then
            startLoop(entry.x, entry.y, entry.z)
        end
    end
    for k in pairs(playing) do
        if not registry[k] then stopLoop(k) end
    end
end

Events.OnGameStart.Add(reconcile)
Events.EveryOneMinute.Add(reconcile)
