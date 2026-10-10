require "TimedActions/ISToggleClothingWasher"
require "TimedActions/ISToggleComboWasherDryer"
require "TimedActions/ISSetComboWasherDryerMode"

BWM = BWM or {}

local CYCLE_KEY = "BWM_Cycle"
local REGISTRY_KEY = "BWM_ActiveWashers"
local DEFAULT_DURATION = 40
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

function BWM.isWasherMode(object)
    if instanceof(object, "IsoCombinationWasherDryer") then
        return object:isModeWasher()
    end
    return instanceof(object, "IsoClothingWasher")
end

function BWM.isCycleActive(object)
    return object:getModData()[CYCLE_KEY] ~= nil
end

local function squareKey(object)
    local square = object:getSquare()
    if not square then return nil end
    return square:getX() .. "," .. square:getY() .. "," .. square:getZ(), square
end

local function register(object)
    local key, square = squareKey(object)
    if not key then return end
    ModData.getOrCreate(REGISTRY_KEY)[key] = { x = square:getX(), y = square:getY(), z = square:getZ() }
end

local function unregister(object)
    local key = squareKey(object)
    if not key then return end
    ModData.getOrCreate(REGISTRY_KEY)[key] = nil
end

function BWM.endCycle(object)
    object:getModData()[CYCLE_KEY] = nil
    unregister(object)
    object:transmitModData()
end

function BWM.startCycle(object)
    local container = object:getContainer()
    if not container or not container:isPowered() then return false end
    if object:getFluidAmount() <= 0 then return false end

    local duration, water = BWM.getOptions()
    object:getModData()[CYCLE_KEY] = { elapsed = 0, duration = duration, water = water }
    register(object)
    object:transmitModData()
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
            if final and touched then
                item:setWetness(100)
            end
        end
    end

    -- Vanilla ISWashClothing also resets getBloodLevel() on every item, clothing included.
    local bloodLevel = item:getBloodLevel()
    if bloodLevel > 0 then
        item:setBloodLevel(final and 0 or bloodLevel * keep)
        touched = true
    end

    return touched
end

local function cleanContainer(container, fraction, final)
    local items = container:getItems()
    local touchedItems = {}
    local replacements = {}

    for index = 0, items:size() - 1 do
        local item = items:get(index)
        local ok, touched = pcall(cleanItem, item, fraction, final)
        if ok and touched then
            touchedItems[#touchedItems + 1] = item
        end
        if final and ok then
            local afterCleaning = item:getItemAfterCleaning()
            if afterCleaning then
                replacements[#replacements + 1] = { item = item, newType = afterCleaning }
            end
        end
    end

    if not final then return end

    for _, entry in ipairs(replacements) do
        container:Remove(entry.item)
        sendRemoveItemFromContainer(container, entry.item)
        local newItem = container:AddItem(entry.newType)
        if newItem then
            newItem:setFavorite(entry.item:isFavorite())
            sendAddItemToContainer(container, newItem)
        end
    end

    if isServer() then
        for _, item in ipairs(touchedItems) do
            pcall(sendItemStats, item)
        end
    end
end

local function tickWasher(object)
    local cycle = object:getModData()[CYCLE_KEY]
    local container = object:getContainer()
    if not cycle or not container then return false end
    if object:isActivated() or not BWM.isWasherMode(object) or not container:isPowered() then
        return false
    end

    local step = cycle.water / cycle.duration
    if step > 0 then
        if object:getFluidAmount() < step then return false end
        object:useFluid(step)
    end

    local remaining = cycle.duration - cycle.elapsed
    cleanContainer(container, 1 / remaining, remaining <= 1)
    cycle.elapsed = cycle.elapsed + 1
    return cycle.elapsed < cycle.duration
end

local function findCycleObject(square)
    local objects = square:getObjects()
    for index = 0, objects:size() - 1 do
        local object = objects:get(index)
        if (instanceof(object, "IsoClothingWasher") or instanceof(object, "IsoCombinationWasherDryer"))
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
                local ok, keepGoing = pcall(tickWasher, object)
                if not ok then
                    print("[BWM] cycle tick failed: " .. tostring(keepGoing))
                    keepGoing = false
                end
                if not keepGoing then
                    BWM.endCycle(object)
                end
            end
        end
    end
end
Events.EveryOneMinute.Add(onEveryOneMinute)

local function wrapToggle(actionClass)
    local original = actionClass.complete
    actionClass.complete = function(self)
        local object = self.object
        if object and not object:isActivated() and BWM.isWasherMode(object) then
            if BWM.isCycleActive(object) then
                BWM.endCycle(object)
            else
                BWM.startCycle(object)
            end
            return true
        end
        return original(self)
    end
end
wrapToggle(ISToggleClothingWasher)
wrapToggle(ISToggleComboWasherDryer)

local originalSetMode = ISSetComboWasherDryerMode.complete
ISSetComboWasherDryerMode.complete = function(self)
    if self.object and self.mode ~= "washer" and BWM.isCycleActive(self.object) then
        BWM.endCycle(self.object)
    end
    return originalSetMode(self)
end
