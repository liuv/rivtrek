#!/usr/bin/env python3
"""
按路径采样请求高德逆地理，将返回结构直接映射为 SQLite 列（一列一字段），便于存储与检索。

河流 id、数字 id、points/master JSON 路径均从 assets/json/rivers/rivers_config.json 读取，
与 App 共用同一配置；--river 传河流 id，脚本据此查 config 得到 numeric_id 与文件路径。

用法:
  python3 fetch_river_pois.py --river yangtze --step 5 --key YOUR_AMAP_KEY
  python3 fetch_river_pois.py --river yangtze --step 5 --key YOUR_KEY --from 0 --to 2

参数:
  --key    高德 Web 服务 Key（必填）
  --river  河流 id（与 config 中 id 一致），如 yangtze / yellow_river / songhua_river
  --step   采样间隔（公里），默认 5
  --from / --to  采样段起止索引（含）
  --delay  请求间隔秒数，默认 0.3
  --out    输出 DB 路径
  --points / --master  可选，覆盖 config 中的 JSON 路径
"""

import argparse
import json
import os
import ssl
import sqlite3
import time
import urllib.parse
import urllib.request

# macOS 上 Python 常因证书链不完整导致 HTTPS 报 CERTIFICATE_VERIFY_FAILED
def _http_context():
    try:
        import certifi
        return ssl.create_default_context(cafile=certifi.where())
    except ImportError:
        # 未安装 certifi 时用未验证上下文，仅建议本地脚本使用；生产环境建议: pip install certifi
        return ssl._create_unverified_context()

# 项目根目录（脚本在 tools/ 下）
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONFIG_PATH = os.path.join(ROOT, "assets", "json", "rivers", "rivers_config.json")


def load_rivers_config() -> list[dict]:
    """从 rivers_config.json 读取江河列表。"""
    if not os.path.isfile(CONFIG_PATH):
        raise SystemExit(f"配置文件不存在: {CONFIG_PATH}")
    with open(CONFIG_PATH, "r", encoding="utf-8") as f:
        data = json.load(f)
    return data.get("rivers") or []


def get_river_by_id(rivers: list[dict], river_id: str) -> dict | None:
    """按 id 查找一条河流配置，返回含 numeric_id、points_json_path、master_json_path 等。"""
    for r in rivers:
        if r.get("id") == river_id:
            return r
    return None


def resolve_config_path(relative_path: str) -> str:
    """config 中路径为 assets/json/rivers/xxx.json，转为项目根下的绝对路径。"""
    parts = relative_path.replace("\\", "/").strip("/").split("/")
    return os.path.join(ROOT, *parts)


def load_master_section_lengths(master_path: str) -> list[tuple[float, float]]:
    """返回 [(section_length_km, accumulated_length_km), ...]，与 sections_points 一一对应。"""
    with open(master_path, "r", encoding="utf-8") as f:
        m = json.load(f)
    rows = []
    for sec in m["challenge_sections"]:
        for sub in sec["sub_sections"]:
            rows.append((sub["sub_section_length_km"], sub["accumulated_length_km"]))
    return rows


def load_points_with_distance_km(points_path: str, section_lengths: list[tuple[float, float]]) -> list[tuple[float, float, float]]:
    """返回 [(lat, lon, distance_km), ...]，按路径顺序。section_lengths 每项为 (section_length_km, accumulated_length_km)，accumulated 为该段终点累计里程。"""
    with open(points_path, "r", encoding="utf-8") as f:
        p = json.load(f)
    sections = p["sections_points"]
    if len(sections) != len(section_lengths):
        raise ValueError(f"sections_points 数量 {len(sections)} 与 master 中 sub_sections 数量 {len(section_lengths)} 不一致")
    out = []
    for i, section in enumerate(sections):
        sec_len, acc_end = section_lengths[i]
        acc_start = 0.0 if i == 0 else section_lengths[i - 1][1]
        n = len(section)
        for j, pt in enumerate(section):
            lng = float(pt[0])
            lat = float(pt[1])
            if n <= 1:
                dist = acc_start
            else:
                ratio = j / (n - 1)
                dist = acc_start + ratio * sec_len
            out.append((lat, lng, dist))
    return out


def sample_by_km(points: list[tuple[float, float, float]], step_km: float) -> list[tuple[float, float, float]]:
    """按 step_km 间隔采样，每个间隔取距离最接近的一个点。"""
    if not points:
        return []
    sampled = []
    target = 0.0
    max_km = points[-1][2]
    idx = 0
    while target <= max_km and idx < len(points):
        # 找到第一个 >= target 的点，再在该点与前一点之间选更近的
        while idx < len(points) and points[idx][2] < target:
            idx += 1
        if idx >= len(points):
            break
        if idx == 0:
            best = points[0]
        else:
            prev = points[idx - 1]
            curr = points[idx]
            if abs(prev[2] - target) <= abs(curr[2] - target):
                best = prev
            else:
                best = curr
        sampled.append(best)
        target += step_km
        if points[idx][2] <= target:
            idx += 1
    return sampled


def _reverse_geocode_amap(lat: float, lon: float, key: str) -> dict | None:
    """高德逆地理 extensions=all，返回与表列一一对应的平铺字典（无 JSON 列）。"""
    location = f"{lon},{lat}"
    url = f"https://restapi.amap.com/v3/geocode/regeo?key={urllib.parse.quote(key)}&location={location}&extensions=all&radius=1000"
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "RivtrekPOI/1.0"})
        with urllib.request.urlopen(req, timeout=15, context=_http_context()) as resp:
            data = json.loads(resp.read().decode())
    except Exception as e:
        msg = str(e)
        print(f"  [WARN] amap request failed for ({lat}, {lon}): {e}")
        if "CERTIFICATE_VERIFY_FAILED" in msg or "SSL" in msg:
            print("  若遇 SSL 证书错误，可执行: pip install certifi")
        return None
    status = data.get("status")
    info = data.get("info", "")
    if status != "1":
        print(f"  [WARN] 高德返回异常 status={status!r} info={info!r} → 请检查 Key 是否有效、是否超出日配额、控制台是否勾选「Web 服务」")
        return None
    if "regeocode" not in data or not data["regeocode"]:
        print(f"  [WARN] 高德无 regeocode status={status!r} info={info!r}")
        return None
    r = data["regeocode"]
    out = {"formatted_address": r.get("formatted_address")}
    ac = r.get("addressComponent")
    if isinstance(ac, dict):
        out["country"] = ac.get("country")
        out["province"] = ac.get("province")
        out["city"] = ac.get("city")
        out["citycode"] = _str(ac.get("citycode"))
        out["district"] = ac.get("district")
        out["adcode"] = _str(ac.get("adcode"))
        out["township"] = ac.get("township")
        out["towncode"] = _str(ac.get("towncode"))
    else:
        for k in ("country", "province", "city", "citycode", "district", "adcode", "township", "towncode"):
            out[k] = None
    pois = r.get("pois")
    # 完整 POI 列表存 JSON，展示时解析 poisList 一次性展示多个兴趣点
    if isinstance(pois, list) and len(pois) > 0:
        def _poi_row(p):
            if not isinstance(p, dict):
                return None
            return {
                "id": _str(p.get("id")),
                "name": p.get("name"),
                "type": p.get("type"),
                "tel": p.get("tel"),
                "distance": _float(p.get("distance")),
                "direction": p.get("direction"),
                "address": p.get("address"),
                "location": p.get("location"),
                "businessarea": p.get("businessarea"),
            }
        pois_clean = [x for x in (_poi_row(x) for x in pois) if x is not None]
        out["pois_json"] = json.dumps(pois_clean, ensure_ascii=False) if pois_clean else None
    else:
        out["pois_json"] = None
    return out


def _str(v):
    return str(v) if v is not None else None


def _float(v):
    if v is None:
        return None
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def _scalar(v):
    """高德 API 空值常返回 [] 或 {}，SQLite 不能绑定 list/dict，统一转为 None。"""
    if v is None:
        return None
    if isinstance(v, (list, dict)):
        return None
    return v


def main():
    parser = argparse.ArgumentParser(description="采集河流路径 POI 写入 SQLite（高德逆地理→表列直接映射）")
    parser.add_argument("--key", required=True, help="高德 Web 服务 Key")
    parser.add_argument("--river", default="yangtze", help="河流 id")
    parser.add_argument("--step", type=float, default=5.0, help="采样间隔(km)")
    parser.add_argument("--from", dest="from_index", type=int, default=0, help="采样段起点(含)")
    parser.add_argument("--to", dest="to_index", type=int, default=None, help="采样段终点(含)，不填表示到末尾")
    parser.add_argument("--delay", type=float, default=0.3, help="请求间隔(秒)")
    parser.add_argument("--out", default=None, help="输出 db 路径")
    parser.add_argument("--points", default=None, help="覆盖 config 中的 points JSON 路径")
    parser.add_argument("--master", default=None, help="覆盖 config 中的 master JSON 路径")
    args = parser.parse_args()

    rivers = load_rivers_config()
    river_cfg = get_river_by_id(rivers, args.river)
    if not river_cfg:
        ids = [r.get("id") for r in rivers if r.get("id")]
        raise SystemExit(f"未知河流: {args.river}，config 中现有 id: {ids}")

    points_path = args.points or resolve_config_path(river_cfg["points_json_path"])
    master_path = args.master or resolve_config_path(river_cfg["master_json_path"])
    out_path = args.out or os.path.join(ROOT, "tools", "out", "rivtrek_base.db")
    numeric_id = int(river_cfg["numeric_id"])

    for p in (points_path, master_path):
        if not os.path.isfile(p):
            raise SystemExit(f"文件不存在: {p}")

    os.makedirs(os.path.dirname(os.path.abspath(out_path)) or ".", exist_ok=True)

    print("加载 master 与 points...")
    section_lengths = load_master_section_lengths(master_path)
    points = load_points_with_distance_km(points_path, section_lengths)
    print(f"  总点数: {len(points)}, 总长约 {points[-1][2]:.1f} km")

    full_sampled = sample_by_km(points, args.step)
    from_i = max(0, args.from_index)
    if args.to_index is not None:
        to_i = min(args.to_index + 1, len(full_sampled))  # --to 2 表示第 0、1、2 个（含）
    else:
        to_i = len(full_sampled)
    sampled = full_sampled[from_i:to_i]
    print(f"  高德逆地理  按 {args.step} km 采样共 {len(full_sampled)} 个点；本次第 {from_i}～{to_i - 1} 个，共 {len(sampled)} 次请求")

    if sampled:
        lat0, lon0, _ = sampled[0]
        probe = _reverse_geocode_amap(lat0, lon0, args.key)
        if probe is None:
            print("  [提示] 首点逆地理返回空，后续请求可能均为空。请检查 Key、配额与「Web 服务」权限。")
        else:
            print(f"  首点探路成功: {probe.get('formatted_address') or '(无地址)'}")

    river_slug = river_cfg["id"]  # 字符型 id，如 yangtze
    cols = (
        "numeric_id", "river_id", "distance_km", "latitude", "longitude", "formatted_address",
        "country", "province", "city", "citycode", "district", "adcode", "township", "towncode",
        "pois_json",
    )
    conn = sqlite3.connect(out_path)
    cur = conn.execute("PRAGMA table_info(river_pois)")
    cols_exist = [r[1] for r in cur.fetchall()] if cur else []
    if "distance_km" not in cols_exist:
        conn.execute("DROP TABLE IF EXISTS river_pois")
        cols_exist = []
    if not cols_exist:
        conn.execute("""
        CREATE TABLE river_pois (
            numeric_id INTEGER NOT NULL,
            river_id TEXT NOT NULL,
            distance_km REAL NOT NULL,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            formatted_address TEXT,
            country TEXT, province TEXT, city TEXT, citycode TEXT, district TEXT, adcode TEXT, township TEXT, towncode TEXT,
            pois_json TEXT,
            PRIMARY KEY (numeric_id, distance_km)
        )
    """)
        conn.commit()

    placeholders = ",".join(["?"] * len(cols))
    insert = f"INSERT OR REPLACE INTO river_pois ({','.join(cols)}) VALUES ({placeholders})"
    for i, (lat, lon, dist_km) in enumerate(sampled):
        if i > 0:
            time.sleep(args.delay)
        result = _reverse_geocode_amap(lat, lon, args.key)
        d = round(dist_km, 2)
        if result is None:
            row = (numeric_id, river_slug, d, lat, lon) + (None,) * (len(cols) - 5)
        else:
            row = (
                numeric_id, river_slug, d, lat, lon,
                _scalar(result.get("formatted_address")), _scalar(result.get("country")), _scalar(result.get("province")), _scalar(result.get("city")), _scalar(result.get("citycode")),
                _scalar(result.get("district")), _scalar(result.get("adcode")), _scalar(result.get("township")), _scalar(result.get("towncode")),
                result.get("pois_json"),
            )
        conn.execute(insert, row)
        if (i + 1) % 100 == 0:
            conn.commit()
            print(f"  已请求 {i + 1}/{len(sampled)}")

    conn.commit()
    conn.close()
    print(f"完成。SQLite 已写入: {out_path}")


if __name__ == "__main__":
    main()
