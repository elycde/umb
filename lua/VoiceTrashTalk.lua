-- ========================================================================
-- elycde: Voice TrashTalk Companion
-- Автоматический войс-трэшток в голосовой чат Доты 2 при событиях
-- ========================================================================

local VoiceTrashTalk = {}

-- ------------------------------------------------------------------------
-- Меню: Scripts -> elycde -> Voice TrashTalk
-- ------------------------------------------------------------------------
local vtt_tab = Menu.Create("Scripts", "elycde", "Voice TrashTalk")
vtt_tab:Icon("\u{f028}")

local side_left = (Enum and Enum.GroupSide and Enum.GroupSide.Left) or nil
local side_right = (Enum and Enum.GroupSide and Enum.GroupSide.Right) or nil

-- Подвкладки
local tab_main = vtt_tab:Create("Основное")
tab_main:Icon("\u{f013}")

local tab_chat = vtt_tab:Create("Чат и Насмешки")
tab_chat:Icon("\u{f086}")

-- ------------------------------------------------------------------------
-- ------------------------------------------------------------------------
-- Константы, пути и вспомогательные функции
-- ------------------------------------------------------------------------
local SERVER_URL = "http://127.0.0.1:8765"

local is_speaking = false
local stop_speak_time = 0
local last_kill_time = 0
local last_ingame_vol = -1
local next_ping_time = 0

local function GetScriptDir()
    local ok, info = pcall(function() return debug.getinfo(1, "S") end)
    if ok and info and type(info.source) == "string" then
        local src = info.source
        if src:sub(1, 1) == "@" then src = src:sub(2) end
        src = src:gsub("/", "\\")
        local dir = src:match("^(.*)\\[^\\]+$")
        if dir and dir ~= "" then return dir end
    end
    return "scripts"
end

local SOUND_PRESETS = {
    "(Загрузка списка...)"
}

local PHRASES_KILL = {
    "?",
    "ez",
    "куда ты лезешь?",
    "отдохни в таверне",
    "слабо сыграно",
    "минус бездарь",
    "потренируйся с ботами",
    "gg wp",
    "на базу",
    "не чувствую",
    "слишком легко"
}

local function GetRandomKillPhrase()
    return PHRASES_KILL[math.random(1, #PHRASES_KILL)]
end

-- Forward declarations
local UpdateServerStatus = function() end
local RefreshSoundsList = function(cb) end
local KillServerExe = function() end
local StopAudioAndVoice = function() end
local OpenSoundsFolder = function() end
local PlayVoiceSound = function(event_type, test_mode_flag) end

-- ------------------------------------------------------------------------
-- TAB 1: Основное (Настройки, Звуки, Громкость, Тесты, Сервер)
-- ------------------------------------------------------------------------

-- Левая колонка: 1. Триггеры в игре
local group_main = tab_main:Create("Триггеры в игре", side_left)
local ui_enable = group_main:Switch("Включить Voice TrashTalk", true, "\u{f00c}")
ui_enable:ToolTip("Включает или выключает автоматический войс-трэшток")

local ui_on_kill = group_main:Switch("Войс при убийстве врага", true, "\u{f05b}")
ui_on_kill:ToolTip("Воспроизводить звук в микрофон при убийстве вражеского героя")

local ui_on_fb = group_main:Switch("Особый звук на First Blood", true, "\u{f005}")
ui_on_fb:ToolTip("Воспроизводить отдельный звук при первой крови")

local ui_on_death = group_main:Switch("Звук при своей смерти", false, "\u{f714}")
ui_on_death:ToolTip("Воспроизводить звук при вашей смерти")

local ui_cooldown = group_main:Slider("Кулдаун между фразами (сек)", 1, 20, 4, "%d сек")
ui_cooldown:ToolTip("Минимальный интервал между срабатываниями звуков")

-- Левая колонка: 2. Выбор звука
local group_sound_select = tab_main:Create("Выбор звука", side_left)
local ui_sound_mode = group_sound_select:Combo("Режим воспроизведения", {
    "Случайный из папки sounds",
    "Выбранный из списка"
}, 0)

local ui_sound_file = group_sound_select:Combo("Файл из списка", SOUND_PRESETS, 0)
local ui_sound_now_playing = group_sound_select:Label("Сейчас играет: Нет")

local ui_btn_refresh_sounds = group_sound_select:Button("🔄 Обновить список звуков", function()
    RefreshSoundsList()
end)
ui_btn_refresh_sounds:ToolTip("Сканирует папку sounds и мгновенно обновляет выпадающий список файлов")

local ui_btn_open_folder = group_sound_select:Button("📂 Открыть папку sounds", function()
    OpenSoundsFolder()
end)
ui_btn_open_folder:ToolTip("Открывает папку sounds в Проводнике Windows (работает только при запущенном elycde.exe)")

-- Левая колонка: 3. Сервер и Драйвер
local group_server = tab_main:Create("Сервер и Драйвер", side_left)
local ui_server_status = group_server:Label("Сервер: Проверка...")
local ui_cable_status = group_server:Label("Микрофон: Поиск...")

local ui_btn_check = group_server:Button("Проверить статус", function()
    UpdateServerStatus()
end)

local ui_btn_kill = group_server:Button("Убить процесс сервера", function()
    KillServerExe()
end)

-- Левая колонка: 4. Инструкция
local group_guide = tab_main:Create("Инструкция", side_left)
local ui_guide_step1 = group_guide:Label("1. Запустите elycde.exe")
ui_guide_step1:ToolTip("При старте elycde.exe сам проверит наличие VB-Audio Cable.\nЕсли драйвера нет — окно сразу предложит скачать его с официального сайта.")

local ui_guide_step2 = group_guide:Label("2. В Доте: CABLE Output")
ui_guide_step2:ToolTip("В настройках Доты 2 (Звук -> Устройство записи / Микрофон) выберите:\n«CABLE Output (VB-Audio Virtual Cable)».\nТогда войс-трэшток пойдет прямо в голосовой чат игры!")

-- Правая колонка: 4. Регулировка громкости
local group_volume = tab_main:Create("Регулировка громкости", side_right)

local ui_vol_speaker = group_volume:Slider("Громкость в наушники (для себя)", 0, 100, 25, "%d%%")
ui_vol_speaker:ToolTip("Реальное программное масштабирование сэмплов звука для ваших наушников (5% = очень тихо, 100% = макс)")

local ui_vol_mic = group_volume:Slider("Громкость в микрофон (в Доту)", 0, 100, 100, "%d%%")
ui_vol_mic:ToolTip("Громкость звука, отправляемого в виртуальный микрофон Доты (VB-Audio Virtual Cable)")

local ui_vol_ingame = group_volume:Slider("voice_scale (консоль Доты)", 0, 100, 100, "%d%%")
ui_vol_ingame:ToolTip("Регулирует консольную команду Dota 2 voice_scale (0.00 - 1.00)")

local ui_voicerecord_delay = group_volume:Slider("Буфер удержания микрофона (мс)", 50, 1500, 300, "%d мс")
ui_voicerecord_delay:ToolTip("Дополнительное время удержания +voicerecord после окончания трека, чтобы звук не обрывался")

-- Правая колонка: 5. Тестирование
local group_tests = tab_main:Create("Тестирование", side_right)

local ui_btn_test_all = group_tests:Button("Звук + Войс в игре", function()
    PlayVoiceSound("test", "all")
end)
ui_btn_test_all:ToolTip("Играет звук в наушники, передает в виртуальный микрофон Доты и зажимает +voicerecord")

local ui_btn_test_mic_only = group_tests:Button("Только в микрофон Доты", function()
    PlayVoiceSound("test", "only_mic")
end)
ui_btn_test_mic_only:ToolTip("Отправляет звук напрямую в виртуальный микрофон Доты и зажимает +voicerecord без звука в наушниках")

local ui_btn_test_speaker_only = group_tests:Button("Только в наушники (для себя)", function()
    PlayVoiceSound("test", "only_speaker")
end)
ui_btn_test_speaker_only:ToolTip("Воспроизводит звук только вам в наушники, чтобы комфортно настроить ползунок громкости")

local ui_btn_test_mic_raw = group_tests:Button("Проверка микрофона (+voicerecord 2 сек)", function()
    Engine.ExecuteCommand("+voicerecord")
    is_speaking = true
    stop_speak_time = os.clock() + 2.0
    if ui_sound_now_playing then
        pcall(function() ui_sound_now_playing:Name("Микрофон: +voicerecord (2.0с)") end)
    end
end)
ui_btn_test_mic_raw:ToolTip("Включает микрофон Доты на 2 секунды без музыки для проверки значка голоса")

local ui_btn_stop = group_tests:Button("Остановить всё (Stop)", function()
    StopAudioAndVoice()
end)
ui_btn_stop:ToolTip("Немедленно глушит звук и отпускает микрофон (-voicerecord)")

-- ------------------------------------------------------------------------
-- TAB 2: Чат и Насмешки
-- ------------------------------------------------------------------------
local group_chat = tab_chat:Create("Текстовый чат при килле", side_left)
local ui_chat_phrase = group_chat:Switch("Писать фразу в чат", true, "\u{f086}")
local ui_chat_all = group_chat:Switch("В общий чат (All Chat)", true, "\u{f0ac}")
local ui_chat_custom = group_chat:Input("Своя фраза (пусто = случайная)", "")

local group_taunt = tab_chat:Create("Насмешки героя", side_right)
local ui_hero_laugh = group_taunt:Switch("Смех героя (dota_player_laugh)", true, "\u{f118}")
local ui_hero_taunt = group_taunt:Switch("Таунт героя (dota_taunt)", false, "\u{f004}")

-- ------------------------------------------------------------------------
-- Функции взаимодействия с сервером
-- ------------------------------------------------------------------------
UpdateServerStatus = function()
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

            RefreshSoundsList()
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

RefreshSoundsList = function(callback)
    HTTP.Request("GET", SERVER_URL .. "/list", {}, function(res)
        if not res or not res.response then return end

        local new_list = {}
        local files_part = res.response:match('"files"%s*:%s*%[([^%]]+)%]')
        if files_part then
            for item in files_part:gmatch('"([^"]+)"') do
                table.insert(new_list, item)
            end
        end

        if #new_list > 0 then
            SOUND_PRESETS = new_list
        else
            SOUND_PRESETS = { "(Папка sounds пуста)" }
        end

        if ui_sound_file and ui_sound_file.Update then
            pcall(function()
                local cur = ui_sound_file:Get() or 0
                ui_sound_file:Update(SOUND_PRESETS)
                if cur >= #SOUND_PRESETS then cur = 0 end
                ui_sound_file:Set(cur)
            end)
        end

        if ui_sound_now_playing then
            pcall(function()
                ui_sound_now_playing:Name(string.format("Файлов в папке: %d", #new_list))
            end)
        end

        if callback then callback() end
    end)
end

KillServerExe = function()
    HTTP.Request("GET", SERVER_URL .. "/kill", {}, function(res)
        if ui_server_status then
            pcall(function() ui_server_status:Name("Сервер: Остановлен") end)
        end
        if ui_cable_status then
            pcall(function() ui_cable_status:Name("Микрофон: Оффлайн") end)
        end
        StopAudioAndVoice()
    end)
end

StopAudioAndVoice = function()
    HTTP.Request("GET", SERVER_URL .. "/stop", {}, function() end)
    if is_speaking then
        Engine.ExecuteCommand("-voicerecord")
        is_speaking = false
    end
    if ui_sound_now_playing then
        pcall(function() ui_sound_now_playing:Name("Сейчас играет: Нет") end)
    end
end

OpenSoundsFolder = function()
    if ui_sound_now_playing then
        pcall(function() ui_sound_now_playing:Name("📂 Открываем папку sounds...") end)
    end

    -- 1. Запрос серверу (откроет и выведет окно Проводника на передний план над игрой)
    HTTP.Request("GET", SERVER_URL .. "/open_folder", {}, function(res)
        if res and res.response and res.response:find('"opened"') then
            if ui_sound_now_playing then
                pcall(function() ui_sound_now_playing:Name("✅ Папка sounds открыта") end)
            end
        end
    end)

    -- 2. Прямой запуск через Shell Windows (100% надежность)
    local script_dir = GetScriptDir()
    if script_dir then
        local sounds_dir = script_dir .. "\\VoiceTrashTalk\\sounds"
        pcall(function()
            os.execute('if not exist "' .. sounds_dir .. '" mkdir "' .. sounds_dir .. '" >nul 2>&1')
            os.execute('explorer.exe "' .. sounds_dir .. '"')
        end)
    end
end

PlayVoiceSound = function(event_type, test_mode_flag)
    local is_test = (test_mode_flag ~= nil and test_mode_flag ~= false)
    if not is_test and not ui_enable:Get() then return end

    local spk_vol = (ui_vol_speaker and ui_vol_speaker:Get()) or 25
    local mic_vol = (ui_vol_mic and ui_vol_mic:Get()) or 100

    local url = string.format("%s/play?speaker_vol=%d&mic_vol=%d", SERVER_URL, spk_vol, mic_vol)

    if test_mode_flag == "only_mic" then
        url = url .. "&only_mic=1"
    elseif test_mode_flag == "only_speaker" then
        url = url .. "&only_speaker=1"
    end

    local mode = (ui_sound_mode and ui_sound_mode:Get()) or 0
    local chosen_file = nil

    if mode == 1 then
        local idx = ((ui_sound_file and ui_sound_file:Get()) or 0) + 1
        chosen_file = SOUND_PRESETS[idx] or SOUND_PRESETS[1]
    end

    if chosen_file then
        url = url .. "&file=" .. chosen_file
    elseif event_type then
        url = url .. "&event=" .. event_type
    end

    HTTP.Request("GET", url, {}, function(res)
        if not res or not res.response then
            if ui_sound_now_playing then
                pcall(function() ui_sound_now_playing:Name("Ошибка: Сервер оффлайн") end)
            end
            return
        end

        local filename = res.response:match('"file"%s*:%s*"([^"]+)"') or "Звук"
        local dur_ms = tonumber(res.response:match('"duration_ms"%s*:%s*(%d+)')) or 2000

        if ui_sound_now_playing then
            pcall(function()
                ui_sound_now_playing:Name("Сейчас играет: " .. filename .. " (" .. string.format("%.1f", dur_ms / 1000) .. "с)")
            end)
        end

        if test_mode_flag ~= "only_speaker" then
            local extra_delay = (ui_voicerecord_delay and ui_voicerecord_delay:Get()) or 300
            local total_sec = (dur_ms + extra_delay) / 1000.0

            Engine.ExecuteCommand("+voicerecord")
            is_speaking = true
            stop_speak_time = os.clock() + total_sec
        end
    end)

    if (event_type == "kill" or event_type == "firstblood") and not is_test then
        if ui_hero_laugh and ui_hero_laugh:Get() then
            Engine.ExecuteCommand("dota_player_laugh")
        end

        if ui_hero_taunt and ui_hero_taunt:Get() then
            Engine.ExecuteCommand("dota_taunt")
        end

        if ui_chat_phrase and ui_chat_phrase:Get() then
            local phrase = ""
            local custom = ui_chat_custom and ui_chat_custom:Get() or ""
            if custom and custom ~= "" then
                phrase = custom
            else
                phrase = GetRandomKillPhrase()
            end
            local channel = (ui_chat_all and ui_chat_all:Get()) and "say" or "say_team"
            Engine.ExecuteCommand(channel .. ' "' .. phrase .. '"')
        end
    end
end

-- Инициализация слушателя событий
pcall(function()
    if Event and Event.AddListener then
        Event.AddListener("dota_player_kill")
    end
end)

-- Начальный опрос статуса
UpdateServerStatus()

-- ------------------------------------------------------------------------
-- Callbacks чита
-- ------------------------------------------------------------------------
function VoiceTrashTalk.OnUpdate()
    if ui_vol_ingame then
        local cur_vol = ui_vol_ingame:Get()
        if cur_vol ~= last_ingame_vol then
            last_ingame_vol = cur_vol
            Engine.ExecuteCommand(string.format("voice_scale %.2f", cur_vol / 100.0))
        end
    end

    local now = os.clock()
    if now >= next_ping_time then
        next_ping_time = now + 5.0
        UpdateServerStatus()
    end

    if is_speaking and os.clock() >= stop_speak_time then
        Engine.ExecuteCommand("-voicerecord")
        is_speaking = false
        if ui_sound_now_playing then
            pcall(function() ui_sound_now_playing:Name("Сейчас играет: Нет") end)
        end
    end
end

function VoiceTrashTalk.OnFireEventClient(data)
    if not ui_enable:Get() or not ui_on_kill:Get() then return end
    if not data or not data.event then return end

    if data.name == "dota_player_kill" then
        local my_player = Players.GetLocal()
        if not my_player then return end

        local my_pid = Player.GetPlayerID(my_player)
        local killer_pid = Event.GetInt(data.event, "killer1_player_id") or Event.GetInt(data.event, "killer_player_id")

        if killer_pid == my_pid then
            local now = os.clock()
            local cd = (ui_cooldown and ui_cooldown:Get()) or 4
            if (now - last_kill_time) >= cd then
                last_kill_time = now
                local is_fb = false
                pcall(function()
                    is_fb = Event.GetBool(data.event, "first_blood") or (Event.GetInt(data.event, "first_blood") == 1)
                end)
                if is_fb and ui_on_fb:Get() then
                    PlayVoiceSound("firstblood", false)
                else
                    PlayVoiceSound("kill", false)
                end
            end
        end
    end
end

function VoiceTrashTalk.OnEntityKilled(data)
    if not ui_enable:Get() then return end
    if not data or not data.target then return end

    local my_hero = Heroes.GetLocal()
    if not my_hero then return end

    if ui_on_death:Get() and data.target == my_hero then
        local now = os.clock()
        local cd = (ui_cooldown and ui_cooldown:Get()) or 4
        if (now - last_kill_time) >= cd then
            last_kill_time = now
            PlayVoiceSound("death", false)
        end
        return
    end

    if ui_on_kill:Get() and data.source == my_hero and NPC.IsHero(data.target) and not Entity.IsSameTeam(my_hero, data.target) then
        local now = os.clock()
        local cd = (ui_cooldown and ui_cooldown:Get()) or 4
        if (now - last_kill_time) >= cd then
            last_kill_time = now
            PlayVoiceSound("kill", false)
        end
    end
end

function VoiceTrashTalk.OnScriptUnload()
    if is_speaking then
        Engine.ExecuteCommand("-voicerecord")
        is_speaking = false
    end
end

return VoiceTrashTalk
