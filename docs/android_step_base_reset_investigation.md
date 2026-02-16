# Android 基准步数被“重新设定”问题调查

## 你的实际场景（复述）

- **11:00** 打开 App，当时约 **100 步**
- 之后又走了 **3000 步**（合计约 3100）
- 再次查看 App 只显示 **约 1500 步**

说明：若基准（base）一直保持 11 点时的 100，应显示 3000；显示 1500 等价于在某时刻 **base 被设成了约 1600**（todaySteps = 3100 - 1600 = 1500）。因此问题可以归纳为：**在已经设好“当天基准”之后，又在某种情况下重新设定了更大的基准。**

---

## 结论概览

基准（`base_steps_value`）**只会在两处被写入**，但存在两个导致“基准被错误推高”的机制：

1. **基准不是在“打开 App 时”设定，而是在“第一次收到传感器事件”时设定**  
   若第一条事件晚到（例如已是 1600 步），基准就会被设为 1600，从而少计 1500 步。
2. **FlowController 收到步数事件后调用 `syncAndroidSensor()` 时没有把当前事件传进去**  
   `syncAndroidSensor()` 内部会**重新订阅** `stepCountStream`，用的是**自己第一次收到的事件**来算 base，可能是更晚的步数，等于在“后续某次回调里又重新设定了一次基准”。

---

## 1. 基准何时、在哪里被写入

全局搜索后，**只有** `lib/services/step_sync_service.dart` 会写 `base_steps_value`：

| 位置 | 条件 | 效果 |
|------|------|------|
| 约 115 行 | `base = prefs.getInt('base_steps_value') ?? hardwareTotal` | 仅读：若没有存过 base，就用当前 `hardwareTotal` 作为 base（**没有在这里写 prefs**） |
| 约 118–120 行 | `hardwareTotal < base`（认为重启） | 写 `base_steps_value = hardwareTotal` |
| 约 126–131 行 | `lastSyncDate != today`（跨天） | 写 `last_sync_date = today` 且 **`base_steps_value = hardwareTotal`** |

因此，**“把 base 设成更大的数”只可能来自“跨天”分支**：某次执行时 `lastSyncDate != today`，用当时的 `hardwareTotal`（例如 1600）写入了 base。  
也就是说：**不是“跨天”被误判，就是“第一次参与计算的 hardwareTotal”本身就偏大（见下）。**

---

## 2. base 依赖的是“第一次传感器事件”，不是“打开 App 那一刻”

`syncAndroidSensor()` 的流程是：

1. **订阅** `Pedometer.stepCountStream`
2. **等待第一个 event**，用 `event.steps` 当作 `hardwareTotal`
3. 用这个 `hardwareTotal` 做：`base ?? hardwareTotal`、或跨天时 `base_steps_value = hardwareTotal`

文档与常见行为表明：**订阅时不会立刻收到“当前步数”，第一条事件要等传感器/系统下次上报才会来。**  
因此：

- 11:00 打开 App、当时真实只有 100 步
- `syncAll()` → `syncAndroidSensor()` 在 init 里被调用并订阅
- 若第一条事件在“又走了 1500 步之后”才到，则 `hardwareTotal = 1600`
- 此时若是“今天第一次跑这段逻辑”，会走 `lastSyncDate != today` 或 `base == null`，把 **base 设为 1600**
- 之后再走 1500 步，`hardwareTotal = 3100`，todaySteps = 3100 - 1600 = **1500** → 和你看到的一致

所以：**基准并不是在“11 点打开 App、100 步”时设定，而是在“第一次收到的那条事件”时设定；若该事件晚到，基准就会被设大，导致少计。**

---

## 3. 状态管理问题：每次调用都重新订阅，用的是“下一次”事件

调用关系：

- **FlowController**（约 123–127 行）：  
  `Pedometer.stepCountStream.listen((event) async { await StepSyncService.syncAndroidSensor(); ... })`  
  这里拿到了 `event`（例如 100 或 1600），但 **没有把 event 传给 `syncAndroidSensor()`**。
- **syncAndroidSensor()**（约 110 行）：  
  内部再次 `Pedometer.stepCountStream.listen((event) async { ... })`，用**自己第一次收到的 event** 去算 base 和 todaySteps。

因此：

- 某次回调里收到的是 100 步的 event，但 `syncAndroidSensor()` 没用这个 100，而是**重新订阅**，等**下一个** event（可能是 150、200、…、1600）。
- 当内部订阅第一次收到 1600 时，就会用 1600 去写 base（若满足跨天或 base 未设），等于**在已经有机会用 100 做基准之后，又用 1600 重新设定了一次基准**。

所以：**基准被“重新设定”的直接原因，是“每次 sync 都用新的订阅的第一次事件”，而不是用“触发这次 sync 的那次事件”。** 这属于状态/调用设计问题：**没有把“当前步数事件”从调用方传进 sync 逻辑。**

---

## 4. 其他可能：Workmanager 后台任务

- `main.dart` 里用 Workmanager 每小时跑一次 `StepSyncService.syncAll()`，其中包含 `syncAndroidSensor()`。
- 若后台在**独立进程/ isolate** 里跑，且该环境下的 SharedPreferences 与前台不同步（或读到的是旧/空状态），则后台第一次收到的事件可能是 3100，从而把 base 写成 3100、todaySteps 写成 0，之后前台再写 3200 就只显示 100。  
  你当前现象是“少了一半、约 1500”，更符合上面 2、3 的“第一次/内部订阅事件偏大（约 1600）”的解释；若你曾见过“某次打开突然变成 0 或很少”，再重点怀疑 Workmanager 与 prefs 不同步。

---

## 5. 小结：为何 11 点 100 步、又走 3000 步后只显示 1500

1. **基准不是“打开 App 时 100 步”设的，而是“某次第一次收到的事件”设的**  
   若该事件在 1600 步时才到，base 就会被设为 1600，导致少计约 1500 步。
2. **每次由 FlowController 触发 sync 时没有传入当前 event**  
   `syncAndroidSensor()` 用自己新订阅的“第一次事件”来算 base，可能比触发 sync 的那次 event 大很多，从而在运行过程中**再次把基准推高**，相当于“基准被重新设定”。

要修复，需要至少做两件事（仅方向，不涉及具体改法）：

- 在**今天第一次**需要基准时，尽量用“当前已知的步数”来设 base（例如打开 App 时若已有 Health 或一次即时读数，用该值写 base），而不是只依赖“第一条延迟的传感器事件”。
- **调用 `syncAndroidSensor()` 时传入“当前步数事件”**，在本次 sync 内用该事件计算 base 和 todaySteps，而不是在内部重新订阅并用“下一次”事件。

如需，我可以再根据你当前代码结构给出具体修改方案（仍不直接改代码，只写步骤和接口建议）。
