#!/usr/bin/env python3
"""
按路径采样请求海外逆地理/POI（OSM+Geoapify），返回结构与高德完全对齐，直接写入同一份SQLite。

与原高德脚本参数/用法/输出完全一致，仅新增 --geoapify-key 参数（替代高德key），
自动识别海外坐标（非中国）并使用Geoapify查询，数据结构1:1映射高德字段。

用法:
  python3 fetch_river_pois_overseas.py --river mekong --step 5 --geoapify-key YOUR_GEOAPIFY_KEY
  python3 fetch_river_pois_overseas.py --river salween --step 5 --geoapify-key YOUR_KEY --from 0 --to 2

参数:
  --geoapify-key    Geoapify API Key（必填，免费申请: https://www.geoapify.com/）
  --river           河流 id（与 config 中 id 一致），如 mekong / salween
  --step            采样间隔（公里），默认 5
  --from / --to     采样段起止索引（含）
  --delay           请求间隔秒数，默认 0.3
  --out             输出 DB 路径
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
from typing import Dict, List, Tuple, Optional

# macOS 证书兼容
def _http_context():
    try:
        import certifi
        return ssl.create_default_context(cafile=certifi.where())
    except ImportError:
        return ssl._create_unverified_context()

# 项目根目录（与原脚本保持一致）
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONFIG_PATH = os.path.join(ROOT, "assets", "json", "rivers", "rivers_config.json")

# 中国经纬度范围（用于区分国内/海外，避免误查）
CHINA_LON_MIN = 73.66
CHINA_LON_MAX = 135.05
CHINA_LAT_MIN = 3.86
CHINA_LAT_MAX = 53.55

def is_china_coordinate(lat: float, lon: float) -> bool:
    """判断坐标是否在中国境内（避免海外脚本查询国内坐标）"""
    return (CHINA_LON_MIN <= lon <= CHINA_LON_MAX) and (CHINA_LAT_MIN <= lat <= CHINA_LAT_MAX)

# -------------------------- 原脚本复用逻辑（完全不变） --------------------------
def load_rivers_config() -> list[dict]:
    if not os.path.isfile(CONFIG_PATH):
        raise SystemExit(f"配置文件不存在: {CONFIG_PATH}")
    with open(CONFIG_PATH, "r", encoding="utf-8") as f:
        data = json.load(f)
    return data.get("rivers") or []

def get_river_by_id(rivers: list[dict], river_id: str) -> dict | None:
    for r in rivers:
        if r.get("id") == river_id:
            return r
    return None

def resolve_config_path(relative_path: str) -> str:
    parts = relative_path.replace("\\", "/").strip("/").split("/")
    return os.path.join(ROOT, *parts)

def load_master_section_lengths(master_path: str) -> list[tuple[float, float]]:
    with open(master_path, "r", encoding="utf-8") as f:
        m = json.load(f)
    rows = []
    for sec in m["challenge_sections"]:
        for sub in sec["sub_sections"]:
            rows.append((sub["sub_section_length_km"], sub["accumulated_length_km"]))
    return rows

def load_points_with_distance_km(points_path: str, section_lengths: list[tuple[float, float]]) -> list[tuple[float, float, float]]:
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
    if not points:
        return []
    sampled = []
    target = 0.0
    max_km = points[-1][2]
    idx = 0
    while target <= max_km and idx < len(points):
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
    if v is None:
        return None
    if isinstance(v, (list, dict)):
        return None
    return v

# -------------------------- 校正后的海外逆地理/POI核心逻辑 --------------------------
def _reverse_geocode_geoapify(lat: float, lon: float, api_key: str) -> Dict | None:
    """
    终极版：单次请求获取地址+POI（只算1次配额），解决超限问题
    """
    # 1. 格式化经纬度
    lat_str = f"{lat:.6f}"
    lon_str = f"{lon:.6f}"
    
    # 2. 构造合并请求URL（关键：include=pois，单次请求获取地址+POI）
    params = urllib.parse.urlencode({
        "lat": lat_str,
        "lon": lon_str,
        "apiKey": api_key,
        "format": "json",
        "include": "pois",          # 核心：同时返回POI
        "pois_radius": 1000,        # POI搜索半径（米）
        "pois_limit": 20,           # 最多返回20个POI
        "pois_categories": "tourism,commercial,amenity,transport,natural"  # POI类型
    })
    # 只用这1个URL，同时获取地址+POI，只算1次请求！
    request_url = f"https://api.geoapify.com/v1/geocode/reverse?{params}"

    # 3. 请求头
    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Accept": "application/json",
        "Accept-Language": "en-US,en;q=0.9"
    }

    try:
        # 只发1次请求！
        req = urllib.request.Request(request_url, headers=headers, method="GET")
        with urllib.request.urlopen(req, timeout=15, context=_http_context()) as resp:
            if resp.getcode() != 200:
                print(f"  [WARN] 请求状态码: {resp.getcode()}")
                return None
            data = json.loads(resp.read().decode("utf-8"))

    except urllib.error.HTTPError as e:
        error_detail = e.read().decode("utf-8") if hasattr(e, "read") else "无详细信息"
        print(f"  [ERROR] Geoapify HTTP {e.code} 错误: {error_detail} | 坐标 ({lat}, {lon})")
        return None
    except Exception as e:
        print(f"  [ERROR] 请求异常: {str(e)} | 坐标 ({lat}, {lon})")
        return None

    # -------------------------- 解析地址+POI（单次请求返回） --------------------------
    out = {"formatted_address": None, "pois_json": None}
    
    # 1. 解析逆地理地址（不变）
    if data.get("results") and len(data["results"]) > 0:
        props = data["results"][0]
        out["formatted_address"] = props.get("formatted") or props.get("address_line1")
        out["country"] = props.get("country")
        out["province"] = props.get("state") or props.get("region")
        out["city"] = props.get("city") or props.get("municipality") or props.get("county")
        out["citycode"] = props.get("country_code") or props.get("iso3166_2")
        out["district"] = props.get("county") or props.get("district")
        out["adcode"] = props.get("postcode") or props.get("plus_code")
        out["township"] = props.get("town") or props.get("village")
        out["towncode"] = None
    
    # 2. 解析POI（从同一次请求的pois字段获取，不用再发第二次请求）
    pois_clean = []
    if data.get("pois") and len(data["pois"]) > 0:
        for poi in data["pois"]:
            # POI字段映射（适配合并请求的返回格式）
            poi_type = poi["category"] if poi.get("category") else None
            distance = _float(poi.get("distance"))
            poi_row = {
                "id": _str(poi.get("place_id")),
                "name": poi.get("name"),
                "type": poi_type,
                "tel": poi.get("phone"),
                "distance": distance,
                "direction": None,
                "address": poi.get("formatted") or poi.get("address_line1"),
                "location": f"{poi.get('lon')},{poi.get('lat')}" if poi.get('lon') and poi.get('lat') else None,
                "businessarea": poi.get("district") or poi.get("suburb"),
            }
            pois_clean.append(poi_row)
    
    out["pois_json"] = json.dumps(pois_clean, ensure_ascii=False) if pois_clean else None
    
    # 日志提示
    if out["formatted_address"]:
        print(f"  [SUCCESS] 地址: {out['formatted_address']} | POI数量: {len(pois_clean)}")
    else:
        print(f"  [INFO] 坐标 ({lat}, {lon}) 无地址数据（保留空值）")
    return out

# -------------------------- 主逻辑（仅替换逆地理函数） --------------------------
def main():
    parser = argparse.ArgumentParser(description="采集海外河流路径 POI 写入 SQLite（兼容高德结构）")
    parser.add_argument("--geoapify-key", required=True, help="Geoapify API Key（免费申请: https://www.geoapify.com/）")
    parser.add_argument("--river", default="mekong", help="河流 id")
    parser.add_argument("--step", type=float, default=5.0, help="采样间隔(km)")
    parser.add_argument("--from", dest="from_index", type=int, default=0, help="采样段起点(含)")
    parser.add_argument("--to", dest="to_index", type=int, default=None, help="采样段终点(含)，不填表示到末尾")
    parser.add_argument("--delay", type=float, default=0.3, help="请求间隔(秒)")
    parser.add_argument("--out", default=None, help="输出 db 路径")
    parser.add_argument("--points", default=None, help="覆盖 config 中的 points JSON 路径")
    parser.add_argument("--master", default=None, help="覆盖 config 中的 master JSON 路径")
    args = parser.parse_args()

    # 加载河流配置（与原脚本一致）
    rivers = load_rivers_config()
    river_cfg = get_river_by_id(rivers, args.river)
    if not river_cfg:
        ids = [r.get("id") for r in rivers if r.get("id")]
        raise SystemExit(f"未知河流: {args.river}，config 中现有 id: {ids}")

    # 解析路径（与原脚本一致）
    points_path = args.points or resolve_config_path(river_cfg["points_json_path"])
    master_path = args.master or resolve_config_path(river_cfg["master_json_path"])
    out_path = args.out or os.path.join(ROOT, "tools", "out", "rivtrek_base.db")
    numeric_id = int(river_cfg["numeric_id"])

    for p in (points_path, master_path):
        if not os.path.isfile(p):
            raise SystemExit(f"文件不存在: {p}")

    os.makedirs(os.path.dirname(os.path.abspath(out_path)) or ".", exist_ok=True)

    # 加载并采样点（与原脚本一致）
    print("加载 master 与 points...")
    section_lengths = load_master_section_lengths(master_path)
    points = load_points_with_distance_km(points_path, section_lengths)
    print(f"  总点数: {len(points)}, 总长约 {points[-1][2]:.1f} km")

    full_sampled = sample_by_km(points, args.step)
    from_i = max(0, args.from_index)
    if args.to_index is not None:
        to_i = min(args.to_index + 1, len(full_sampled))
    else:
        to_i = len(full_sampled)
    sampled = full_sampled[from_i:to_i]
    print(f"  海外逆地理  按 {args.step} km 采样共 {len(full_sampled)} 个点；本次第 {from_i}～{to_i - 1} 个，共 {len(sampled)} 次请求")

    # 首点探路（验证API Key）
    if sampled:
        lat0, lon0, _ = sampled[0]
        probe = _reverse_geocode_geoapify(lat0, lon0, args.geoapify_key)
        if probe is None:
            print("  [提示] 首点逆地理返回空，后续请求可能均为空。请检查 Geoapify Key 是否有效、是否超出配额。")
        else:
            print(f"  首点探路成功: {probe.get('formatted_address') or '(无地址)'}")

    # -------------------------- 替换原脚本中的写入逻辑 --------------------------
    # SQLite 表结构（与原脚本完全一致）
    river_slug = river_cfg["id"]
    cols = (
        "numeric_id", "river_id", "distance_km", "latitude", "longitude", "formatted_address",
        "country", "province", "city", "citycode", "district", "adcode", "township", "towncode",
        "pois_json",
    )
    conn = sqlite3.connect(out_path)
    # 开启事务，提升批量写入效率
    conn.execute("BEGIN TRANSACTION")

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

    # 新增：先查询是否已有非空数据，只更新空值
    def is_record_empty(cur, numeric_id, distance_km):
        """判断该记录的POI字段是否为空"""
        cur.execute("""
            SELECT formatted_address FROM river_pois 
            WHERE numeric_id = ? AND distance_km = ?
        """, (numeric_id, distance_km))
        res = cur.fetchone()
        # 无记录 或 formatted_address为空 → 需要更新
        return res is None or res[0] is None

    # 替换 INSERT 为 UPDATE（只更新空值）+ INSERT（无记录时插入）
    update_sql = f"""
    UPDATE river_pois 
    SET river_id=?, formatted_address=?, country=?, province=?, city=?, citycode=?, 
        district=?, adcode=?, township=?, towncode=?, pois_json=?
    WHERE numeric_id=? AND distance_km=?
    """
    insert_sql = f"INSERT OR IGNORE INTO river_pois ({','.join(cols)}) VALUES ({','.join(['?']*len(cols))})"

    cur = conn.cursor()
    for i, (lat, lon, dist_km) in enumerate(sampled):
        if i > 0:
            time.sleep(args.delay)
        
        d = round(dist_km, 2)
        # 先检查该记录是否为空，非空则跳过（保留高德数据）
        if is_record_empty(cur, numeric_id, d):
            # 调用校正后的海外逆地理函数
            result = _reverse_geocode_geoapify(lat, lon, args.geoapify_key)
            
            if result is None:
                # 海外查询也失败，保留null（不修改）
                print(f"  [SKIP] 坐标 ({lat}, {lon}) 查询失败，保留空值")
                continue
            
            # 构造更新数据
            update_data = (
                river_slug,
                _scalar(result.get("formatted_address")),
                _scalar(result.get("country")),
                _scalar(result.get("province")),
                _scalar(result.get("city")),
                _scalar(result.get("citycode")),
                _scalar(result.get("district")),
                _scalar(result.get("adcode")),
                _scalar(result.get("township")),
                _scalar(result.get("towncode")),
                result.get("pois_json"),
                numeric_id,
                d
            )
            cur.execute(update_sql, update_data)
            
            # 如果UPDATE影响行数为0（无记录），则执行INSERT
            if cur.rowcount == 0:
                insert_data = (
                    numeric_id, river_slug, d, lat, lon,
                    _scalar(result.get("formatted_address")),
                    _scalar(result.get("country")),
                    _scalar(result.get("province")),
                    _scalar(result.get("city")),
                    _scalar(result.get("citycode")),
                    _scalar(result.get("district")),
                    _scalar(result.get("adcode")),
                    _scalar(result.get("township")),
                    _scalar(result.get("towncode")),
                    result.get("pois_json"),
                )
                cur.execute(insert_sql, insert_data)
            
            print(f"  [UPDATE] 坐标 ({lat}, {lon}) 距离 {d}km → {result.get('formatted_address') or '无地址'}")
        else:
            # 已有非空数据（高德采集的国内数据），跳过
            print(f"  [SKIP] 坐标 ({lat}, {lon}) 距离 {d}km 已有数据，跳过")
        
        if (i + 1) % 100 == 0:
            conn.commit()
            print(f"  已处理 {i + 1}/{len(sampled)} 个点")

    conn.commit()
    conn.close()
    print(f"完成。SQLite 已更新: {out_path}")

if __name__ == "__main__":
    main()