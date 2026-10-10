require "BWM_WashCommon"
require "TimedActions/ISToggleClothingWasher"
require "TimedActions/ISToggleClothingDryer"
require "TimedActions/ISToggleComboWasherDryer"

local function interceptComplete(actionClass, actionName)
    if not actionClass then
        print("[BWM][ERROR] Cannot intercept " .. actionName .. ": action class is unavailable")
        return
    end

    local original = actionClass.complete
    if type(original) ~= "function" then
        print("[BWM][ERROR] Cannot intercept " .. actionName .. ": complete is not a function")
        return
    end

    actionClass.complete = function(self)
        if BWM.managesToggle(self.object) then return true end
        return original(self)
    end
end

interceptComplete(ISToggleClothingWasher, "ISToggleClothingWasher")
interceptComplete(ISToggleClothingDryer, "ISToggleClothingDryer")
interceptComplete(ISToggleComboWasherDryer, "ISToggleComboWasherDryer")
