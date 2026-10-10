require "ISUI/LootWindow/Handlers/ClothingWasherToggle"
require "ISUI/LootWindow/Handlers/ClothingDryerToggle"
require "ISUI/ISContextMenu"
require "ISUI/ISWorldObjectContextMenu"
require "ISUI/ISInventoryPaneContextMenu"
require "ISUI/LootWindow/Handlers/CombinationWasherDryerToggle"
require "BWM_WashCommon"

local function patchHandler(handler, machineClass)
    local originalVisible = handler.shouldBeVisible
    handler.shouldBeVisible = function(self)
        if originalVisible(self) then return true end
        local object = self.object
        if not machineClass or not instanceof(object, machineClass) then return false end
        if getCore():getGameMode() == "Tutorial" or not self.container or not self.container:isPowered() then
            return false
        end
        local mode = BWM.getMachineMode(object)
        return mode == "washer" and BWM.hasWater(object)
    end

    local originalGetControl = handler.getControl
    handler.getControl = function(self)
        if handler.createIconControl then
            local control = originalGetControl(self)
            if control and not control.bwmWrapped then
                control.bwmWrapped = true
                local originalPrerender = control.prerender
                control.prerender = function(btn)
                    if BWM.isCycleActive(self.object) and self.container:isPowered() then
                        local alpha = btn.mouseOver and 0.8 or 0.6
                        btn:drawTextureScaled(getTexture("media/ui/CleanUI/Button/2_3Background.png"), 0, 0, btn.width, btn.height, alpha, 0.2, 0.6, 0.2)

                        btn:drawTextureScaled(getTexture("media/ui/CleanUI/Button/2_3Border.png"), 0, 0, btn.width, btn.height, 1, 0.4, 0.4, 0.4)
                        btn:drawTextureScaled(getTexture("media/ui/CleanUI/ICON/Icon_ON.png"), 0, 0, btn.width, btn.height, 1, 0.8, 0.8, 0.8)
                        control.tooltip = getText("ContextMenu_Turn_Off")
                        btn:updateTooltip()
                    else
                        originalPrerender(btn)
                    end
                end
            end
            return control
        end
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
            option.iconTexture = BWM.getCycleMode(self.object) == "dryer"
                and ContainerButtonIcons.clothingdryer or ContainerButtonIcons.clothingwasher
            return
        end
        return originalJoypad(self, context)
    end
end

patchHandler(ISLootWindowObjectControlHandler_ClothingWasherToggle, "IsoClothingWasher")
patchHandler(ISLootWindowObjectControlHandler_ClothingDryerToggle)
patchHandler(ISLootWindowObjectControlHandler_CombinationWasherDryerToggle, "IsoCombinationWasherDryer")

local function findMachineParam(option)
    for index = 1, 10 do
        local value = option["param" .. index]
        if value ~= nil and type(value) ~= "string" and type(value) ~= "number"
            and type(value) ~= "boolean" and type(value) ~= "function" then
            local ok, isWasher = pcall(function()
                return instanceof(value, "IsoClothingWasher") or instanceof(value, "IsoClothingDryer")
                    or instanceof(value, "IsoCombinationWasherDryer")
            end)
            if ok and isWasher then return value end
        end
    end
    return nil
end

local function addTimeLeft(menu, machine)
    local minutes = BWM.getMinutesLeft(machine)
    if not minutes then return end
    menu:addOption(getText("ContextMenu_BWM_MinutesLeft", minutes))
    local options = menu.options
    table.insert(options, 1, table.remove(options))
    for index, option in ipairs(options) do option.id = index end
end

local function fixMenu(menu, turnOn, turnOff)
    local activeMachine
    for _, option in ipairs(menu.options) do
        if option.name == turnOn then
            local machine = findMachineParam(option)
            if machine and BWM.isCycleActive(machine) then
                option.name = turnOff
                activeMachine = machine
            end
        end
    end
    for _, option in ipairs(menu.options) do
        if option.subOption then
            local subMenu = menu:getSubMenu(option.subOption)
            if subMenu then fixMenu(subMenu, turnOn, turnOff) end
        end
    end
    if activeMachine then addTimeLeft(menu, activeMachine) end
end

Events.OnFillWorldObjectContextMenu.Add(function(player, context, worldobjects, test)
    if test then return end
    local ok, err = pcall(fixMenu, context, getText("ContextMenu_Turn_On"), getText("ContextMenu_Turn_Off"))
    if not ok then print("[BWM][UI] menu label fix failed: " .. tostring(err)) end
end)
