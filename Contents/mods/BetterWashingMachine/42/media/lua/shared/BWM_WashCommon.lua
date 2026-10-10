BWM = BWM or {}

BWM.CYCLE_KEY = "BWM_Cycle"
BWM.REGISTRY_KEY = "BWM_ActiveWashers"

BWM.MODULE = "BWM"
BWM.CMD_TOGGLE = "toggle"
BWM.CMD_REQUEST_SYNC = "requestSync"
BWM.CMD_SOUND = "sound"
BWM.CMD_SYNC = "sync"
BWM.CMD_ITEM_SYNC = "itemSync"
BWM.MAX_INTERACT_DISTANCE = 4
BWM.TOGGLE_DEBOUNCE_MS = 1000

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

function BWM.getOptions()
    local vars = SandboxVars and SandboxVars.BWMachine or nil
    local duration = vars and tonumber(vars.CycleDuration) or 40
    local water = vars and tonumber(vars.WaterPerCycle) or 100
    return clamp(math.floor(duration), 10, 120), clamp(water, 0, 600)
end

function BWM.getDryingDuration()
    local vars = SandboxVars and SandboxVars.BWMachine or nil
    return clamp(math.floor(vars and tonumber(vars.DryingCycleDuration) or 40), 10, 120)
end

function BWM.getWaterForLoad(container, baseWater)
    local vars = SandboxVars and SandboxVars.BWMachine or nil
    local ratio = container:getCapacity() > 0 and container:getCapacityWeight() / container:getCapacity() or 0
    local percent
    if ratio <= 0.33 then
        percent = vars and tonumber(vars.LowLoadWater) or 30
    elseif ratio <= 0.66 then
        percent = vars and tonumber(vars.MediumLoadWater) or 60
    else
        percent = 100
    end
    return baseWater * clamp(percent, 0, 100) / 100
end

function BWM.getMachineMode(object)
    if not object then return nil end
    if instanceof(object, "IsoCombinationWasherDryer") then
        return object:isModeWasher() and "washer" or "dryer"
    end
    if instanceof(object, "IsoClothingWasher") then return "washer" end
    if instanceof(object, "IsoClothingDryer") then return "dryer" end
    return nil
end

function BWM.isSupportedMachine(object)
    return object ~= nil and (instanceof(object, "IsoClothingWasher")
        or instanceof(object, "IsoClothingDryer")
        or instanceof(object, "IsoCombinationWasherDryer"))
end

function BWM.managesToggle(object)
    return BWM.isSupportedMachine(object) and BWM.getMachineMode(object) == "washer"
end

function BWM.machineKey(x, y, z)
    return x .. "," .. y .. "," .. z
end

function BWM.resolveMachine(x, y, z, objectIndex)
    if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then return nil end
    local cell = getCell()
    local square = cell and cell:getGridSquare(x, y, z)
    if not square then return nil end

    local objects = square:getObjects()
    if type(objectIndex) == "number" and objectIndex >= 0 and objectIndex < objects:size() then
        local object = objects:get(objectIndex)
        if BWM.isSupportedMachine(object) then return object end
    end
    for index = 0, objects:size() - 1 do
        local object = objects:get(index)
        if BWM.isSupportedMachine(object) then return object end
    end
    return nil
end

function BWM.isCycleActive(object)
    return object:getModData()[BWM.CYCLE_KEY] ~= nil
end

function BWM.getCycleMode(object)
    local cycle = object:getModData()[BWM.CYCLE_KEY]
    return cycle and cycle.mode or nil
end

function BWM.getMinutesLeft(object)
    local cycle = object:getModData()[BWM.CYCLE_KEY]
    return cycle and math.max(1, cycle.duration - cycle.elapsed) or nil
end

function BWM.hasWater(object)
    return object:getFluidAmount() > 0 or (object.hasWater and object:hasWater())
end
