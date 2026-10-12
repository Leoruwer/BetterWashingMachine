require "BWM_WashCommon"
require "BWM_WashToggle"

local MENU_INTENT_TTL_MS = 120000
local menuIntent = {}

-- The menu label (On/Off) can be stale when the click happens; remember what the player was shown.
function BWM.recordMenuIntent(object, wantOn)
    local square = object:getSquare()
    if not square then return end
    menuIntent[BWM.machineKey(square:getX(), square:getY(), square:getZ())] = { wantOn = wantOn, at = getTimestampMs() }
end

local function sendToggle(player, object)
    local square = object:getSquare()
    if not square then return end
    local id = BWM.machineKey(square:getX(), square:getY(), square:getZ())
    local intent = menuIntent[id]
    menuIntent[id] = nil
    local wantOn
    if intent and getTimestampMs() - intent.at < MENU_INTENT_TTL_MS then
        wantOn = intent.wantOn
    else
        wantOn = not BWM.isCycleActive(object)
    end
    sendClientCommand(player, BWM.MODULE, BWM.CMD_TOGGLE, {
        x = square:getX(), y = square:getY(), z = square:getZ(),
        objectIndex = object:getObjectIndex(),
        wantOn = wantOn,
    })
end

for _, actionClass in ipairs({ ISToggleClothingWasher, ISToggleClothingDryer, ISToggleComboWasherDryer }) do
    local original = actionClass.perform
    actionClass.perform = function(self)
        if BWM.managesToggle(self.object) then
            ISBaseTimedAction.perform(self)
            sendToggle(self.character, self.object)
            return
        end
        return original(self)
    end
end
