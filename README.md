# turbo-garbanzo — файтинг в стиле UFC 4 на Roblox

Рабочий каркас MMA-файтинга для Roblox: **кадровая боевая система** (startup/active/recovery), стамина, хитбоксы по костям R15, греппл-граф, авторитетный сервер с фиксированным шагом, предсказание на клиенте, бот-соперник, HUD и телевизионная камера октагона.

Всё спроектировано так, чтобы **числа можно было калибровать по видео из UFC 4**, а код — генерировать нейросетями.

> ⚠️ Юридически: мы **наблюдаем** за игрой (тайминги, урон, отбрасывание) и пишем **свою** реализацию. Не копируй ассеты, анимации, имена бойцов и логотипы из UFC 4 — это DMCA-бан в Roblox. Подробности: [`docs/reverse-engineering.md`](docs/reverse-engineering.md).

---

## Главный принцип: «физика» UFC 4 — это не физический движок

90% ощущений дают **кадры, тайминги и реакции**, а не симуляция тел:

| Система | Как сделано здесь |
|---|---|
| Фреймдата | `src/shared/FrameData.luau` + `data/moves.json` (60 fps) |
| Попадания | хитбокс на кости в активных кадрах → `HitboxSystem.queryHit` |
| Урон/блок/нокдаун | чистая функция `FrameData.resolveHit` |
| Стамина | `src/shared/StaminaSystem.luau` |
| Греппл | граф позиций + контесты в `src/server/GrappleSystem.luau` |
| Авторитет | сервер симулирует 60 тиков/с, клиент шлёт только `moveId` |
| Визуал | клиент предсказывает анимацию и сверяется со снапшотом |
| «Вес» удара | хитстоп + тряска камеры + отбрасывание импульсом |

Roblox-физика используется **только** для knockback-импульса и ragdoll при нокдауне.

---

## Быстрый старт

### 1. Установи Rojo
```bash
npm i -g rojo        # или: cargo install rojo / foreman
rojo --version
```
Плагин Rojo для Studio: https://rojo.space/docs/v7/getting-started/installation/

### 2. Запусти проект
```bash
rojo serve           # в терминале
```
В Roblox Studio: **New Baseplate → Rojo plugin → Connect**.

Или собрать файл места:
```bash
rojo build -o turbo-garbanzo.rbxlx
```

### 3. Проверь данные (без Studio)
```bash
python3 tools/calibrate.py --check data/moves.json
```

### 4. Проверка синтаксиса без Studio
```bash
python3 -m venv .venv && .venv/bin/pip install luaparser   # один раз
python3 tools/luau_syntax_check.py                          # все src/ и tests/
python3 tools/luau_syntax_check.py src/shared/FrameData.luau
python3 tools/luau_syntax_check.py --dump src/server/MatchServer.luau
```
Скрипт снимает Luau-типы и парсит результат настоящим Lua-парсером: ловит опечатки, незакрытые `end` и битые таблицы до открытия Studio. Если `luaparser` не установлен, работает эвристика по балансу блоков (неполная проверка).

### 5. Тесты
Положи [TestEZ](https://github.com/Roblox/testez) в `ReplicatedStorage.TestEZ` и запусти `tests/RunTests.server.luau`.

### 6. Подключи анимации
В `src/client/AnimDriver.luau` впиши свои `rbxassetid://` в таблицу `ANIMATIONS`. Без них мувы работают (логика считает кадры), но без визуала.

---

## Структура

```
default.project.json      # маппинг Rojo -> Roblox
data/
  moves.json              # ★ фреймдата всех 29 приёмов (сюда пишешь замеры)
  fighters.json           # статы бойцов/архетипов
src/
  shared/
    FrameData.luau        # ★ типы MoveDef/HitResult, фазы, resolveHit
    StateMachine.luau     # универсальный конечный автомат
    StaminaSystem.luau    # стамина, выдох, множители скорости
    FightMath.luau        # clamp/lerp/remap, контесты, пружина-демпфер
    Moves.luau            # загрузчик moves.json
    Remotes.luau          # единая точка RemoteEvent
  server/
    Main.server.luau      # вход: спавн бойцов, бот, тик-цикл
    MatchServer.luau      # ★ фиксированный шаг 60 Гц, коллизии, снапшоты
    FighterState.luau     # состояние бойца, буфер ввода, приём урона
    HitboxSystem.luau     # хитбоксы/хуртбоксы по костям R15
    GrappleSystem.luau    # граппл-граф, контесты, переводы позиций
    BotController.luau    # ИИ-соперник (заменяется RL-агентом)
  client/
    Main.client.luau      # вход клиента
    InputBuffer.luau      # раскладка клавиш/геймпада -> намерения
    Prediction.luau       # локальное предсказание + реконсиляция
    AnimDriver.luau       # moveId -> Animation track
    CameraRig.luau        # TV-камера октагона + тряска
    VFX.luau              # хитстоп, вспышки, брызги, звук
    HUD.luau              # полоски здоровья/стамины
tests/
  FrameData.spec.luau     # тесты фаз, resolveHit, стамины, целостности данных
  RunTests.server.luau
tools/
  pose_extract.py         # видео -> CSV скелета (MediaPipe)
  calibrate.py            # CSV -> startup/active/recovery + валидация JSON
  luau_syntax_check.py    # офлайн-проверка синтаксиса .luau (Luau -> Lua 5.1 + парсер)
docs/
  reverse-engineering.md  # ★ как замерять UFC 4 по кадрам
  ai-workflow.md          # ★ как вайбкодить это нейросетями + промпты
```

---

## Раскладка управления

| Клавиша | Действие | Геймпад |
|---|---|---|
| `E` | джеб | `A` |
| `R` | кросс | `R2` |
| `F` | хук (передняя) | `B` |
| `G` | апперкот | — |
| `Q` / `T` / `Y` | лоу / боди / хэд кик | `X` / `R1` |
| `C` | колено в клинче | — |
| `X` / `V` | double leg / single leg | `Y` |
| `B` / `N` | slip / duck (хэд-мувмент) | `L1` |
| `Space` / `ПКМ` | блок (удерживать) | `L2` |
| `W W` | двойной тап = проход в ноги | — |

---

## Порядок калибровки (это и есть «реверс»)

1. Сними клип приёма в 60 fps (тренировочный режим UFC 4, неподвижный dummy).
2. `python3 tools/pose_extract.py clip.mp4 --out clip.csv --fps 60`
3. `python3 tools/calibrate.py --measure clip.csv --point wrist_r --id cross --recovery 16`
4. Вставь полученный `timing` в `data/moves.json`.
5. `python3 tools/calibrate.py --check data/moves.json`
6. В Studio: ударь dummy — сравни ощущение с оригиналом. Правь `damage`, `knockback`, `stunFrames`.

Полная методика с таблицей «что мерить и куда писать» — в [`docs/reverse-engineering.md`](docs/reverse-engineering.md).

---

## Что уже работает «из коробки»

- ✅ Джеб прерывает кросс, потому что короче (7 vs 12 кадров startup)
- ✅ Блок режет урон по здоровью до `chipRatio`, но жжёт стамину ×1.35
- ✅ Долгий блок (>30 кадров) пробивается быстрее
- ✅ На нулевой стамине — выдох: скорость ×0.55, нокдаун-шанс растёт до +45%
- ✅ Один мув попадает максимум один раз (`hitConsumed`)
- ✅ Буфер ввода: нажал заранее — исполнится в окне отмены (как в файтингах)
- ✅ Хитстоп 3 кадра (6 на нокауте) + тряска камеры
- ✅ Тейкдаун защищается в окне 0.42 сек, провал жжёт стамину
- ✅ Позиции на земле: guard → side → mount → back, сабмишены, свипы, эскейпы
- ✅ Бот держит дистанцию, блокирует в startup соперника, выбирает мув по скорингу

---

## Что добавлять дальше

1. **Раунды и таймер** (5×5 мин, перерывы, судейские записки).
2. **Ростер бойцов** + статы из `fighters.json` в меню выбора.
3. **Ragdoll при нокдауне** (BallSocketConstraint на суставы R15 + отключение Motor6D на время).
4. **Клинч как отдельная позиция** с борьбой за контроль (сейчас тейкдаун идёт из `standing`).
5. **Headless-симуляция** для автобаланса: гонять 10 000 боёв бот-vs-бот, собирать CSV, кормить LLM.
6. **RL-агент** вместо `BotController` (контракт тот же — шлёт `moveId`).
7. **Своя 3D-модель бойца** (Blender → R15-риг), чтобы уйти от стандартного Roblox-аватара.

---

## Документация

- [`docs/reverse-engineering.md`](docs/reverse-engineering.md) — как легально снять тайминги/урон/отбрасывание из UFC 4 по кадрам, какие 7 систем реверсим, чем мерить.
- [`docs/ai-workflow.md`](docs/ai-workflow.md) — как вайбкодить проект нейросетями: контракты промптов, готовые промпты, пайплайны «видео → фреймдата», RL-агент, автобаланс.
