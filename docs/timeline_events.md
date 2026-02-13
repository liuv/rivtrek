# Timeline 事件逻辑梳理

## 一、数据来源与三类信息

| 类型 | 数据表/模型 | 含义 |
|------|-------------|------|
| **每日行进信息** | `daily_activities` / `DailyActivity` | 每日步数 → 换算成当日前进距离，并维护累计里程 |
| **每日天气** | `daily_weather` / `DailyWeather` | 按日期存储的天气快照，用于在时间线上关联「当日天气」 |
| **河流事件** | `river_events` / `RiverEvent` | 主动/随机事件：放河灯、祭江、江上拾遗（拾遗）、成就等 |

进入挑战记录时间线时，在「个人中心」点击「挑战记录（公里）」或「挑战记录（日期）」会从数据库拉取：

- `getAllActivities()`
- `getAllWeather()`
- `getAllEvents()`

然后交给 `TimelinePage` → `BlocProvider` → `Timeline.loadFromActivities(activities, weathers, events, axisMode)`，统一生成时间线条目。

---

## 二、时间轴两种维度

时间线支持两种**轴模式**（`TimelineAxisMode`），对应你说的「距离维度」和「时间维度」：

| 模式 | 枚举值 | 横轴含义 | 行进信息位置 | 事件位置 |
|------|--------|----------|--------------|----------|
| **距离维度** | `distanceKm` | 累计里程 (km) | `activity.accumulatedDistanceKm` | `event.distanceAtKm` |
| **时间维度** | `calendarDate` | 日历天数（相对 epoch 的天数） | `dateStringToAxisDay(activity.date)` | `dateStringToAxisDay(event.date)` |

核心映射在 `timeline.dart` 中：

- **活动（每日行进）**  
  - `_axisValueForActivity(activity, axisMode)`  
  - 距离轴：`activity.accumulatedDistanceKm`  
  - 日期轴：`dateStringToAxisDay(activity.date)`

- **河流事件**  
  - `_axisValueForEvent(event, axisMode)`  
  - 距离轴：`event.distanceAtKm`  
  - 日期轴：`dateStringToAxisDay(event.date)`

因此：

- **距离维度**：同一天可能有多条记录（多天步数），按「累计里程」沿江排开；事件要落在正确里程上，必须存对 `distanceAtKm`（例如放河灯/祭江时用 `challenge.currentDistance`）。
- **时间维度**：按「日期」排布，同一天的行进与事件会落在同一天的位置；事件只需要 `date` 正确即可，`distanceAtKm` 在日期轴下不参与定位，但保留无妨。

---

## 三、时间线上「两类事件」如何被处理

### 1. 每日行进信息（一条/天）

- **生成方式**：对 `sortedActivities` 逐条生成一个 `TimelineEntry`，类型为 `Incident`。
- **轴位置**：由当前 `axisMode` 决定用 `accumulatedDistanceKm` 还是 `date`（见上）。
- **天气**：用 `activity.date` 在 `weathers` 里查找当日天气，赋给 `entry.weather`，并在 label 中展示（如 `" | 温度 城市"`）。
- **展示**：label 为「日期 + 步数 + 当日前进 km + 天气摘要」。

所以：**无论是距离轴还是日期轴，每天一条行进记录，且可关联当日天气。**

### 2. 主动/随机事件（放河灯、祭江、江上拾遗等）

- **生成方式**：对 `events`（`RiverEvent` 列表）逐条生成一个 `TimelineEntry`，类型同样为 `Incident`。
- **轴位置**：  
  - **距离维度**：用 `event.distanceAtKm`，所以录入时必须是「当时的累计里程」（当前实现里放河灯/祭江用的是 `challenge.currentDistance`，正确）。  
  - **时间维度**：用 `event.date` 转成轴上的「天」。
- **天气**：现已按 `event.date` 查找当日天气，赋给 `eventEntry.weather`，并在事件 label 末尾加上天气摘要；点击事件时也可用 `entry.weather` 展示当日天气。
- **类型与样式**：  
  - `RiverEventType.pickup` → 拾遗（绿）  
  - `RiverEventType.activity` → 活动（蓝），放河灯、祭江属于此类  
  - `RiverEventType.achievement` → 成就（黄）

同一日可以既有「当日行进」条目，也有多个「河流事件」条目；在日期轴上会挤在同一天附近，在距离轴上则按各自里程排布。

---

## 四、数据流小结

```
数据库
  daily_activities (date, steps, distance_km, accumulated_distance_km, river_id)
  daily_weather     (date, ...)
  river_events      (date, timestamp, type, name, description, distance_at_km, ...)
       ↓
MeScreen 点击「挑战记录（公里/日期）」
  → getAllActivities / getAllWeather / getAllEvents
  → TimelinePage(activities, weathers, events, mode)
       ↓
BlocProvider
  → Timeline.loadFromActivities(activities, weathers, events, axisMode: mode)
       ↓
1) 按 axisMode 对 activities 排序（按轴值）
2) 为河流建一个 Era（挑战时间线/挑战里程）
3) 每个 DailyActivity → 一个 Incident（带 weather），轴值 = _axisValueForActivity(·)
4) 每个 RiverEvent → 一个 Incident（带 weather），轴值 = _axisValueForEvent(·)
5) 全部按 start 排序，再建 next/previous、parent/children
       ↓
TimelineWidget 展示；点击任意条目可沿用 entry.weather 做当日天气展示
```

---

## 五、你关心的几个点

1. **「每天会有一个行进信息事件」**  
   - 已满足：每条 `DailyActivity` 对应时间线上的一个 Incident，且按日期每天一条（由步数同步/写入逻辑保证）。

2. **「主动事件（放河灯、祭江）和后续的江上拾遗」**  
   - 都走 `RiverEvent` + `recordEvent()`；拾遗用 `RiverEventType.pickup`，放河灯/祭江用 `RiverEventType.activity`。  
   - 时间线上统一用「事件」分支处理，和「每日行进」并列。

3. **「点击事件时关联当日天气」**  
   - 行进条目：本来就有 `entry.weather`。  
   - 事件条目：已改为按 `event.date` 查天气并赋给 `eventEntry.weather`，label 也带天气摘要；详情页只要读 `entry.weather` 即可展示当日天气。

4. **「距离维度和时间维度对两类事件如何处理」**  
   - **距离维度**：行进用 `accumulatedDistanceKm`，事件用 `distanceAtKm`（放河灯/祭江已用当前累计里程）。  
   - **时间维度**：行进和事件都用「日期」转轴值，因此同一天的行进与事件会在同一段时间附近；事件只需保证 `date` 正确。

5. **FVM**  
   - 所有 `flutter` 命令前加 `fvm` 即可，例如：`fvm flutter run`、`fvm flutter pub get`。

若你后续要加「江上拾遗」的触发与写入，只需在合适处调用 `DatabaseService.instance.recordEvent(RiverEvent(..., type: RiverEventType.pickup, date: ..., distanceAtKm: ...))`，并保证 `date` 与 `distanceAtKm` 与当前逻辑一致即可。
