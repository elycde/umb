-- ========================================================================
-- elycde Visuals Suite for Umbrella Dota 2
-- Полный пакет визуальных настроек: Погода, Камера, Окружение
-- ========================================================================

local Visuals = {}

-- ------------------------------------------------------------------------
-- Меню: Scripts -> elycde -> Visuals
-- ------------------------------------------------------------------------
local vis_tab = Menu.Create("Scripts", "elycde", "Visuals")
vis_tab:Icon("\u{f06e}")

local side_left = (Enum and Enum.GroupSide and Enum.GroupSide.Left) or nil
local side_right = (Enum and Enum.GroupSide and Enum.GroupSide.Right) or nil

-- ------------------------------------------------------------------------
-- Вкладка 1: Погода (Weather Changer)
-- ------------------------------------------------------------------------
local group_weather = vis_tab:Create("Погода (Weather Changer)", side_left)

local WEATHER_PRESETS = {
    "По умолчанию",
    "1. Зима / Снег (Winter)",
    "2. Дождь (Rain)",
    "3. Лунный свет (Moonbeam)",
    "4. Мор / Болото (Pestilence)",
    "5. Сакура / Урожай (Harvest)",
    "6. Сирокко / Пустыня (Sirocco)",
    "7. Весна (Spring)",
    "8. Пепел / Ад (Ash)",
    "9. Северное сияние (Aurora)",
    "10. Кровавый туман (Crimson)"
}

local ui_weather_enable = group_weather:Switch("Включить кастомную погоду", true, "\u{f0c2}")
ui_weather_enable:ToolTip("Активирует выбранный погодный эффект на карте Доты 2")

local ui_weather_choice = group_weather:Combo("Эффект погоды", WEATHER_PRESETS, 0)
ui_weather_choice:ToolTip("Выберите любой понравившийся погодный эффект (из официальных предметов погоды)")

local ui_weather_btn_reset = group_weather:Button("Сбросить погоду на дефолт", function()
    if ui_weather_choice then ui_weather_choice:Set(0) end
end)

-- ------------------------------------------------------------------------
-- Вкладка 2: Камера (Camera Distance)
-- ------------------------------------------------------------------------
local group_camera = vis_tab:Create("Камера (Camera Distance)", side_right)

local ui_cam_enable = group_camera:Switch("Кастомная дистанция камеры", false, "\u{f030}")
ui_cam_enable:ToolTip("Позволяет отдалить камеру для большего обзора карты")

local ui_cam_distance = group_camera:Slider("Дистанция камеры", 1134, 2000, 1350, "%d")
ui_cam_distance:ToolTip("Стандартное отдаление в Доте 2: 1134 - 1200.\nКомфортное значение: 1300 - 1500.")

local ui_cam_btn_reset = group_camera:Button("Сбросить камеру на 1134", function()
    if ui_cam_distance then ui_cam_distance:Set(1134) end
end)

-- ------------------------------------------------------------------------
-- Вкладка 3: Окружение и Атмосфера (Environment)
-- ------------------------------------------------------------------------
local group_env = vis_tab:Create("Окружение и Видимость", side_left)

local ui_fog_disable = group_env:Switch("Убрать атмосферный туман (No Fog)", false, "\u{f75f}")
ui_fog_disable:ToolTip("Убирает серую атмосферную дымку (fog_enable 0), делая изображение кристально четким")

local ui_farz_boost = group_env:Switch("Увеличить дальность прорисовки (FarZ)", false, "\u{f06e}")
ui_farz_boost:ToolTip("Увеличивает дальность прорисовки объектов на карте при высоком отдалении камеры")

-- ------------------------------------------------------------------------
-- ConVars & Состояние
-- ------------------------------------------------------------------------
local cvar_weather = ConVar.Find("cl_weather")
local cvar_camera = ConVar.Find("dota_camera_distance")
local cvar_fog = ConVar.Find("fog_enable")
local cvar_farz = ConVar.Find("r_farz")

local last_weather_val = -1
local last_cam_val = -1
local last_fog_val = -1
local last_farz_val = -1
local next_check_time = 0

local function ApplyWeather(val)
    if cvar_weather then
        pcall(function() ConVar.SetInt(cvar_weather, val) end)
    else
        Engine.ExecuteCommand(string.format("cl_weather %d", val))
    end
end

local function ApplyCamera(val)
    if cvar_camera then
        pcall(function() ConVar.SetInt(cvar_camera, val) end)
    else
        Engine.ExecuteCommand(string.format("dota_camera_distance %d", val))
    end
end

local function ApplyFog(enabled_flag)
    local v = enabled_flag and 1 or 0
    if cvar_fog then
        pcall(function() ConVar.SetInt(cvar_fog, v) end)
    else
        Engine.ExecuteCommand(string.format("fog_enable %d", v))
    end
end

local function ApplyFarz(val)
    if cvar_farz then
        pcall(function() ConVar.SetInt(cvar_farz, val) end)
    else
        Engine.ExecuteCommand(string.format("r_farz %d", val))
    end
end

-- ------------------------------------------------------------------------
-- Callbacks чита
-- ------------------------------------------------------------------------
function Visuals.OnUpdate()
    if not Engine.IsInGame() then return end

    local now = os.clock()
    if now < next_check_time then return end
    next_check_time = now + 0.1

    -- 1. Погода
    local target_weather = 0
    if ui_weather_enable and ui_weather_enable:Get() then
        target_weather = (ui_weather_choice and ui_weather_choice:Get()) or 0
    end

    if target_weather ~= last_weather_val then
        ApplyWeather(target_weather)
        last_weather_val = target_weather
    end

    -- 2. Дистанция камеры
    local target_cam = 1134
    if ui_cam_enable and ui_cam_enable:Get() then
        target_cam = (ui_cam_distance and ui_cam_distance:Get()) or 1134
    end

    if target_cam ~= last_cam_val then
        ApplyCamera(target_cam)
        last_cam_val = target_cam
    end

    -- 3. Атмосферный туман
    local fog_off = (ui_fog_disable and ui_fog_disable:Get()) or false
    local target_fog = fog_off and 0 or 1
    if target_fog ~= last_fog_val then
        ApplyFog(target_fog == 1)
        last_fog_val = target_fog
    end

    -- 4. Дальность прорисовки FarZ
    local boost_farz = (ui_farz_boost and ui_farz_boost:Get()) or false
    local target_farz = boost_farz and 8000 or -1
    if target_farz ~= last_farz_val then
        ApplyFarz(target_farz)
        last_farz_val = target_farz
    end
end

function Visuals.OnScriptUnload()
    ApplyWeather(0)
    ApplyCamera(1134)
    ApplyFog(true)
    ApplyFarz(-1)
end

return Visuals
