# ROADMAP — что вырезано из тестовой сборки и как вернуть

Сейчас в `main` — **быстрая тестовая сборка: только стойка** (12 приёмов, манекен).
Полная MMA-версия (29 приёмов, греппл, партер, ИИ-бот, тесты, калибровка) была в
истории git до вырезания. Этот документ фиксирует, **что именно удалено** и **как
это вернуть**, когда понадобится.

---

## Что вырезано

### Файлы удалены целиком

| Файл | Что делал |
|---|---|
| `src/server/GrappleSystem.luau` | греппл целиком: тейкдауны, клинч, позиции guard/side/mount/back, сабмишены, свипы, эскейпы |
| `src/shared/StateMachine.luau` | универсальный конечный автомат (не использовался — мёртвый вес) |
| `src/client/Prediction.luau` | предсказание анимаций + реконсиляция со снапшотами (для тестов с манекеном не нужно) |
| `src/server/BotController.luau` | ИИ-соперник с контролем дистанции и скорингом мувов (заменён на `DummyController.luau`) |
| `tools/pose_extract.py` | видео → CSV скелета (MediaPipe) |
| `tools/calibrate.py` | CSV → замеры startup/active/recovery + валидация JSON |
| `tools/simulate.py` | headless-симулятор боёв → CSV для автобаланса |
| `tests/` (2 файла) | тесты FrameData/стамины (требуют внешний TestEZ) |
| `docs/ai-workflow.md` | вайбкодинг нейросетями: промпты, пайплайны, RL-агент |
| `docs/reverse-engineering.md` | методика замеров UFC 4 по кадрам |

### Из `data/moves.json` убрано 17 приёмов

- удары: `spinning_back_kick`, `superman_punch`, `knee_clinch`, `elbow_clinch`;
- греппл: `double_leg`, `single_leg`, `clinch_trip`, `escape_guard`, `sweep_guard`, `transition_mount`, `armbar_guard`, `rnc_attempt`;
- партер: `ground_pound_top`, `ground_punch_bottom`;
- движение: `walk_fwd`, `walk_back`, `sidestep`.

Плюс убраны поля `props.standingOnly` / `props.onGroundOnly` и все блоки `grapple`
у приёмов. Остались ровно 12 приёмов стойки: `jab`, `cross`, `hook_left`,
`hook_right`, `uppercut_right`, `overhand_right`, `kick_low`, `kick_body`,
`kick_head`, `block`, `slip`, `duck`.

### Из кода убрано

- `FighterState`: поля `grounded` / `getupFrames` (оставлен `knockdownFrames`), нокдаун переписан на дешёвый `PlatformStand` + `ChangeState(Physics)`;
- `MatchServer`: греппл-сессия, action `grapple`, action `move` (направления). Клиент теперь шлёт **только** `{action, moveId}`;
- `Moves.luau`: `groundStrikes()` / `takedowns()` (добавлены `Moves.isValid`, `Moves.defensive`, загрузка секций настроек);
- `StaminaSystem`: реген в клинче (`regenPerSecondGrappling`);
- `FrameData`: тип `GrappleSpec`, поле `grounded` у защитника.

### Сохранено (не трогать при возврате!)

- буфер ввода, окна отмены, супер-армор, прерывание **только замаха**;
- фиксированный шаг 60 Гц, античит по частоте намерений, `Moves.isValid`, «один мув = одно попадание»;
- все числа боя — в `data/moves.json` (секции `combat` / `balance` / `stamina` / `hurtboxes` / `dummy`);
- только R15: хитбоксы `RightHand`/`LeftHand`/`RightFoot`, хуртбоксы `Head`/`UpperTorso`/`LowerTorso`.

---

## Как вернуть из истории git

Последний коммит с полной версией — это точка слияния полной версии в `main`:

```
5e2ad812071a801dc4ba2d601d9eed04c107f89c  (Merge pull request #1)
```

Все удалённые файлы лежат в нём целиком. Вернуть файл:

```bash
git checkout 5e2ad81 -- src/server/GrappleSystem.luau
git checkout 5e2ad81 -- tests/ tools/simulate.py docs/ai-workflow.md
```

Посмотреть, каким был старый код:

```bash
git show 5e2ad81:src/server/BotController.luau
git show 5e2ad81:data/moves.json          # все 29 приёмов
git log --oneline --all                    # найти нужный срез по дате/описанию
```

Вернуть **файл целиком на старую версию** (перезаписав текущую):

```bash
git checkout 5e2ad81 -- src/server/MatchServer.luau
```

### Порядок возврата (рекомендуемый)

1. **Стейт-машина и греппл-граф**: `git checkout 5e2ad81 -- src/server/GrappleSystem.luau src/shared/StateMachine.luau` — но учти, что `FighterState` потерял `grounded`/`getupFrames`; их придётся вернуть либо из того же коммита, либо вручную.
2. **Приёмы**: вытащить из `git show 5e2ad81:data/moves.json` нужные блоки и вклеить в текущий `moves.json` (не забыть вернуть поля `grapple` / `standingOnly` / `onGroundOnly` и тип `GrappleSpec` в `FrameData.luau`).
3. **MatchServer**: вернуть греппл-сессию и action `grapple` (`git show 5e2ad81:src/server/MatchServer.luau` как референс).
4. **Prediction**: `git checkout 5e2ad81 -- src/client/Prediction.luau`, подключить в `Main.client.luau` (он дёргает `AnimDriver` по снапшотам).
5. **BotController**: вернуть вместо/рядом с `DummyController.luau` (у него тот же контракт ввода — `MatchServer.handleInputBot`).
6. **Инструменты и тесты**: `git checkout 5e2ad81 -- tools/ tests/` + положить [TestEZ](https://github.com/Roblox/testez) в `ReplicatedStorage.TestEZ`; не забыть вернуть `ServerStorage/Tests` в `default.project.json`.
7. **Документы**: `git checkout 5e2ad81 -- docs/ai-workflow.md docs/reverse-engineering.md`.

⚠️ Файл `tools/luau_syntax_check.py` **не удалялся** — проверка `python3 tools/luau_syntax_check.py` должна выдавать OK на каждом шаге возврата.

---

## Куда дальше (после возврата полной версии)

1. **Раунды и таймер** (5×5 мин, перерывы, судейские записки).
2. **Ragdoll при нокдауне** (BallSocketConstraint на суставы R15 + отключение Motor6D).
3. **Клинч как отдельная позиция** с борьбой за контроль.
4. **RL-агент** вместо `BotController`/`DummyController` (контракт тот же — шлёт `{action, moveId}`).
5. **Своя 3D-модель бойца** (Blender → R15-риг).
