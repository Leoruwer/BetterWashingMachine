require "BWM_WashCommon"
require "TimedActions/ISToggleClothingWasher"
require "TimedActions/ISToggleClothingDryer"
require "TimedActions/ISToggleComboWasherDryer"

-- In Washer mode the vanilla action must never reach setActivated(); the client
-- sends BWM/toggle instead and the server owns the cycle. Other modes stay vanilla.
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

print("[BWM] Loaded BWM_WashToggle LOCAL BWMachineDebug MP FIX v3")
