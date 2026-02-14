#!/usr/bin/env python3
"""
仅请求 3 个采样点的逆地理，并打印完整返回 JSON，用于确认 POI 数据样式。支持天地图与高德。

用法（在项目根目录）:
  # 天地图
  python3 tools/test_poi_three_points.py --provider tianditu --tk YOUR_TK
  # 高德（数据通常更细致）
  python3 tools/test_poi_three_points.py --provider amap --key YOUR_AMAP_KEY
  python3 tools/test_poi_three_points.py --river yangtze --step 5 --provider amap --key YOUR_KEY
"""

import argparse
import json
import os
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load_master_section_lengths(master_path: str):
    with open(master_path, "r", encoding="utf-8") as f:
        m = json.load(f)
    return [
        (sub["sub_section_length_km"], sub["accumulated_length_km"])
        for sec in m["challenge_sections"]
        for sub in sec["sub_sections"]
    ]


def load_points_with_distance_km(points_path: str, section_lengths: list):
    with open(points_path, "r", encoding="utf-8") as f:
        p = json.load(f)
    sections = p["sections_points"]
    out = []
    for i, section in enumerate(sections):
        sec_len, _ = section_lengths[i]
        acc_start = 0.0 if i == 0 else section_lengths[i - 1][1]
        n = len(section)
        for j, pt in enumerate(section):
            lng, lat = float(pt[0]), float(pt[1])
            dist = acc_start + (j / (n - 1) if n > 1 else 0) * sec_len
            out.append((lat, lng, dist))
    return out


def sample_by_km(points: list, step_km: float):
    if not points:
        return []
    sampled, target, max_km, idx = [], 0.0, points[-1][2], 0
    while target <= max_km and idx < len(points):
        while idx < len(points) and points[idx][2] < target:
            idx += 1
        if idx >= len(points):
            break
        if idx == 0:
            best = points[0]
        else:
            prev, curr = points[idx - 1], points[idx]
            best = prev if abs(prev[2] - target) <= abs(curr[2] - target) else curr
        sampled.append(best)
        target += step_km
        if points[idx][2] <= target:
            idx += 1
    return sampled


def request_tianditu_raw(lat: float, lon: float, tk: str) -> dict:
    """天地图逆地理，返回完整响应。"""
    post_str = f"{{'lon': {lon}, 'lat': {lat}, 'ver': 1}}"
    url = f"http://api.tianditu.gov.cn/geocoder?type=geocode&tk={tk}&postStr={urllib.parse.quote(post_str)}"
    req = urllib.request.Request(url, headers={"User-Agent": "RivtrekPOI/1.0"})
    with urllib.request.urlopen(req, timeout=15) as resp:
        return json.loads(resp.read().decode())


def request_amap_raw(lat: float, lon: float, key: str) -> dict:
    """高德逆地理，返回完整响应。location=经度,纬度；extensions=base 仅地址，all 含周边 POI。"""
    location = f"{lon},{lat}"
    url = f"https://restapi.amap.com/v3/geocode/regeo?key={urllib.parse.quote(key)}&location={location}&extensions=all"
    req = urllib.request.Request(url, headers={"User-Agent": "RivtrekPOI/1.0"})
    with urllib.request.urlopen(req, timeout=15) as resp:
        return json.loads(resp.read().decode())


def main():
    parser = argparse.ArgumentParser(description="测试 3 个点，打印逆地理完整返回（支持天地图/高德）")
    parser.add_argument("--provider", choices=["tianditu", "amap"], default="tianditu", help="数据源")
    parser.add_argument("--tk", default=None, help="天地图 API 密钥（provider=tianditu 时必填）")
    parser.add_argument("--key", default=None, help="高德 Web 服务 Key（provider=amap 时必填）")
    parser.add_argument("--river", default="yangtze", help="河流 id")
    parser.add_argument("--step", type=float, default=5.0, help="采样间隔(km)")
    args = parser.parse_args()

    if args.provider == "tianditu" and not args.tk:
        raise SystemExit("使用天地图时请提供 --tk")
    if args.provider == "amap" and not args.key:
        raise SystemExit("使用高德时请提供 --key")

    points_path = os.path.join(ROOT, "assets", "json", "rivers", f"{args.river}_points.json")
    master_path = os.path.join(ROOT, "assets", "json", "rivers", f"{args.river}_master.json")
    if not os.path.isfile(points_path) or not os.path.isfile(master_path):
        raise SystemExit("文件不存在，请指定 --river 且保证 assets 下有点位与 master 文件")

    section_lengths = load_master_section_lengths(master_path)
    points = load_points_with_distance_km(points_path, section_lengths)
    sampled = sample_by_km(points, args.step)
    three = sampled[:3]
    print(f"数据源: {args.provider}  采样间隔 {args.step} km，共 {len(sampled)} 个采样点；本次仅请求前 3 个:\n")

    for i, (lat, lon, dist_km) in enumerate(three):
        print("=" * 60)
        print(f"第 {i + 1} 个点  里程≈{dist_km:.1f} km  坐标 ({lat}, {lon})")
        print("=" * 60)
        try:
            if args.provider == "tianditu":
                raw = request_tianditu_raw(lat, lon, args.tk)
            else:
                raw = request_amap_raw(lat, lon, args.key)
            print(json.dumps(raw, indent=2, ensure_ascii=False))
        except Exception as e:
            print(f"请求失败: {e}")
        print()
    print("以上为逆地理完整返回。确认无误后可用 fetch_river_pois.py 全量（加 --provider 与 --tk/--key，可选 --from 0 --to N）。")


if __name__ == "__main__":
    main()
