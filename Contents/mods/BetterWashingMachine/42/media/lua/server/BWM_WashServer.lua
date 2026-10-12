require "BWM_WashCommon"

if isClient() then return end

local function key(object)
    local square = object:getSquare()
    return square:getX() .. "," .. square:getY() .. "," .. square:getZ()
end

local function syncClientItem(object, itemIndex, item)
    local parts = {}
    if instanceof(item, "Clothing") or instanceof(item, "InventoryContainer") then
        local coveredParts = BloodClothingType.getCoveredParts(item:getBloodClothingType())
        if coveredParts then
            for index = 0, coveredParts:size() - 1 do
                local part = coveredParts:get(index)
                parts[index + 1] = { blood = item:getBlood(part), dirt = item:getDirt(part) }
            end
        end
    end
    local args = {
        x = object:getSquare():getX(),
        y = object:getSquare():getY(),
        z = object:getSquare():getZ(),
        objectIndex = object:getObjectIndex(),
        itemIndex = itemIndex,
        parts = parts,
        bloodLevel = item:getBloodLevel(),
    }
    if instanceof(item, "Clothing") then
        args.dirtiness = item:getDirtiness()
        args.wetness = item:getWetness()
    end
    sendServerCommand(BWM.MODULE, BWM.CMD_ITEM_SYNC, args)
end

local function notify(object, mode, state)
    local square = object:getSquare()
    local args = { x = square:getX(), y = square:getY(), z = square:getZ(), index = object:getObjectIndex(), mode = mode, state = state }
    if not isServer() and BWM.onSoundEvent then BWM.onSoundEvent(args) end
    sendServerCommand(BWM.MODULE, BWM.CMD_SOUND, args)
end

local function transmitRegistry()
    ModData.transmit(BWM.REGISTRY_KEY)
end

local function endCycle(object, finished, reason)
    local cycle = object:getModData()[BWM.CYCLE_KEY]
    if not cycle then return end
    object:getModData()[BWM.CYCLE_KEY] = nil
    ModData.getOrCreate(BWM.REGISTRY_KEY)[key(object)] = nil
    object:transmitModData()
    transmitRegistry()
    notify(object, cycle.mode, finished and "finish" or "stop")
end

local function sync(item)
    local syncFields = item.syncItemFields
    if type(syncFields) == "function" then
        local ok, err = pcall(syncFields, item)
        if not ok then print("[BWM] item field sync failed: " .. tostring(err)) end
    end
    local ok, err = pcall(sendItemStats, item)
    if not ok then print("[BWM] item sync failed: " .. tostring(err)) end
end

local function clean(item, fraction, final, mode)
    local touched = false
    if mode == "dryer" then
        if instanceof(item, "Clothing") then
            local wetness = item:getWetness()
            if wetness > 0 then
                item:setWetness(final and 0 or wetness * (1 - fraction))
                touched = true
            end
        end
        return touched
    end

    if instanceof(item, "Clothing") or instanceof(item, "InventoryContainer") then
        local parts = BloodClothingType.getCoveredParts(item:getBloodClothingType())
        if parts then
            for index = 0, parts:size() - 1 do
                local part = parts:get(index)
                local blood = item:getBlood(part)
                local dirt = item:getDirt(part)
                if blood > 0 then
                    item:setBlood(part, final and 0 or blood * (1 - fraction))
                    touched = true
                end
                if dirt > 0 then
                    item:setDirt(part, final and 0 or dirt * (1 - fraction))
                    touched = true
                end
            end
        end
    end
    if instanceof(item, "Clothing") then
        local dirtiness = item:getDirtiness()
        if dirtiness > 0 then
            item:setDirtiness(final and 0 or dirtiness * (1 - fraction))
            touched = true
        end
        if item:getWetness() < 100 then
            item:setWetness(100)
            touched = true
        end
    end
    local bloodLevel = item:getBloodLevel()
    if bloodLevel > 0 then
        item:setBloodLevel(final and 0 or bloodLevel * (1 - fraction))
        touched = true
    end
    return touched
end

local BUNDLE_AFTER_CLEANING = {
    ["Base.RippedSheetsDirtyBundle"] = "Base.RippedSheetsBundle",
    ["Base.DenimStripsDirtyBundle"] = "Base.DenimStripsBundle",
    ["Base.LeatherStripsDirtyBundle"] = "Base.LeatherStripsBundle",
}

local function process(object, cycle)
    local container = object:getContainer()
    local items = container:getItems()
    local remaining = cycle.duration - cycle.elapsed
    local replacements = {}
    for index = 0, items:size() - 1 do
        local item = items:get(index)
        local ok, touched = pcall(clean, item, 1 / remaining, remaining <= 1, cycle.mode)
        if not ok then
            print("[BWM][Server] Item processing failed for "
                .. tostring(item:getFullType()) .. ": " .. tostring(touched))
        elseif touched then
            sync(item)
            syncClientItem(object, index, item)
        end

        if cycle.mode == "washer" and remaining <= 1 then
            local afterCleaning = item:getItemAfterCleaning() or BUNDLE_AFTER_CLEANING[item:getFullType()]
            if afterCleaning then
                replacements[#replacements + 1] = { item = item, itemType = afterCleaning }
            end
        end
    end
    for _, replacement in ipairs(replacements) do
        container:Remove(replacement.item)
        sendRemoveItemFromContainer(container, replacement.item)
        local newItem = container:AddItem(replacement.itemType)
        if newItem then
            newItem:setFavorite(replacement.item:isFavorite())
            sendAddItemToContainer(container, newItem)
        end
    end
    cycle.elapsed = cycle.elapsed + 1
    object:transmitModData()
    return cycle.elapsed < cycle.duration
end

local function soakContainer(container)
    local items = container:getItems()
    for index = 0, items:size() - 1 do
        local item = items:get(index)
        if instanceof(item, "Clothing") and item:getWetness() < 100 then
            item:setWetness(100)
            sync(item)
        end
    end
end

local function startCycle(object)
    local mode, container = BWM.getMachineMode(object), object:getContainer()
    if not container or not container:isPowered() then
        return
    end
    local duration, water = BWM.getOptions()
    if mode == "dryer" then
        duration, water = BWM.getDryingDuration(), 0
    elseif not BWM.hasWater(object) then
        return
    else
        water = BWM.getWaterForLoad(container, water)
        soakContainer(container)
    end
    object:getModData()[BWM.CYCLE_KEY] = { mode = mode, elapsed = 0, duration = duration, water = water }
    local square = object:getSquare()
    ModData.getOrCreate(BWM.REGISTRY_KEY)[key(object)] = {
        x = square:getX(), y = square:getY(), z = square:getZ(), index = object:getObjectIndex(), mode = mode,
    }
    object:transmitModData()
    transmitRegistry()
    notify(object, mode, "start")
end

Events.EveryOneMinute.Add(function()
    local registry = ModData.getOrCreate(BWM.REGISTRY_KEY)
    for registryKey, entry in pairs(registry) do
        local object = BWM.resolveMachine(entry.x, entry.y, entry.z, entry.index)
        local cycle = object and object:getModData()[BWM.CYCLE_KEY]
        if not object or not cycle then
            registry[registryKey] = nil
        else
            local container = object:getContainer()
            local stopReason
            if BWM.getMachineMode(object) ~= cycle.mode then
                stopReason = "machine mode changed"
            elseif not container or not container:isPowered() then
                stopReason = "machine lost power"
            end
            if stopReason then
                endCycle(object, false, stopReason)
            else
                local step = cycle.water / cycle.duration
                local hasWater = true
                if step > 0 then
                    local amount = object:getFluidAmount()
                    if amount > 0 then
                        hasWater = amount >= step
                        if hasWater then object:useFluid(step) end
                    else
                        hasWater = BWM.hasWater(object)
                    end
                end
                if not hasWater then
                    endCycle(object, false, "insufficient water")
                elseif not process(object, cycle) then
                    endCycle(object, true)
                end
            end
        end
    end
end)

require "TimedActions/ISSetComboWasherDryerMode"

local lastToggle = {}

local function canInteract(player, object)
    local square = object:getSquare()
    if not square or not player then return false end
    if math.abs(player:getZ() - square:getZ()) > 0.5 then return false end
    local dx, dy = player:getX() - (square:getX() + 0.5), player:getY() - (square:getY() + 0.5)
    return dx * dx + dy * dy <= BWM.MAX_INTERACT_DISTANCE * BWM.MAX_INTERACT_DISTANCE
end

local function deny() end

local function onToggle(player, args)
    if type(args) ~= "table" then return deny("bad args") end
    local object = BWM.resolveMachine(args.x, args.y, args.z, args.objectIndex)
    if not object then return deny("machine not found") end
    if not BWM.managesToggle(object) then return deny("unsupported machine mode") end
    if not canInteract(player, object) then return deny("player too far") end

    local id = key(object)
    local now = getTimestampMs()
    if lastToggle[id] and now - lastToggle[id] < BWM.TOGGLE_DEBOUNCE_MS then return deny("duplicate request") end
    lastToggle[id] = now

    local active = BWM.isCycleActive(object)
    if args.wantOn == true and active then return end
    if args.wantOn == false and not active then return end
    if active then
        endCycle(object, false, "toggle requested")
    else
        startCycle(object)
    end
end

local function onRequestSync(player)
    local list = {}
    for _, entry in pairs(ModData.getOrCreate(BWM.REGISTRY_KEY)) do
        list[#list + 1] = { x = entry.x, y = entry.y, z = entry.z, index = entry.index, mode = entry.mode }
    end
    sendServerCommand(player, BWM.MODULE, BWM.CMD_SYNC, { active = list })
end

Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= BWM.MODULE then return end
    if command == BWM.CMD_TOGGLE then onToggle(player, args)
    elseif command == BWM.CMD_REQUEST_SYNC then onRequestSync(player) end
end)

local originalSetMode = ISSetComboWasherDryerMode.complete
ISSetComboWasherDryerMode.complete = function(self)
    if not self.object then return originalSetMode(self) end
    if BWM.isCycleActive(self.object) then endCycle(self.object, false, "machine mode changed") end
    return originalSetMode(self)
end
