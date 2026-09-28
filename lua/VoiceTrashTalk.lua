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
local tab_events = vtt_tab:Create("События и Звуки")
tab_events:Icon("\u{f028}")

local tab_volume = vtt_tab:Create("Громкость и Тесты")
tab_volume:Icon("\u{f013}")

local tab_chat = vtt_tab:Create("Чат и Насмешки")
tab_chat:Icon("\u{f086}")

-- ------------------------------------------------------------------------
-- Константы, пути и вспомогательные функции
-- ------------------------------------------------------------------------
local SERVER_URL = "http://127.0.0.1:8765"

local is_speaking = false
local stop_speak_time = 0
local last_kill_time = 0
local last_ingame_vol = -1
local next_ping_time = 0
local has_played_win = false

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
    "1.wav",
    "2.wav"
}

local SOUND_PRESETS_NONE = {
    "(Не выбран)",
    "1.wav",
    "2.wav"
}

local SOUND_MODES = {
    "🎲 Случайный из всей папки",
    "🎯 Один выбранный файл",
    "🔀 Пул из выбранных звуков"
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
-- TAB 1: События и Звуки
-- ------------------------------------------------------------------------

-- Левая колонка: 1. Убийство врага (Kill)
local group_kill = tab_events:Create("Убийство врага (Kill)", side_left)
local ui_enable = group_kill:Switch("Включить Voice TrashTalk", true, "\u{f00c}")
ui_enable:ToolTip("Главный выключатель войс-трэштока")

local ui_on_kill = group_kill:Switch("Войс при убийстве героя", true, "\u{f05b}")
ui_on_kill:ToolTip("Воспроизводить звук в микрофон при убийстве вражеского героя")

local ui_on_fb = group_kill:Switch("Особый звук на First Blood", true, "\u{f005}")
ui_on_fb:ToolTip("Воспроизводить отдельный звук при первой крови")

local ui_kill_mode = group_kill:Combo("Режим звука Kill", SOUND_MODES, 0)
ui_kill_mode:ToolTip("Случайный: рандом из всех файлов папки sounds.\nОдин файл: всегда играет выбранный звук.\nПул: случайный выбор только из выбранных слотов ниже.")

local ui_kill_file1 = group_kill:Combo("Файл при убийстве", SOUND_PRESETS, 0)
local ui_kill_file2 = group_kill:Combo("Пул: Доп. звук #2", SOUND_PRESETS_NONE, 0)
local ui_kill_file3 = group_kill:Combo("Пул: Доп. звук #3", SOUND_PRESETS_NONE, 0)
local ui_kill_file4 = group_kill:Combo("Пул: Доп. звук #4", SOUND_PRESETS_NONE, 0)

local ui_cooldown = group_kill:Slider("Кулдаун между звуками (сек)", 1, 20, 4, "%d сек")
ui_cooldown:ToolTip("Минимальный интервал между срабатываниями звуков")

-- Правая колонка: 2. Своя смерть (Death)
local group_death = tab_events:Create("Своя смерть (Death)", side_right)
local ui_on_death = group_death:Switch("Войс при своей смерти", false, "\u{f714}")
ui_on_death:ToolTip("Воспроизводить звук в микрофон при вашей гибели")

local ui_death_mode = group_death:Combo("Режим звука Death", SOUND_MODES, 0)
ui_death_mode:ToolTip("Случайный: рандом из всех файлов папки sounds.\nОдин файл: всегда играет выбранный звук.\nПул: случайный выбор только из выбранных слотов ниже.")

local ui_death_file1 = group_death:Combo("Файл при смерти", SOUND_PRESETS, 0)
local ui_death_file2 = group_death:Combo("Пул: Доп. звук #2", SOUND_PRESETS_NONE, 0)
local ui_death_file3 = group_death:Combo("Пул: Доп. звук #3", SOUND_PRESETS_NONE, 0)
local ui_death_file4 = group_death:Combo("Пул: Доп. звук #4", SOUND_PRESETS_NONE, 0)

-- Правая колонка: 3. Победа команды (Victory / Трон)
local group_win = tab_events:Create("Победа команды (Victory)", side_right)
local ui_on_win = group_win:Switch("Войс при сносе вражеского трона", true, "\u{f091}")
ui_on_win:ToolTip("Воспроизводить триумфальный звук при уничтожении вражеского Ancient")

local ui_win_mode = group_win:Combo("Режим звука Victory", SOUND_MODES, 0)
ui_win_mode:ToolTip("Случайный: рандом из всех файлов папки sounds.\nОдин файл: всегда играет выбранный звук.\nПул: случайный выбор только из выбранных слотов ниже.")

local ui_win_file1 = group_win:Combo("Файл при победе", SOUND_PRESETS, 0)
local ui_win_file2 = group_win:Combo("Пул: Доп. звук #2", SOUND_PRESETS_NONE, 0)
local ui_win_file3 = group_win:Combo("Пул: Доп. звук #3", SOUND_PRESETS_NONE, 0)
local ui_win_file4 = group_win:Combo("Пул: Доп. звук #4", SOUND_PRESETS_NONE, 0)

local ui_win_chat = group_win:Switch("Писать 'GG WP' в общий чат", true, "\u{f086}")

-- Настройка видимости / активности слотов в зависимости от режима
local function SetupModeCallback(mode_ctrl, s1, s2, s3, s4)
    if mode_ctrl and mode_ctrl.SetCallback then
        mode_ctrl:SetCallback(function()
            local m = mode_ctrl:Get() or 0
            if s1 and s1.Disabled then s1:Disabled(m == 0) end
            if s2 and s2.Disabled then s2:Disabled(m ~= 2) end
            if s3 and s3.Disabled then s3:Disabled(m ~= 2) end
            if s4 and s4.Disabled then s4:Disabled(m ~= 2) end
        end, true)
    end
end

SetupModeCallback(ui_kill_mode, ui_kill_file1, ui_kill_file2, ui_kill_file3, ui_kill_file4)
SetupModeCallback(ui_death_mode, ui_death_file1, ui_death_file2, ui_death_file3, ui_death_file4)
SetupModeCallback(ui_win_mode, ui_win_file1, ui_win_file2, ui_win_file3, ui_win_file4)

-- Левая колонка: 4. Управление звуками
local group_sound_manage = tab_events:Create("Файлы и Папка", side_left)
local ui_sound_now_playing = group_sound_manage:Label("Сейчас играет: Нет")

local ui_btn_refresh_sounds = group_sound_manage:Button("🔄 Обновить список звуков", function()
    RefreshSoundsList()
end)
ui_btn_refresh_sounds:ToolTip("Сканирует папку sounds и обновляет списки файлов во всех селекторах")

local ui_btn_open_folder = group_sound_manage:Button("📂 Открыть папку sounds", function()
    OpenSoundsFolder()
end)
ui_btn_open_folder:ToolTip("Открывает папку sounds в Проводнике Windows для добавления своих треков")

-- ------------------------------------------------------------------------
-- TAB 2: Громкость и Тесты
-- ------------------------------------------------------------------------

-- Левая колонка: Регулировка громкости
local group_volume = tab_volume:Create("Регулировка громкости", side_left)

local ui_vol_speaker = group_volume:Slider("Громкость в наушники (для себя)", 0, 100, 25, "%d%%")
ui_vol_speaker:ToolTip("Программное масштабирование звука для ваших наушников")

local ui_vol_mic = group_volume:Slider("Громкость в микрофон (в Доту)", 0, 100, 100, "%d%%")
ui_vol_mic:ToolTip("Громкость звука, отправляемого в виртуальный микрофон Доты (VB-Audio Cable)")

local ui_vol_ingame = group_volume:Slider("voice_scale (консоль Доты)", 0, 100, 100, "%d%%")
ui_vol_ingame:ToolTip("Регулирует консольную команду Dota 2 voice_scale (0.00 - 1.00)")

local ui_voicerecord_delay = group_volume:Slider("Буфер удержания микрофона (мс)", 50, 1500, 300, "%d мс")
ui_voicerecord_delay:ToolTip("Дополнительное время удержания +voicerecord после окончания трека, чтобы звук не обрывался")

-- Левая колонка: Инструкция
local group_guide = tab_volume:Create("Инструкция", side_left)
local ui_guide_step1 = group_guide:Label("1. Запустите elycde.exe")
ui_guide_step1:ToolTip("При старте elycde.exe сам проверит наличие VB-Audio Cable.\nЕсли драйвера нет — окно сразу предложит скачать его с официального сайта.")

local ui_guide_step2 = group_guide:Label("2. В Доте: CABLE Output")
ui_guide_step2:ToolTip("В настройках Доты 2 (Звук -> Устройство записи / Микрофон) выберите:\n«CABLE Output (VB-Audio Virtual Cable)».\nТогда войс-трэшток пойдет прямо в голосовой чат игры!")

-- Правая колонка: Тестирование
local group_tests = tab_volume:Create("Тестирование звуков", side_right)

local ui_btn_test_kill = group_tests:Button("Тест: Звук при убийстве (Kill)", function()
    PlayVoiceSound("kill", "all")
end)
ui_btn_test_kill:ToolTip("Воспроизводит звук убийства в наушники и микрофон Доты (+voicerecord)")

local ui_btn_test_death = group_tests:Button("Тест: Звук при смерти (Death)", function()
    PlayVoiceSound("death", "all")
end)
ui_btn_test_death:ToolTip("Воспроизводит звук при смерти в наушники и микрофон Доты (+voicerecord)")

local ui_btn_test_win = group_tests:Button("Тест: Звук победы (Victory)", function()
    PlayVoiceSound("victory", "all")
end)
ui_btn_test_win:ToolTip("Воспроизводит звук победы в наушники и микрофон Доты (+voicerecord)")

local ui_btn_test_mic_only = group_tests:Button("Только в микрофон Доты (+voicerecord)", function()
    PlayVoiceSound("kill", "only_mic")
end)
ui_btn_test_mic_only:ToolTip("Отправляет звук напрямую в виртуальный микрофон Доты без звука в наушниках")

local ui_btn_test_speaker_only = group_tests:Button("Только в наушники (для себя)", function()
    PlayVoiceSound("kill", "only_speaker")
end)
ui_btn_test_speaker_only:ToolTip("Воспроизводит звук только вам в наушники для комфортной настройки громкости")

local ui_btn_stop = group_tests:Button("Остановить всё (Stop)", function()
    StopAudioAndVoice()
end)
ui_btn_stop:ToolTip("Немедленно глушит звук и отпускает микрофон (-voicerecord)")

-- ------------------------------------------------------------------------
-- TAB 3: Чат и Насмешки
-- ------------------------------------------------------------------------
local group_chat = tab_chat:Create("Текстовый чат при килле", side_left)
local ui_chat_phrase = group_chat:Switch("Писать фразу в чат", true, "\u{f086}")
local ui_chat_all = group_chat:Switch("В общий чат (All Chat)", true, "\u{f0ac}")
local ui_chat_custom = group_chat:Input("Своя фраза (пусто = случайная)", "")

local group_taunt = tab_chat:Create("Насмешки героя", side_right)
local ui_hero_laugh = group_taunt:Switch("Смех героя (dota_player_laugh)", true, "\u{f118}")
local ui_hero_taunt = group_taunt:Switch("Таунт героя (dota_taunt)", false, "\u{f004}")

-- ------------------------------------------------------------------------
-- Вспомогательная логика выбора звука для событий
-- ------------------------------------------------------------------------
local function GetEventSound(event_type)
    local mode = 0
    local s1, s2, s3, s4 = nil, nil, nil, nil

    if event_type == "kill" or event_type == "firstblood" then
        mode = (ui_kill_mode and ui_kill_mode:Get()) or 0
        s1, s2, s3, s4 = ui_kill_file1, ui_kill_file2, ui_kill_file3, ui_kill_file4
    elseif event_type == "death" then
        mode = (ui_death_mode and ui_death_mode:Get()) or 0
        s1, s2, s3, s4 = ui_death_file1, ui_death_file2, ui_death_file3, ui_death_file4
    elseif event_type == "victory" then
        mode = (ui_win_mode and ui_win_mode:Get()) or 0
        s1, s2, s3, s4 = ui_win_file1, ui_win_file2, ui_win_file3, ui_win_file4
    end

    -- 0: Случайный из всей папки sounds
    if mode == 0 then
        return nil
    end

    -- 1: Один конкретный звук
    if mode == 1 and s1 then
        local idx = (s1:Get() or 0) + 1
        local file = SOUND_PRESETS[idx]
        if file and file ~= "" and not file:find("^%(") then
            return file
        end
        return nil
    end

    -- 2: Пул из выбранных звуков (рандом из слотов 1-4)
    if mode == 2 then
        local pool = {}
        local function check(ctrl, list)
            if ctrl then
                local idx = (ctrl:Get() or 0) + 1
                local item = list[idx]
                if item and item ~= "" and not item:find("^%(") and item ~= "(Не выбран)" then
                    table.insert(pool, item)
                end
            end
        end

        check(s1, SOUND_PRESETS)
        check(s2, SOUND_PRESETS_NONE)
        check(s3, SOUND_PRESETS_NONE)
        check(s4, SOUND_PRESETS_NONE)

        if #pool > 0 then
            return pool[math.random(1, #pool)]
        end
    end

    return nil
end

-- ------------------------------------------------------------------------
-- Функции взаимодействия с сервером
-- ------------------------------------------------------------------------
UpdateServerStatus = function()
    HTTP.Request("GET", SERVER_URL .. "/ping", {}, function(res)
        if res and res.response and res.response:find('"running"') then
            RefreshSoundsList()
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

        SOUND_PRESETS_NONE = { "(Не выбран)" }
        for _, f in ipairs(new_list) do
            table.insert(SOUND_PRESETS_NONE, f)
        end

        local function UpdateCombo(ctrl, items)
            if ctrl and ctrl.Update then
                pcall(function()
                    local cur = ctrl:Get() or 0
                    ctrl:Update(items)
                    if cur >= #items then cur = 0 end
                    ctrl:Set(cur)
                end)
            end
        end

        UpdateCombo(ui_kill_file1, SOUND_PRESETS)
        UpdateCombo(ui_kill_file2, SOUND_PRESETS_NONE)
        UpdateCombo(ui_kill_file3, SOUND_PRESETS_NONE)
        UpdateCombo(ui_kill_file4, SOUND_PRESETS_NONE)

        UpdateCombo(ui_death_file1, SOUND_PRESETS)
        UpdateCombo(ui_death_file2, SOUND_PRESETS_NONE)
        UpdateCombo(ui_death_file3, SOUND_PRESETS_NONE)
        UpdateCombo(ui_death_file4, SOUND_PRESETS_NONE)

        UpdateCombo(ui_win_file1, SOUND_PRESETS)
        UpdateCombo(ui_win_file2, SOUND_PRESETS_NONE)
        UpdateCombo(ui_win_file3, SOUND_PRESETS_NONE)
        UpdateCombo(ui_win_file4, SOUND_PRESETS_NONE)

        if ui_sound_now_playing then
            pcall(function()
                ui_sound_now_playing:Name(string.format("Файлов в папке: %d", #new_list))
            end)
        end

        if callback then callback() end
    end)
end

KillServerExe = function()
    HTTP.Request("GET", SERVER_URL .. "/kill", {}, function()
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

    HTTP.Request("GET", SERVER_URL .. "/open_folder", {}, function(res)
        if res and res.response and res.response:find('"opened"') then
            if ui_sound_now_playing then
                pcall(function() ui_sound_now_playing:Name("✅ Папка sounds открыта") end)
            end
        end
    end)

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

    local chosen_file = GetEventSound(event_type)
    if chosen_file and chosen_file ~= "" and chosen_file ~= "(Папка sounds пуста)" then
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
    elseif event_type == "victory" and not is_test then
        if ui_win_chat and ui_win_chat:Get() then
            Engine.ExecuteCommand('say "GG WP"')
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
    if not Engine.IsInGame() then
        has_played_win = false
    end

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

    -- 1. Снос вражеского трона (Победа)
    local target_name = ""
    pcall(function()
        if NPC and NPC.GetUnitName then
            target_name = NPC.GetUnitName(data.target) or ""
        end
    end)

    if (target_name == "npc_dota_goodguys_fort" or target_name == "npc_dota_badguys_fort") and not has_played_win then
        if not Entity.IsSameTeam(my_hero, data.target) then
            has_played_win = true
            if ui_on_win and ui_on_win:Get() then
                PlayVoiceSound("victory", false)
            end
            return
        end
    end

    -- 2. Своя смерть
    if ui_on_death:Get() and data.target == my_hero then
        local now = os.clock()
        local cd = (ui_cooldown and ui_cooldown:Get()) or 4
        if (now - last_kill_time) >= cd then
            last_kill_time = now
            PlayVoiceSound("death", false)
        end
        return
    end

    -- 3. Убийство врага
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
