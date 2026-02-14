# 河流 POI 一次性采集脚本

用 **Python 脚本** 按路径采样请求逆地理（**天地图**或**高德**），把结果写入 **SQLite**。App 里只查本地库，不再请求第三方，避免占用配额。高德通常返回的省/市/区/街道等更细致，可按需选用。

## 1. 统计与采样

- `yangtze_points.json`：约 **12.3 万** 个路径点，20 段，总长约 6387 km。
- 不适合对每个点请求 POI（请求量过大、配额不够）。
- 做法：按 **里程间隔**（如每 5 km）采样，只对采样点请求逆地理，约 **1200～3200 次** 请求（可再调大间隔以控制总量）。

## 2. 先看 POI 返回样式（3 个点测试）

用测试脚本只请求前 3 个采样点，并**打印完整返回 JSON**，确认字段与细致度后再跑全量：

```bash
# 天地图
export TIANDITU_TK="你的天地图key"
python3 tools/test_poi_three_points.py --provider tianditu --tk "$TIANDITU_TK"

# 高德（一般更细致：省/市/区/街道等）
export AMAP_KEY="你的高德Web服务Key"
python3 tools/test_poi_three_points.py --provider amap --key "$AMAP_KEY"
# 可选：--river yangtze --step 5
```

## 3. 运行全量 / 采样段

依赖：Python 3，无需额外 pip 包（仅用标准库）。数据源为 **高德**（`--key` 必填），河流列表与 JSON 路径从 **rivers_config.json** 读取。

```bash
# 在项目根目录执行
cd /path/to/rivtrek
export AMAP_KEY="你的高德Web服务Key"

# 只跑第 0～2 个采样点（共 3 次请求）
python3 tools/fetch_river_pois.py --river yangtze --step 5 --key "$AMAP_KEY" --from 0 --to 2
# 全量
python3 tools/fetch_river_pois.py --river yangtze --step 5 --key "$AMAP_KEY"

# 指定输出 DB、请求间隔等
python3 tools/fetch_river_pois.py --river yangtze --step 5 --key "$AMAP_KEY" --out tools/out/rivtrek_base.db --delay 0.5
```

参数说明：

| 参数       | 说明                         | 默认 |
|------------|------------------------------|------|
| `--key`    | 高德 Web 服务 Key（必填）     | - |
| `--river`  | 河流 id（与 **rivers_config.json** 中 `id` 一致） | yangtze |
| `--step`   | 采样间隔（公里）             | 5 |
| `--from`   | 采样段起点（含）             | 0 |
| `--to`     | 采样段终点（含）             | 到末尾 |
| `--delay`  | 每次请求间隔（秒）           | 0.3 |
| `--out`    | 输出 SQLite 文件路径         | tools/out/rivtrek_base.db |
| `--points` / `--master` | 可选，覆盖 config 中的 JSON 路径 | 从 config 读 |

**配置来源**：河流 id、数字 id（numeric_id）、points/master JSON 路径均从 **`assets/json/rivers/rivers_config.json`** 读取，与 App 共用同一配置。新增或下线江河只需改该配置文件并保证对应 JSON 存在。

脚本会：

1. 读取 `rivers_config.json`，按 `--river` 得到该河流的 `numeric_id`、`points_json_path`、`master_json_path`
2. 按 `--step` 在路径上采样得到 (lat, lon, distance_km)
3. 对每个采样点调用高德逆地理，解析 `formatted_address` 等
4. 以 `numeric_id` 写入 `river_id` 列，结果写入 `--out` 指定的 SQLite，表结构见下

## 4. 输出 SQLite 表结构（线性存储）

按「距起点距离」线性存储：每行一个采样点，主键 (numeric_id, distance_km)。  
查询时取「距离 path_km 最近」的一条：前后各查一次（≤ path_km 最大 / ≥ path_km 最小），比较 \|d - path_km\| 取更近者，避免只取「≤ 当前里程最大」导致 105 km 点比 80 km 更近却被忽略的问题。  
若做数据压缩，可只保留「POI/地址发生变化」的里程点，同一查询逻辑仍然成立（返回该里程所在段的代表点）。运行 **compress_river_pois.py** 对已生成的 DB 做变化点压缩：`python3 tools/compress_river_pois.py [--db tools/out/rivtrek_base.db]`，支持 `--dry-run` 仅查看保留行数。

- **缩放因子**：行进距离与路径地理距离可能不一致，App 从各河流 **master JSON**（如 `yangtze_master.json`）的 `correction_coefficient` 自动读取，查库前做 `path_km = accumulated_km * correction_coefficient`，无需在 config 里手配。

```sql
CREATE TABLE river_pois (
    numeric_id INTEGER NOT NULL,
    river_id TEXT NOT NULL,
    distance_km REAL NOT NULL,
    ...
    PRIMARY KEY (numeric_id, distance_km)
);
-- 查询: 取 distance_km <= path_km 最大一条 与 distance_km >= path_km 最小一条，选 |d - path_km| 更小者
```

## 5. 接入 App（POI 独立库，不与主库合并）

- **数据分离**：基础数据（POI 及今后其他静态数据）使用独立库 **`rivtrek_base.db`**；程序主库 `rivtrek_v1.db` 只存动态数据（步数、天气、事件）。不合并、解耦。
- **getNearestPoi** 是**本地 SQLite 查询**（查基础库），不是网络请求。

**接入步骤：**

1. 运行 POI 脚本，输出到 `tools/out/rivtrek_base.db`（可多河多次跑，或合并成单文件；可选再跑 compress 做变化点压缩）
2. **将 `tools/out/` 下生成的 `rivtrek_base.db` 拷贝到 `assets/db/`**（已在 `pubspec.yaml` 声明）
3. App 首次需要基础数据时：若本地无该文件则从 asset 复制到应用目录并打开，之后直接查该库
4. 产品里根据当前行进距离调 **getNearestPoi(riverId, accumulatedKm)**，用返回的 `shortLabel` 做「此刻行至 XXX」等展示，无需请求天地图。
