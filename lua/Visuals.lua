-- ========================================================================
-- elycde Visuals for Umbrella Dota 2
-- Погода (Weather Changer)
-- ========================================================================

local Visuals = {}

-- ------------------------------------------------------------------------
-- Меню: Scripts -> elycde -> Visuals -> Погода
-- ------------------------------------------------------------------------
local vis_tab = Menu.Create("Scripts", "elycde", "Visuals")
pcall(function() vis_tab:Icon("\u{f06e}") end)

local tab_weather = vis_tab:Create("Погода")
pcall(function() tab_weather:Icon("\u{f0c2}") end)

local group = tab_weather:Create("Настройки погоды")
if not group or (not group.Combo and not group.ComboBox) then
    group = Menu.Create("Scripts", "elycde", "Visuals", "Main", "Погода")
end

local weather_list = {
    "По умолчанию",
    "1. Зима",
    "2. Дождь",
    "3. Сакура",
    "4. Болото",
    "5. Осень",
    "6. Пустыня",
    "7. Весна",
    "8. Ад",
    "9. Северное сияние"
}

local ui_weather = nil
if group and group.Combo then
    ui_weather = group:Combo("Эффект погоды", weather_list, 0)
elseif group and group.ComboBox then
    ui_weather = group:ComboBox("Эффект погоды", weather_list, 0)
end

if ui_weather then
    pcall(function()
        ui_weather:Icon("\u{f0c2}")
        ui_weather:ToolTip("Смена погодного эффекта на карте Доты 2")
    end)
end

local cvar_weather = ConVar.Find("cl_weather")
local last_weather_val = -1

function Visuals.OnUpdate()
    if not Engine.IsInGame() then return end

    if ui_weather then
        local current_weather = ui_weather:Get() or 0
        if current_weather ~= last_weather_val then
            if cvar_weather then
                pcall(function() ConVar.SetInt(cvar_weather, current_weather) end)
            else
                Engine.ExecuteCommand(string.format("cl_weather %d", current_weather))
            end
            last_weather_val = current_weather
        end
    end
end

function Visuals.OnScriptUnload()
    if cvar_weather then
        pcall(function() ConVar.SetInt(cvar_weather, 0) end)
    else
        Engine.ExecuteCommand("cl_weather 0")
    end
end

return Visuals
