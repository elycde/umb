-- ========================================================================
-- elycde Settings Suite for Umbrella Dota 2
-- Меню: Scripts -> elycde -> Настройки
-- ========================================================================

local Settings = {}

local SERVER_URL = "http://127.0.0.1:8765"
local GITHUB_REPO = "https://github.com/elycde/umb"

-- ------------------------------------------------------------------------
-- Меню: Scripts -> elycde -> Настройки
-- ------------------------------------------------------------------------
local settings_tab = Menu.Create("Scripts", "elycde", "Настройки")
pcall(function() settings_tab:Icon("\u{f013}") end)

local tab_main = settings_tab:Create("Общие")
pcall(function() tab_main:Icon("\u{f021}") end)

local side_left = (Enum and Enum.GroupSide and Enum.GroupSide.Left) or nil
local side_right = (Enum and Enum.GroupSide and Enum.GroupSide.Right) or nil

-- Левая колонка: Обновление скриптов с GitHub
local group_update = tab_main:Create("Обновление скриптов (GitHub)", side_left)
if not group_update or not group_update.Button then
    group_update = Menu.Create("Scripts", "elycde", "Настройки", "Общие", "Обновление скриптов (GitHub)")
end

local ui_repo_label = group_update:Label("Репозиторий: elycde/umb")
local ui_update_status = group_update:Label("Статус: Ожидание")

local function CheckUpdates()
    if ui_update_status then
        pcall(function() ui_update_status:Name("Статус: Проверка GitHub...") end)
    end

    HTTP.Request("GET", SERVER_URL .. "/update", {}, function(res)
        if not res or not res.response then
            if ui_update_status then
                pcall(function() ui_update_status:Name("Статус: Сервер оффлайн (запустите elycde.exe)") end)
            end
            return
        end

        local msg = res.response:match('"message"%s*:%s*"([^"]+)"') or "Готово"
        local updated = res.response:match('"updated_files"%s*:%s*%[([^%]]+)%]')
        if updated and updated ~= "" then
            if ui_update_status then
                pcall(function() ui_update_status:Name("Статус: " .. msg) end)
            end
        else
            if ui_update_status then
                pcall(function() ui_update_status:Name("Статус: " .. msg) end)
            end
        end
    end)
end

local function url_encode(str)
    if not str then return "" end
    str = tostring(str)
    return (str:gsub("([^%w%-%_%.%~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

local function OpenBrowserUrl(url)
    pcall(function()
        Engine.RunScript(string.format("$.DispatchEvent('ExternalBrowserGoToURL', '%s')", url))
    end)
    HTTP.Request("GET", SERVER_URL .. "/open_url?url=" .. url_encode(url), {}, function() end)
    pcall(function()
        os.execute('cmd.exe /c start "" "' .. url .. '"')
    end)
end

local ui_btn_update = group_update:Button("🔄 Обновить скрипты (GitHub)", function()
    CheckUpdates()
end)
ui_btn_update:Unsafe(true)
ui_btn_update:ToolTip("Внимание: требуется запущенный сервер elycde.exe!\nПроверяет и скачивает обновления elycde.exe и скриптов с GitHub.")

local ui_btn_repo = group_update:Button("🌐 Открыть GitHub репозиторий", function()
    OpenBrowserUrl(GITHUB_REPO)
end)
ui_btn_repo:ToolTip("Открыть страницу https://github.com/elycde/umb в браузере")

-- Правая колонка: Сервер и Драйвер
local group_server = tab_main:Create("Сервер elycde.exe", side_right)
if not group_server or not group_server.Button then
    group_server = Menu.Create("Scripts", "elycde", "Настройки", "Общие", "Сервер elycde.exe")
end

local ui_server_status = group_server:Label("Сервер: Проверка...")
local ui_cable_status = group_server:Label("Микрофон: Поиск...")

local function UpdateServerStatus()
    HTTP.Request("GET", SERVER_URL .. "/ping", {}, function(res)
        if res and res.response and res.response:find('"running"') then
            local count = res.response:match('"sounds_count"%s*:%s*(%d+)') or "0"
            local cable_found = res.response:find('"cable_found"%s*:%s*true') ~= nil
            local cable_name = res.response:match('"cable_name"%s*:%s*"([^"]+)"') or "CABLE Input"

            if ui_server_status then
                pcall(function()
                    ui_server_status:Name("Сервер: Работает (" .. count .. " звуков)")
                    ui_server_status:Icon("\u{f00c}")
                end)
            end

            if ui_cable_status then
                pcall(function()
                    if cable_found then
                        ui_cable_status:Name("Микрофон: " .. cable_name .. " (OK)")
                        ui_cable_status:Icon("\u{f130}")
                    else
                        ui_cable_status:Name("Микрофон: VB-Cable не найден")
                        ui_cable_status:Icon("\u{f071}")
                    end
                end)
            end
        else
            if ui_server_status then
                pcall(function()
                    ui_server_status:Name("Сервер: Оффлайн (запустите elycde.exe)")
                    ui_server_status:Icon("\u{f057}")
                end)
            end
            if ui_cable_status then
                pcall(function()
                    ui_cable_status:Name("Микрофон: Ожидание сервера...")
                end)
            end
        end
    end)
end

local ui_btn_check = group_server:Button("Проверить статус", function()
    UpdateServerStatus()
end)

local ui_btn_kill = group_server:Button("Убить процесс сервера", function()
    HTTP.Request("GET", SERVER_URL .. "/kill", {}, function()
        if ui_server_status then
            pcall(function() ui_server_status:Name("Сервер: Остановлен") end)
        end
        if ui_cable_status then
            pcall(function() ui_cable_status:Name("Микрофон: Оффлайн") end)
        end
    end)
end)
ui_btn_kill:Unsafe(true)
ui_btn_kill:ToolTip("Внимание: требуется запущенный сервер elycde.exe!\nЗавершает работу фонового процесса сервера.")

-- Начальный опрос
UpdateServerStatus()

local next_ping_time = 0
function Settings.OnUpdate()
    local now = os.clock()
    if now >= next_ping_time then
        next_ping_time = now + 5.0
        UpdateServerStatus()
    end
end

return Settings
