require "ISUI/LootWindow/Handlers/ClothingWasherToggle"
require "ISUI/LootWindow/Handlers/CombinationWasherDryerToggle"
require "BWM_WashCycle"

local function patchHandler(handler)
    local originalGetControl = handler.getControl
    handler.getControl = function(self)
        if BWM.isCycleActive(self.object) then
            self.control = self:getButtonControl(getText("ContextMenu_Turn_Off"))
            return self.control
        end
        return originalGetControl(self)
    end

    local originalJoypad = handler.handleJoypadContextMenu
    handler.handleJoypadContextMenu = function(self, context)
        if BWM.isCycleActive(self.object) then
            local option = self:addJoypadContextMenuOption(context, getText("ContextMenu_Turn_Off"))
            option.iconTexture = ContainerButtonIcons.clothingwasher
            return
        end
        return originalJoypad(self, context)
    end
end

patchHandler(ISLootWindowObjectControlHandler_ClothingWasherToggle)
patchHandler(ISLootWindowObjectControlHandler_CombinationWasherDryerToggle)
