require "BWM_WashCommon"
require "BWM_WashToggle"

local function sendToggle(player, object)
    local square = object:getSquare()
    if not square then return end
    sendClientCommand(player, BWM.MODULE, BWM.CMD_TOGGLE, {
        x = square:getX(), y = square:getY(), z = square:getZ(),
        objectIndex = object:getObjectIndex(),
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
