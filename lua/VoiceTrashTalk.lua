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
local last_death_time = 0
local last_ingame_vol = -1
local next_ping_time = 0
local has_played_win = false

local function GetScriptDir()
    local umbrella_dir = "C:\\Umbrella\\scripts"
    local f = io.open(umbrella_dir .. "\\VoiceTrashTalk.lua", "r")
    if f then
        f:close()
        return umbrella_dir
    end

    local ok, info = pcall(function() return debug.getinfo(1, "S") end)
    if ok and info and type(info.source) == "string" then
        local src = info.source
        if src:sub(1, 1) == "@" then src = src:sub(2) end
        src = src:gsub("/", "\\")
        local dir = src:match("^(.*)\\[^\\]+$")
        if dir and dir ~= "" then return dir end
    end
    return umbrella_dir
end

local function LoadConfigTable()
    local dir = GetScriptDir()
    if not dir then return {} end
    local path = dir .. "\\VoiceTrashTalk\\vtt_config.json"
    local f = io.open(path, "r")
    if not f then return {} end
    local content = f:read("*a")
    f:close()
    if not content or content == "" then return {} end
    local t = {}
    for k, v in content:gmatch('"([^"]+)"%s*:%s*%[([^%]]*)%]') do
        local arr = {}
        for item in v:gmatch('"([^"]+)"') do
            table.insert(arr, item)
        end
        t[k] = arr
    end
    return t
end

local function SaveConfigTable(key, list)
    local dir = GetScriptDir()
    if not dir then return end
    local path = dir .. "\\VoiceTrashTalk\\vtt_config.json"
    local ok, existing = pcall(LoadConfigTable)
    if not ok or type(existing) ~= "table" then existing = {} end
    existing[key] = list

    local parts = {}
    for k, arr in pairs(existing) do
        local items = {}
        for _, it in ipairs(arr) do
            table.insert(items, string.format("%q", it))
        end
        table.insert(parts, string.format('  "%s": [%s]', k, table.concat(items, ", ")))
    end
    local json_str = "{\n" .. table.concat(parts, ",\n") .. "\n}"
    local f = io.open(path, "w")
    if f then
        f:write(json_str)
        f:close()
    end
end

local function GetSavedList(key)
    if Config and Config.ReadString then
        local ok, raw = pcall(function() return Config.ReadString("elycde_vtt", key, "") end)
        if ok and raw and raw ~= "" then
            local list = {}
            for item in raw:gmatch("([^|]+)") do
                table.insert(list, item)
            end
            if #list > 0 then return list end
        end
    end
    local t = LoadConfigTable()
    return t[key] or {}
end

local function SetSavedList(key, list)
    if not list then list = {} end
    if Config and Config.WriteString then
        pcall(function()
            Config.WriteString("elycde_vtt", key, table.concat(list, "|"))
        end)
    end
    pcall(function() SaveConfigTable(key, list) end)
end

local function url_encode(str)
    if not str then return "" end
    str = tostring(str)
    return (str:gsub("([^%w%-%_%.%~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

local GITHUB_REPO = "https://github.com/elycde/umb"

local function OpenBrowserUrl(url)
    pcall(function()
        Engine.RunScript(string.format("$.DispatchEvent('ExternalBrowserGoToURL', '%s')", url))
    end)
    HTTP.Request("GET", SERVER_URL .. "/open_url?url=" .. url_encode(url), {}, function() end)
    pcall(function()
        os.execute('cmd.exe /c start "" "' .. url .. '"')
    end)
end

local DEFAULT_SOUND_PRESETS = {
    "1.wav",
    "2.wav",
    "втащил в соляного.wav",
    "гимн папича.mp3",
    "Идите нахуй пидорасы Папич.wav",
    "легчайшая для величайшего.mp3",
    "НЫАААА.mp3",
    "отлетаешь очередняра.mp3",
    "Папич - кто то сомневается.mp3",
    "Папич - ЧинЧопа.mp3",
    "Папич Ненавижу доту.mp3",
    "Папич очередняра запилил уебка.mp3",
    "Папич умер из за разрабов.mp3",
    "Папича  НЫЫЫЫААААА.mp3",
    "у меня задержка в развитии.mp3",
    "хелп.mp3",
    "что я сделал.mp3"
}

local function LoadCachedSoundPresets()
    local dir = GetScriptDir()
    if not dir then return DEFAULT_SOUND_PRESETS end
    local path = dir .. "\\VoiceTrashTalk\\sounds_cache.json"
    local f = io.open(path, "r")
    if f then
        local content = f:read("*a")
        f:close()
        if content and content ~= "" then
            local list = {}
            for item in content:gmatch('"([^"]+)"') do
                table.insert(list, item)
            end
            if #list > 0 then return list end
        end
    end
    return DEFAULT_SOUND_PRESETS
end

local function SaveCachedSoundPresets(list)
    local dir = GetScriptDir()
    if not dir or not list then return end
    local path = dir .. "\\VoiceTrashTalk\\sounds_cache.json"
    local items = {}
    for _, it in ipairs(list) do
        table.insert(items, string.format("%q", it))
    end
    local json_str = "[\n  " .. table.concat(items, ",\n  ") .. "\n]"
    local f = io.open(path, "w")
    if f then
        f:write(json_str)
        f:close()
    end
end

local SOUND_PRESETS = LoadCachedSoundPresets()

local SOUND_MODES = {
    "Случайный из всех",
    "Выбранные из списка"
}

local function SetVisible(ctrl, show)
    if not ctrl then return end
    pcall(function()
        if ctrl.Visible then ctrl:Visible(show == true) end
    end)
end

local function CreateMultiControl(group, name, items, default_enabled)
    if not group then return nil end
    local ctrl = nil
    if group.MultiCombo then
        local ok, res = pcall(function()
            return group:MultiCombo(name, items or {}, default_enabled or {})
        end)
        if ok and res then ctrl = res end
    end
    if not ctrl and group.MultiSelect then
        local opts = {}
        local def_map = {}
        for _, d in ipairs(default_enabled or {}) do def_map[d] = true end
        for _, it in ipairs(items or {}) do
            table.insert(opts, { it, "", def_map[it] == true })
        end
        local ok, res = pcall(function()
            return group:MultiSelect(name, opts, false)
        end)
        if ok and res then ctrl = res end
    end
    return ctrl
end

local function UpdateMultiControl(ctrl, new_items, saved_key)
    if not ctrl then return end
    pcall(function()
        local prev_enabled = {}
        if ctrl.ListEnabled then
            local ok, list = pcall(function() return ctrl:ListEnabled() end)
            if ok and list and type(list) == "table" and #list > 0 then
                for _, s in ipairs(list) do
                    prev_enabled[s] = true
                end
            end
        end

        if saved_key then
            local saved = GetSavedList(saved_key)
            if saved and type(saved) == "table" then
                for _, s in ipairs(saved) do
                    prev_enabled[s] = true
                end
            end
        end

        local enabled_list = {}
        for _, item in ipairs(new_items) do
            if prev_enabled[item] then
                table.insert(enabled_list, item)
            end
        end

        local ok_combo = pcall(function()
            ctrl:Update(new_items, enabled_list)
        end)
        if not ok_combo then
            local opts = {}
            for _, item in ipairs(new_items) do
                table.insert(opts, { item, "", prev_enabled[item] == true })
            end
            pcall(function()
                ctrl:Update(opts, false, true)
            end)
        end
    end)
end

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
ui_kill_mode:ToolTip("Случайный: рандом из всех файлов папки sounds.\nВыбранные: выбор одного или нескольких треков галочками из списка ниже.")

local saved_kill_sounds = GetSavedList("kill_sounds")
local ui_kill_sounds = CreateMultiControl(group_kill, "Звуки при убийстве", SOUND_PRESETS, saved_kill_sounds)
if ui_kill_sounds then
    pcall(function() ui_kill_sounds:Icon("\u{f028}") end)
    pcall(function() ui_kill_sounds:ToolTip("Выберите треки галочками для убийства. Если выбрано несколько, играет случайный из них.") end)
    pcall(function()
        if ui_kill_sounds.SetCallback then
            ui_kill_sounds:SetCallback(function()
                if ui_kill_sounds.ListEnabled then
                    local ok, list = pcall(function() return ui_kill_sounds:ListEnabled() end)
                    if ok and list and type(list) == "table" then
                        SetSavedList("kill_sounds", list)
                    end
                end
            end)
        end
    end)
end

local ui_cooldown = group_kill:Slider("Кулдаун между звуками (сек)", 1, 20, 4, "%d сек")
ui_cooldown:ToolTip("Минимальный интервал между срабатываниями звуков")

-- Правая колонка: 2. Своя смерть (Death)
local group_death = tab_events:Create("Своя смерть (Death)", side_right)
local ui_on_death = group_death:Switch("Войс при своей смерти", false, "\u{f714}")
ui_on_death:ToolTip("Воспроизводить звук в микрофон при вашей гибели")

local ui_death_mode = group_death:Combo("Режим звука Death", SOUND_MODES, 0)
ui_death_mode:ToolTip("Случайный: рандом из всех файлов папки sounds.\nВыбранные: выбор одного или нескольких треков галочками из списка ниже.")

local saved_death_sounds = GetSavedList("death_sounds")
local ui_death_sounds = CreateMultiControl(group_death, "Звуки при смерти", SOUND_PRESETS, saved_death_sounds)
if ui_death_sounds then
    pcall(function() ui_death_sounds:Icon("\u{f714}") end)
    pcall(function() ui_death_sounds:ToolTip("Выберите треки галочками для своей смерти. Если выбрано несколько, играет случайный из них.") end)
    pcall(function()
        if ui_death_sounds.SetCallback then
            ui_death_sounds:SetCallback(function()
                if ui_death_sounds.ListEnabled then
                    local ok, list = pcall(function() return ui_death_sounds:ListEnabled() end)
                    if ok and list and type(list) == "table" then
                        SetSavedList("death_sounds", list)
                    end
                end
            end)
        end
    end)
end

-- Правая колонка: 3. Победа команды (Victory / Трон)
local group_win = tab_events:Create("Победа команды (Victory)", side_right)
local ui_on_win = group_win:Switch("Войс при сносе вражеского трона", true, "\u{f091}")
ui_on_win:ToolTip("Воспроизводить триумфальный звук при уничтожении вражеского Ancient")

local ui_win_mode = group_win:Combo("Режим звука Victory", SOUND_MODES, 0)
ui_win_mode:ToolTip("Случайный: рандом из всех файлов папки sounds.\nВыбранные: выбор одного или нескольких треков галочками из списка ниже.")

local saved_win_sounds = GetSavedList("win_sounds")
local ui_win_sounds = CreateMultiControl(group_win, "Звуки при победе", SOUND_PRESETS, saved_win_sounds)
if ui_win_sounds then
    pcall(function() ui_win_sounds:Icon("\u{f091}") end)
    pcall(function() ui_win_sounds:ToolTip("Выберите треки галочками при победе команды. Если выбрано несколько, играет случайный из них.") end)
    pcall(function()
        if ui_win_sounds.SetCallback then
            ui_win_sounds:SetCallback(function()
                if ui_win_sounds.ListEnabled then
                    local ok, list = pcall(function() return ui_win_sounds:ListEnabled() end)
                    if ok and list and type(list) == "table" then
                        SetSavedList("win_sounds", list)
                    end
                end
            end)
        end
    end)
end

-- Левая колонка: 4. Управление звуками
local group_sound_manage = tab_events:Create("Файлы и Папка", side_left)
local ui_sound_now_playing = group_sound_manage:Label("Сейчас играет: Нет")

local ui_btn_refresh_sounds = group_sound_manage:Button("Обновить список звуков", function()
    RefreshSoundsList()
end)
ui_btn_refresh_sounds:Icon("\u{f2f9}")
ui_btn_refresh_sounds:ToolTip("Сканирует папку sounds и обновляет списки файлов во всех селекторах")

local ui_btn_open_folder = group_sound_manage:Button("Открыть папку sounds", function()
    OpenSoundsFolder()
end)
ui_btn_open_folder:Icon("\u{f07b}")
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
group_guide:Label("1. Запустите программу")
group_guide:Label("сервера \x07{primary}elycde.exe\x07{primary_widgets_text}")
group_guide:Label("2. В звуке Доты 2 выберите:")
group_guide:Label("\x07{primary}CABLE Output (микрофон)\x07{primary_widgets_text}")
group_guide:Label("3. Если нет звука в игре:")
group_guide:Label("\x07{primary}проверьте статус сервера\x07{primary_widgets_text}")
group_guide:Label("во вкладке Настройки.")

-- Правая колонка: Тестирование
local group_tests = tab_volume:Create("Тестирование звуков \u{f071}", side_right)

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
ui_btn_test_speaker_only:ToolTip("Воспроизводит звук только вам в наушники для настройки громкости")

local ui_btn_stop = group_tests:Button("Остановить всё (Stop)", function()
    StopAudioAndVoice()
end)
ui_btn_stop:ToolTip("Немедленно глушит звук на сервере и отпускает микрофон (-voicerecord)")

-- ------------------------------------------------------------------------
-- TAB 3: Чат и Насмешки
-- ------------------------------------------------------------------------
local group_chat = tab_chat:Create("Текстовый чат при килле", side_left)
local ui_chat_phrase = group_chat:Switch("Писать фразу при убийстве", true, "\u{f086}")
local ui_chat_all = group_chat:Switch("В общий чат (All Chat)", true, "\u{f0ac}")
local ui_chat_custom = group_chat:Input("Фраза при килле (пусто = случайная)", "")

local group_win_chat = tab_chat:Create("Текстовый чат при победе", side_left)
local ui_win_chat = group_win_chat:Switch("Писать фразу при победе", true, "\u{f086}")
ui_win_chat:ToolTip("Отправляет фразу в чат при уничтожении вражеского трона")
local ui_win_chat_all = group_win_chat:Switch("В общий чат (All Chat)", true, "\u{f0ac}")
ui_win_chat_all:ToolTip("Включено: say (видят все). Выключено: say_team (только союзники).")
local ui_win_chat_custom = group_win_chat:Input("Фраза при победе", "GG WP")
ui_win_chat_custom:ToolTip("Текст сообщения при сносе трона")

local group_taunt = tab_chat:Create("Насмешки героя", side_right)
local ui_hero_laugh = group_taunt:Switch("Смех героя (dota_player_laugh)", true, "\u{f118}")
local ui_hero_taunt = group_taunt:Switch("Таунт героя (dota_taunt)", false, "\u{f004}")

-- ------------------------------------------------------------------------
-- Динамическое скрытие неактивных элементов меню (API :Visible)
-- ------------------------------------------------------------------------
local function UpdateVisibility()
    local main_on = ui_enable and ui_enable:Get()

    -- 1. Kill секция
    local kill_on = main_on and ui_on_kill and ui_on_kill:Get()
    SetVisible(ui_on_kill, main_on)
    SetVisible(ui_on_fb, kill_on)
    SetVisible(ui_kill_mode, kill_on)
    local kill_custom = kill_on and ui_kill_mode and (ui_kill_mode:Get() == 1)
    SetVisible(ui_kill_sounds, kill_custom)
    SetVisible(ui_cooldown, kill_on)

    -- 2. Death секция
    local death_on = main_on and ui_on_death and ui_on_death:Get()
    SetVisible(ui_on_death, main_on)
    SetVisible(ui_death_mode, death_on)
    local death_custom = death_on and ui_death_mode and (ui_death_mode:Get() == 1)
    SetVisible(ui_death_sounds, death_custom)

    -- 3. Victory секция
    local win_on = main_on and ui_on_win and ui_on_win:Get()
    SetVisible(ui_on_win, main_on)
    SetVisible(ui_win_mode, win_on)
    local win_custom = win_on and ui_win_mode and (ui_win_mode:Get() == 1)
    SetVisible(ui_win_sounds, win_custom)

    -- 4. Chat и насмешки
    local chat_on = main_on and ui_chat_phrase and ui_chat_phrase:Get()
    SetVisible(ui_chat_phrase, main_on)
    SetVisible(ui_chat_all, chat_on)
    SetVisible(ui_chat_custom, chat_on)

    local win_chat_on = main_on and ui_win_chat and ui_win_chat:Get()
    SetVisible(ui_win_chat, main_on)
    SetVisible(ui_win_chat_all, win_chat_on)
    SetVisible(ui_win_chat_custom, win_chat_on)

    SetVisible(ui_hero_laugh, main_on)
    SetVisible(ui_hero_taunt, main_on)
end

local function BindCallback(ctrl)
    if ctrl and ctrl.SetCallback then
        pcall(function()
            ctrl:SetCallback(function()
                UpdateVisibility()
            end)
        end)
    end
end

BindCallback(ui_enable)
BindCallback(ui_on_kill)
BindCallback(ui_kill_mode)
BindCallback(ui_on_death)
BindCallback(ui_death_mode)
BindCallback(ui_on_win)
BindCallback(ui_win_mode)
BindCallback(ui_chat_phrase)
BindCallback(ui_win_chat)

UpdateVisibility()

-- ------------------------------------------------------------------------
-- Вспомогательная логика выбора звука для событий
-- ------------------------------------------------------------------------
local last_played_sound = {
    kill = nil,
    death = nil,
    victory = nil,
    all = nil
}

pcall(function()
    math.randomseed(os.time() + math.floor(os.clock() * 1000000))
    for _ = 1, 10 do math.random() end
end)

local function PickSoundFromPool(category, pool)
    if not pool or #pool == 0 then return nil end
    if #pool == 1 then
        last_played_sound[category] = pool[1]
        return pool[1]
    end

    pcall(function()
        math.randomseed(os.time() + math.floor(os.clock() * 1000000) + math.random(1, 10000))
    end)

    -- Исключаем предыдущий сыгранный трек, чтобы звуки гарантированно не повторялись подряд
    local last = last_played_sound[category]
    local candidates = {}
    for _, item in ipairs(pool) do
        if item ~= last then
            table.insert(candidates, item)
        end
    end

    if #candidates == 0 then
        candidates = pool
    end

    local chosen = candidates[math.random(1, #candidates)]
    last_played_sound[category] = chosen
    return chosen
end

local function GetEventSound(event_type)
    local mode = 0
    local multi_ctrl = nil
    local saved_key = "kill_sounds"
    local cat = "kill"

    if event_type == "kill" or event_type == "firstblood" then
        mode = (ui_kill_mode and ui_kill_mode:Get()) or 0
        multi_ctrl = ui_kill_sounds
        saved_key = "kill_sounds"
        cat = "kill"
    elseif event_type == "death" then
        mode = (ui_death_mode and ui_death_mode:Get()) or 0
        multi_ctrl = ui_death_sounds
        saved_key = "death_sounds"
        cat = "death"
    elseif event_type == "victory" then
        mode = (ui_win_mode and ui_win_mode:Get()) or 0
        multi_ctrl = ui_win_sounds
        saved_key = "win_sounds"
        cat = "victory"
    end

    -- 0: Случайный из всех файлов папки sounds (с защитой от повторов подряд)
    if mode == 0 then
        local valid_presets = {}
        for _, it in ipairs(SOUND_PRESETS or {}) do
            if it and it ~= "" and not it:find("^%(") then
                table.insert(valid_presets, it)
            end
        end
        if #valid_presets > 0 then
            return PickSoundFromPool("all", valid_presets)
        end
        return nil
    end

    -- 1: Выбранные галочками из выпадающего списка
    if mode == 1 then
        local pool = {}
        if multi_ctrl and multi_ctrl.ListEnabled then
            local ok, list = pcall(function() return multi_ctrl:ListEnabled() end)
            if ok and list and type(list) == "table" then
                for _, item in ipairs(list) do
                    if item and item ~= "" and not item:find("^%(") then
                        table.insert(pool, item)
                    end
                end
            end
        end

        if #pool == 0 then
            local saved = GetSavedList(saved_key)
            if saved and type(saved) == "table" then
                for _, item in ipairs(saved) do
                    if item and item ~= "" and not item:find("^%(") then
                        table.insert(pool, item)
                    end
                end
            end
        else
            SetSavedList(saved_key, pool)
        end

        if #pool > 0 then
            return PickSoundFromPool(cat, pool)
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
            SaveCachedSoundPresets(new_list)
        else
            SOUND_PRESETS = { "(Папка sounds пуста)" }
        end

        UpdateMultiControl(ui_kill_sounds, SOUND_PRESETS, "kill_sounds")
        UpdateMultiControl(ui_death_sounds, SOUND_PRESETS, "death_sounds")
        UpdateMultiControl(ui_win_sounds, SOUND_PRESETS, "win_sounds")

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
    Engine.ExecuteCommand("-voicerecord")
    is_speaking = false
    if ui_sound_now_playing then
        pcall(function() ui_sound_now_playing:Name("Сейчас играет: Нет") end)
    end
end

OpenSoundsFolder = function()
    if ui_sound_now_playing then
        pcall(function() ui_sound_now_playing:Name("Открываем папку sounds...") end)
    end

    -- 1. Native Dota 2 Panorama URL dispatch (works exactly like the repository link!)
    pcall(function()
        Engine.RunScript("$.DispatchEvent('ExternalBrowserGoToURL', 'file:///C:/Umbrella/scripts/VoiceTrashTalk/sounds')")
    end)

    -- 2. Windows shell command via start explorer
    pcall(function()
        local sounds_dir = "C:\\Umbrella\\scripts\\VoiceTrashTalk\\sounds"
        os.execute('cmd.exe /c if not exist "' .. sounds_dir .. '" mkdir "' .. sounds_dir .. '" & start explorer "' .. sounds_dir .. '"')
    end)

    -- 3. Direct explorer.exe
    pcall(function()
        os.execute('explorer.exe "C:\\Umbrella\\scripts\\VoiceTrashTalk\\sounds"')
    end)

    -- 4. Server HTTP request fallback
    HTTP.Request("GET", SERVER_URL .. "/open_folder", {}, function(res)
        if res and res.response and res.response:find('"opened"') then
            if ui_sound_now_playing then
                pcall(function() ui_sound_now_playing:Name("Папка sounds открыта") end)
            end
        end
    end)
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
        url = url .. "&file=" .. url_encode(chosen_file)
    elseif event_type then
        url = url .. "&event=" .. url_encode(event_type)
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
            local phrase = (ui_win_chat_custom and ui_win_chat_custom:Get()) or ""
            if phrase == "" then
                phrase = "GG WP"
            end
            local channel = (ui_win_chat_all and ui_win_chat_all:Get()) and "say" or "say_team"
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
            elseif ui_win_chat and ui_win_chat:Get() then
                local phrase = (ui_win_chat_custom and ui_win_chat_custom:Get()) or ""
                if phrase == "" then phrase = "GG WP" end
                local channel = (ui_win_chat_all and ui_win_chat_all:Get()) and "say" or "say_team"
                Engine.ExecuteCommand(channel .. ' "' .. phrase .. '"')
            end
            return
        end
    end

    -- 2. Своя смерть
    if ui_on_death:Get() and data.target == my_hero then
        local now = os.clock()
        local cd = (ui_cooldown and ui_cooldown:Get()) or 4
        if (now - last_death_time) >= cd then
            last_death_time = now
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
    Engine.ExecuteCommand("-voicerecord")
    is_speaking = false
end

return VoiceTrashTalk
