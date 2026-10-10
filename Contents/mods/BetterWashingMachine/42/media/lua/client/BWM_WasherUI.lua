require "ISUI/LootWindow/Handlers/ClothingWasherToggle"
require "ISUI/ISContextMenu"
require "ISUI/ISWorldObjectContextMenu"
require "ISUI/ISInventoryPaneContextMenu"
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

-- The world right-click menu entries for the washer are created by Java
-- (ISWorldObjectContextMenuLogic.createMenuEntries), which reads isActivated().
-- That runs before OnFillWorldObjectContextMenu, so the label is corrected afterwards.
local function findWasherParam(option)
    for index = 1, 10 do
        local value = option["param" .. index]
        if value ~= nil and type(value) ~= "string" and type(value) ~= "number"
            and type(value) ~= "boolean" and type(value) ~= "function" then
            local ok, isWasher = pcall(function()
                return instanceof(value, "IsoClothingWasher") or instanceof(value, "IsoCombinationWasherDryer")
            end)
            if ok and isWasher then return value end
        end
    end
    return nil
end

local function fixMenu(menu, turnOn, turnOff)
    for _, option in ipairs(menu.options) do
        if option.name == turnOn then
            local washer = findWasherParam(option)
            if washer and BWM.isWasherMode(washer) and BWM.isCycleActive(washer) then
                option.name = turnOff
            end
        end
        if option.subOption then
            local subMenu = menu:getSubMenu(option.subOption)
            if subMenu then fixMenu(subMenu, turnOn, turnOff) end
        end
    end
end

Events.OnFillWorldObjectContextMenu.Add(function(player, context, worldobjects, test)
    if test then return end
    local ok, err = pcall(fixMenu, context, getText("ContextMenu_Turn_On"), getText("ContextMenu_Turn_Off"))
    if not ok then print("[BWM][UI] menu label fix failed: " .. tostring(err)) end
end)
