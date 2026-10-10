require "TimedActions/ISToggleClothingWasher"
require "TimedActions/ISToggleClothingDryer"
require "TimedActions/ISToggleComboWasherDryer"
require "TimedActions/ISSetComboWasherDryerMode"

BWM = BWM or {}

local CYCLE_KEY = "BWM_Cycle"
local REGISTRY_KEY = "BWM_ActiveWashers"
local DEFAULT_DURATION = 40
local DEFAULT_DRYING_DURATION = 40
local DEFAULT_WATER = 100

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

function BWM.getOptions()
    local vars = SandboxVars and SandboxVars.BWMachine or nil
    local duration = vars and tonumber(vars.CycleDuration) or DEFAULT_DURATION
    local water = vars and tonumber(vars.WaterPerCycle) or DEFAULT_WATER
    return clamp(math.floor(duration), 10, 120), clamp(water, 0, 600)
end

function BWM.getDryingDuration()
    local vars = SandboxVars and SandboxVars.BWMachine or nil
    local duration = vars and tonumber(vars.DryingCycleDuration) or DEFAULT_DRYING_DURATION
    return clamp(math.floor(duration), 10, 120)
end

local LOAD_DEFAULTS = { LowLoadWater = 30, MediumLoadWater = 60 }
local LOW_LOAD_LIMIT = 0.33
local MEDIUM_LOAD_LIMIT = 0.66

local function loadOption(name)
    local vars = SandboxVars and SandboxVars.BWMachine or nil
    local value = vars and tonumber(vars[name]) or LOAD_DEFAULTS[name]
    return clamp(value, 0, 100)
end

-- Water for one cycle: the base amount scaled by how full the machine is.
-- A load above the medium limit always uses the full base amount.
function BWM.getWaterForLoad(container, baseWater)
    local maxWeight = container:getCapacity()
    local ratio = maxWeight > 0 and container:getCapacityWeight() / maxWeight or 0
    local percent
    if ratio <= LOW_LOAD_LIMIT then
        percent = loadOption("LowLoadWater")
    elseif ratio <= MEDIUM_LOAD_LIMIT then
        percent = loadOption("MediumLoadWater")
    else
        percent = 100
    end
    return baseWater * percent / 100
end

function BWM.getMachineMode(object)
    if instanceof(object, "IsoCombinationWasherDryer") then
        return object:isModeWasher() and "washer" or "dryer"
    end
    if instanceof(object, "IsoClothingWasher") then
        return "washer"
    end
    if instanceof(object, "IsoClothingDryer") then
        return "dryer"
    end
    return nil
end

function BWM.isWasherMode(object)
    return BWM.getMachineMode(object) == "washer"
end

function BWM.isCycleActive(object)
    return object:getModData()[CYCLE_KEY] ~= nil
end

function BWM.getCycleMode(object)
    local cycle = object:getModData()[CYCLE_KEY]
    return cycle and (cycle.mode or "washer") or nil
end

local function squareKey(object)
    local square = object:getSquare()
    if not square then return nil end
    return square:getX() .. "," .. square:getY() .. "," .. square:getZ(), square
end

local function register(object)
    local key, square = squareKey(object)
    if not key then return end
    ModData.getOrCreate(REGISTRY_KEY)[key] = {
        x = square:getX(),
        y = square:getY(),
        z = square:getZ(),
        mode = BWM.getCycleMode(object),
    }
end

local function unregister(object)
    local key = squareKey(object)
    if not key then return end
    ModData.getOrCreate(REGISTRY_KEY)[key] = nil
end

local function notifySound(object, mode, state)
    local square = object:getSquare()
    if not square then return end
    local args = { x = square:getX(), y = square:getY(), z = square:getZ(), mode = mode, state = state }
    if isServer() then
        sendServerCommand("BWM", "sound", args)
    elseif BWM.onSoundEvent then
        BWM.onSoundEvent(args)
    end
end

function BWM.endCycle(object, finished)
    local mode = BWM.getCycleMode(object) or "washer"
    object:getModData()[CYCLE_KEY] = nil
    unregister(object)
    object:transmitModData()
    notifySound(object, mode, finished and "finish" or "stop")
end

local function soakContainer(container)
    local items = container:getItems()
    for index = 0, items:size() - 1 do
        local item = items:get(index)
        if instanceof(item, "Clothing") and item:getWetness() < 100 then
            item:setWetness(100)
            if isServer() then
                local ok, err = pcall(sendItemStats, item)
                if not ok then print("[BWM] item sync failed: " .. tostring(err)) end
            end
        end
    end
end

function BWM.startCycle(object, mode)
    mode = mode or "washer"
    local container = object:getContainer()
    if not container or not container:isPowered() then return false end

    local duration, water
    if mode == "washer" then
        if object:getFluidAmount() <= 0 then return false end
        duration, water = BWM.getOptions()
        water = BWM.getWaterForLoad(container, water)
    else
        duration = BWM.getDryingDuration()
        water = 0
    end
    if mode == "washer" then soakContainer(container) end
    object:getModData()[CYCLE_KEY] = { mode = mode, elapsed = 0, duration = duration, water = water }
    register(object)
    object:transmitModData()
    notifySound(object, mode, "start")
    return true
end

local function cleanItem(item, fraction, final)
    local keep = 1 - fraction
    local touched = false

    if instanceof(item, "Clothing") or instanceof(item, "InventoryContainer") then
        local parts = BloodClothingType.getCoveredParts(item:getBloodClothingType())
        if parts then
            for index = 0, parts:size() - 1 do
                local part = parts:get(index)
                local blood = item:getBlood(part)
                if blood > 0 then
                    item:setBlood(part, final and 0 or blood * keep)
                    touched = true
                end
                local dirt = item:getDirt(part)
                if dirt > 0 then
                    item:setDirt(part, final and 0 or dirt * keep)
                    touched = true
                end
            end
        end
        if instanceof(item, "Clothing") then
            local dirtiness = item:getDirtiness()
            if dirtiness > 0 then
                item:setDirtiness(final and 0 or dirtiness * keep)
                touched = true
            end
            if item:getWetness() < 100 then
                item:setWetness(100)
                touched = true
            end
        end
    end

    local bloodLevel = item:getBloodLevel()
    if bloodLevel > 0 then
        item:setBloodLevel(final and 0 or bloodLevel * keep)
        touched = true
    end

    return touched
end

local function dryItem(item, fraction, final)
    if not instanceof(item, "Clothing") then return false end
    local wetness = item:getWetness()
    if wetness <= 0 then return false end
    item:setWetness(final and 0 or wetness * (1 - fraction))
    return true
end

local function processContainer(container, fraction, final, mode)
    local items = container:getItems()
    local touchedItems = {}
    local replacements = {}

    for index = 0, items:size() - 1 do
        local item = items:get(index)
        local processor = mode == "dryer" and dryItem or cleanItem
        local ok, touched = pcall(processor, item, fraction, final)
        if ok and touched then
            touchedItems[#touchedItems + 1] = item
        end
        if mode == "washer" and final and ok then
            local afterCleaning = item:getItemAfterCleaning()
            if afterCleaning then
                replacements[#replacements + 1] = { item = item, newType = afterCleaning }
            end
        end
    end

    if mode == "washer" and final then
        for _, entry in ipairs(replacements) do
            container:Remove(entry.item)
            sendRemoveItemFromContainer(container, entry.item)
            local newItem = container:AddItem(entry.newType)
            if newItem then
                newItem:setFavorite(entry.item:isFavorite())
                sendAddItemToContainer(container, newItem)
            end
        end
    end

    if isServer() and (mode == "dryer" or final) then
        for _, item in ipairs(touchedItems) do
            local ok, err = pcall(sendItemStats, item)
            if not ok then print("[BWM] item sync failed: " .. tostring(err)) end
        end
    end
end

local function tickCycle(object)
    local cycle = object:getModData()[CYCLE_KEY]
    local container = object:getContainer()
    if not cycle or not container then return false end
    local mode = cycle.mode or "washer"
    if object:isActivated() or BWM.getMachineMode(object) ~= mode or not container:isPowered() then
        return false
    end

    if mode == "washer" then
        local step = cycle.water / cycle.duration
        if step > 0 then
            if object:getFluidAmount() < step then return false end
            object:useFluid(step)
        end
    end

    local remaining = cycle.duration - cycle.elapsed
    processContainer(container, 1 / remaining, remaining <= 1, mode)
    cycle.elapsed = cycle.elapsed + 1
    return cycle.elapsed < cycle.duration
end

local function findCycleObject(square)
    local objects = square:getObjects()
    for index = 0, objects:size() - 1 do
        local object = objects:get(index)
        if (instanceof(object, "IsoClothingWasher") or instanceof(object, "IsoClothingDryer")
            or instanceof(object, "IsoCombinationWasherDryer"))
            and BWM.isCycleActive(object) then
            return object
        end
    end
    return nil
end

local function onEveryOneMinute()
    if isClient() then return end
    local registry = ModData.getOrCreate(REGISTRY_KEY)
    local keys = {}
    for key in pairs(registry) do keys[#keys + 1] = key end

    for _, key in ipairs(keys) do
        local entry = registry[key]
        local square = entry and getCell():getGridSquare(entry.x, entry.y, entry.z)
        if square then
            local object = findCycleObject(square)
            if not object then
                registry[key] = nil
            else
                local ok, keepGoing = pcall(tickCycle, object)
                if not ok then
                    print("[BWM] cycle tick failed: " .. tostring(keepGoing))
                    keepGoing = false
                end
                if not keepGoing then
                    local cycle = object:getModData()[CYCLE_KEY]
                    BWM.endCycle(object, ok and cycle and cycle.elapsed >= cycle.duration)
                end
            end
        end
    end
end
Events.EveryOneMinute.Add(onEveryOneMinute)

local SOAK_INTERVAL_TICKS = 3
local soakTicks = 0

local function onTickKeepSoaked()
    if isClient() then return end
    soakTicks = soakTicks + 1
    if soakTicks < SOAK_INTERVAL_TICKS then return end
    soakTicks = 0

    local registry = ModData.getOrCreate(REGISTRY_KEY)
    for _, entry in pairs(registry) do
        if entry.mode == "washer" then
            local square = getCell():getGridSquare(entry.x, entry.y, entry.z)
            local object = square and findCycleObject(square)
            local container = object and object:getContainer()
            if container then
                local items = container:getItems()
                for index = 0, items:size() - 1 do
                    local item = items:get(index)
                    if instanceof(item, "Clothing") and item:getWetness() < 100 then
                        item:setWetness(100)
                    end
                end
            end
        end
    end
end
Events.OnTick.Add(onTickKeepSoaked)

local function wrapToggle(actionClass)
    local original = actionClass.complete
    actionClass.complete = function(self)
        local object = self.object
        local mode = object and BWM.getMachineMode(object)
        if object and mode then
            if BWM.isCycleActive(object) and not object:isActivated() then
                BWM.endCycle(object)
                return true
            elseif not object:isActivated() then
                BWM.startCycle(object, mode)
                return true
            end
        end
        return original(self)
    end
end
wrapToggle(ISToggleClothingWasher)
wrapToggle(ISToggleClothingDryer)
wrapToggle(ISToggleComboWasherDryer)

local originalSetMode = ISSetComboWasherDryerMode.complete
ISSetComboWasherDryerMode.complete = function(self)
    if self.object and BWM.isCycleActive(self.object) then
        BWM.endCycle(self.object)
    end
    return originalSetMode(self)
end
