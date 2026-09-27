# elycde Umbrella Suite 🛡️

Пакет скриптов и аудио-компаньон для **Umbrella Dota 2**.

## 📦 Компоненты

1. **Map Drawer** (`lua/MapDrawer.lua`):
   - Рисование на миникарте от руки и зацикленное воспроизведение (20мс - 3000мс).
   - Генератор плотных QR-кодов (100% считываемость камерой).
   - Векторный парсер SVG (M, L, H, V, C, S, Q, T, A, Z, polygon, polyline, rect, circle).
   - Векторный текстовый рендерер (латиница, кириллица, авто-перенос, жирность).
   - Меню: `Scripts -> elycde -> Map Drawer`.

2. **Voice TrashTalk** (`lua/VoiceTrashTalk.lua`):
   - Автоматическое воспроизведение звуков в голосовой чат Доты 2 при убийствах, First Blood или смерти.
   - Двойной вывод: одновременно в виртуальный микрофон Доты (VB-Audio Cable) и вам в наушники.
   - Насмешки героя (laugh, taunt) и фразы в чат (All / Team).
   - Меню: `Scripts -> elycde -> Voice TrashTalk`.

3. **elycde Companion & Bundle Installer** (`elycde.exe`):
   - Работает в фоне на порту 8765.
   - Автоматически находит папку `scripts/` и скачивает/обновляет все луашки из папки `lua/` репозитория.
   - Сам обновляется при выходе новых версий из GitHub Releases.
   - Автоматически проверяет драйвер VB-Audio Cable и предлагает скачать его, если он не установлен.

---

## 🚀 Быстрый старт (в 1 клик)

1. Скачайте **[`elycde.exe`](https://github.com/elycde/umb/releases/latest/download/elycde.exe)** из раздела Releases.
2. Положите `elycde.exe` прямо в корень папки **Umbrella** (где лежит `UmbrellaLoader.exe`).
3. Запустите `elycde.exe`. Он автоматически создаст все нужные папки, скачает скрипты и звуки.
4. Запустите лоадер Umbrella и нажмите **F6** в игре!
