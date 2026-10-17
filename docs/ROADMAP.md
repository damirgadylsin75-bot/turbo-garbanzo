# ROADMAP — тестовая сборка → полноценный файтинг

Сейчас реализована тестовая сборка **только стойки**. Удалённые компоненты сохранены в git-истории; вернуть их можно точечно, не откатывая весь проект.

## Что вырезано и как вернуть

Удалены: `src/server/GrappleSystem.luau`, `src/shared/StateMachine.luau`, `src/client/Prediction.luau`, `src/server/BotController.luau`, `tools/pose_extract.py`, `tools/calibrate.py`, `tools/simulate.py`, `tests/`, `docs/ai-workflow.md`, `docs/reverse-engineering.md`. Из `moves.json` удалены приёмы партерa/греппла/передвижения и связанные поля. Состояния `grounded` и `getupFrames` удалены; нокдаун теперь использует `PlatformStand` и `Physics`.

Полная версия находилась в истории до упрощения, базовый известный срез — `5e2ad812071a801dc4ba2d601d9eed04c107f89c`. Посмотреть файл без изменения текущего дерева:

```bash
git show 5e2ad81:src/server/GrappleSystem.luau
git show 5e2ad81:data/moves.json
git log --oneline --all
```

Вернуть отдельные материалы в рабочую ветку (проверив совместимость с текущим API):

```bash
git checkout 5e2ad81 -- src/server/GrappleSystem.luau src/shared/StateMachine.luau
```

Prediction и BotController тоже доступны через `git show 5e2ad81:<путь>`. Не заменяй вслепую текущие `MatchServer`, `FighterState`, `FrameData` и `moves.json`: их контракты изменены. Инструменты и тесты зависят от внешнего TestEZ; прежняя привязка тестов в `default.project.json` намеренно удалена. `tools/luau_syntax_check.py` оставлен.

## Следующие этапы (не входят в текущую сборку)

1. **Полноценный ragdoll:** заранее создать Motor6D/BallSocketConstraint-конфигурацию при спавне; выключать Motor6D при падении, переводить Humanoid в `Physics`, импульс прикладывать со смещением от центра масс, клампить его; убрать самоколлизии кистей/стоп и blend ragdoll → getup-анимация около 0,5 с.
2. **IK-реакции:** IKControl работает на клиенте. Сервер отправляет `HitReact{hitVector, magnitude, bone}`, клиент своего персонажа отклоняет на 25–35° с низким Weight; нужен приваренный target Part, отключение IK в ragdoll и крутка UpperTorso.
3. **Греппл:** граф состояний standing → clinch → guard/side/mount/back с contest «атака против защиты», поправкой на стамину и окном защиты около 0,42 с. Не симулировать партер как RigidBody-бои.
4. **Раунды:** таймер 5×5, условия победы, перерывы и судейские записки.
5. **Swept raycast-хитбоксы:** заменить box overlap на 2–3 луча на конечность от позиции кадра N−1 до N, чтобы быстрые удары не проходили сквозь цель.
6. **Свой мувмент:** восемь направлений относительно соперника (вперёд/назад/сайдстеп) с инерцией вместо стандартного контроллера Roblox.
7. **PvP netcode:** вернуть клиентское предсказание и серверную реконсиляцию по снапшотам; старый `src/client/Prediction.luau` — исторический референс, не готовый модуль для подключения без адаптации.
8. **Калибровка по видео и автобаланс:** 60 fps → MediaPipe/OpenCV → CSV скелета → пик скорости конечности/кадр контакта → startup/active/recovery в moves.json → headless-симуляция тысяч боёв и CSV для баланса. Только наблюдение и собственная реализация: не использовать ассеты, анимации, модели, имена бойцов или логотипы UFC 4.
