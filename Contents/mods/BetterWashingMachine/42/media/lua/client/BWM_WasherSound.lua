BWM = BWM or {}

local playing = {}

local function key(x, y, z)
    return x .. "," .. y .. "," .. z
end

local function syncItem(args)
    local object = BWM.resolveMachine(args.x, args.y, args.z, args.objectIndex)
    local container = object and object:getContainer()
    local items = container and container:getItems()
    local item = items and args.itemIndex and items:get(args.itemIndex)
    if not item then return end

    local coveredParts
    if instanceof(item, "Clothing") or instanceof(item, "InventoryContainer") then
        coveredParts = BloodClothingType.getCoveredParts(item:getBloodClothingType())
    end
    if coveredParts then
        for index = 0, coveredParts:size() - 1 do
            local values = (args.parts or {})[index + 1]
            if values then
                local part = coveredParts:get(index)
                item:setBlood(part, values.blood)
                item:setDirt(part, values.dirt)
            end
        end
    end
    item:setBloodLevel(args.bloodLevel or 0)
    if instanceof(item, "Clothing") then
        item:setDirtiness(args.dirtiness or 0)
        item:setWetness(args.wetness or 0)
        triggerEvent("OnClothingUpdated", getPlayer())
    end
end

local function stopLoop(k)
    local entry = playing[k]
    if not entry then return end
    pcall(function() entry.emitter:stopSound(entry.handle) end)
    pcall(function() entry.emitter:stopAll() end)
    playing[k] = nil
end

local function startLoop(x, y, z, mode)
    local k = key(x, y, z)
    if playing[k] then return end
    local ok, err = pcall(function()
        local emitter = getWorld():getFreeEmitter(x + 0.5, y + 0.5, z)
        local sound = mode == "dryer" and "ClothingDryerRunning" or "ClothingWasherRunning"
        local handle = emitter:playSoundLooped(sound)
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

local function playFinished(x, y, z, mode)
    local ok, err = pcall(function()
        local emitter = getWorld():getFreeEmitter(x + 0.5, y + 0.5, z)
        local sound = mode == "dryer" and "ClothingDryerFinished" or "ClothingWasherFinished"
        local handle = emitter:playSound(sound)
        if #finishing == 0 then Events.OnTick.Add(onFinishedTick) end
        finishing[#finishing + 1] = { emitter = emitter, handle = handle, stopAt = getTimestampMs() + FINISHED_MAX_MS }
    end)
    if not ok then print("[BWM][Sound] finished failed: " .. tostring(err)) end
end

local desired = {}
local HEAR_RANGE = 30
local RECONCILE_MS = 1000
local lastReconcile = 0

local function setDesired(list)
    desired = {}
    for _, entry in pairs(list or {}) do
        if type(entry) == "table" and entry.x then
            desired[key(entry.x, entry.y, entry.z)] = { x = entry.x, y = entry.y, z = entry.z, mode = entry.mode }
        end
    end
end

local function reconcile()
    local player = getPlayer()
    for k, entry in pairs(desired) do
        local near = player and player:getZ() == entry.z
            and math.abs(player:getX() - entry.x) <= HEAR_RANGE and math.abs(player:getY() - entry.y) <= HEAR_RANGE
        if near then startLoop(entry.x, entry.y, entry.z, entry.mode) else stopLoop(k) end
    end
    for k in pairs(playing) do
        if not desired[k] then stopLoop(k) end
    end
end

Events.OnTick.Add(function()
    local now = getTimestampMs()
    if now - lastReconcile < RECONCILE_MS then return end
    lastReconcile = now
    reconcile()
end)

function BWM.onSoundEvent(args)
    local k = key(args.x, args.y, args.z)
    if args.state == "start" then
        desired[k] = { x = args.x, y = args.y, z = args.z, mode = args.mode }
    else
        desired[k] = nil
        stopLoop(k)
        if args.state == "finish" then playFinished(args.x, args.y, args.z, args.mode) end
    end
end

Events.OnReceiveGlobalModData.Add(function(moduleName, data)
    if moduleName == BWM.REGISTRY_KEY and type(data) == "table" then setDesired(data) end
end)

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= "BWM" then return end
    if command == "sound" then
        BWM.onSoundEvent(args)
    elseif command == BWM.CMD_ITEM_SYNC then
        syncItem(args)
    elseif command == "sync" then
        setDesired(args.active)
    end
end)

Events.OnGameStart.Add(function()
    ModData.request(BWM.REGISTRY_KEY)
    sendClientCommand(getPlayer(), "BWM", "requestSync", {})
end)
