#!/usr/bin/env python3
"""
验证「按行进距离查 river_pois 最近 POI」的算法，与 App 端 DatabaseService.getNearestPoi 逻辑一致。

DB 的 distance_km 与 fetch_river_pois 写入一致，为挑战累计里程；查库直接用 accumulated_km，不乘修正系数。

用法:
  python3 tools/verify_poi_lookup.py --db assets/db/rivtrek_base.db --river yangtze
  python3 tools/verify_poi_lookup.py --db assets/db/rivtrek_base.db --river 1   # 1 表示 numeric_id=1（长江）

算法（与 lib/services/database_service.dart 一致）:
  1. path_km = accumulated_km（行进距离即挑战里程）
  2. before = 查 numeric_id = ? AND distance_km <= path_km，ORDER BY distance_km DESC，limit 1
  3. after  = 查 numeric_id = ? AND distance_km >= path_km，ORDER BY distance_km ASC，limit 1
  4. 若 before 空则返回 after（或 null）；若 after 空则返回 before；否则取离 path_km 更近的一条
"""

import argparse
import json
import os
import sys
import sqlite3


def _first_poi_name(pois_json_str: str | None) -> str:
    """从 pois_json 取第一个 POI 的 name，供输出预览。"""
    if not pois_json_str or not pois_json_str.strip():
        return ""
    try:
        arr = json.loads(pois_json_str)
        if isinstance(arr, list) and arr and isinstance(arr[0], dict):
            return (arr[0].get("name") or "").strip()
    except (json.JSONDecodeError, TypeError):
        pass
    return ""

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONFIG_PATH = os.path.join(ROOT, "assets", "json", "rivers", "rivers_config.json")


def load_rivers_config():
    with open(CONFIG_PATH, "r", encoding="utf-8") as f:
        data = json.load(f)
    return data.get("rivers") or []


def get_river_by_id(rivers: list, river_id: str) -> dict | None:
    for r in rivers:
        if r.get("id") == river_id:
            return r
    return None


def get_river_by_numeric_id(rivers: list, numeric_id: int) -> dict | None:
    for r in rivers:
        if r.get("numeric_id") == numeric_id:
            return r
    return None


def resolve_river(rivers: list, river_arg: str) -> dict | None:
    """--river 支持字符串 id（如 yangtze）或 numeric_id（如 1）。"""
    cfg = get_river_by_id(rivers, river_arg)
    if cfg:
        return cfg
    try:
        nid = int(river_arg)
        return get_river_by_numeric_id(rivers, nid)
    except ValueError:
        return None


def main():
    parser = argparse.ArgumentParser(description="验证 getNearestPoi 查库逻辑")
    parser.add_argument("--db", default=None, help="rivtrek_base.db 路径（默认 assets/db 或 tools/out）")
    parser.add_argument("--river", default="yangtze", help="河流 id（如 yangtze）或 numeric_id（如 1）")
    parser.add_argument("--test-km", nargs="*", type=float, default=[0, 1, 5, 10, 50, 100, 500, 1000, 3000], help="要测试的 accumulated_km 列表")
    args = parser.parse_args()

    rivers = load_rivers_config()
    river_cfg = resolve_river(rivers, args.river)
    if not river_cfg:
        ids = [r.get("id") for r in rivers if r.get("id")]
        nids = [r.get("numeric_id") for r in rivers if r.get("numeric_id") is not None]
        print(f"错误: 未知河流 '{args.river}'。可用 id: {', '.join(ids)}，numeric_id: {nids}", flush=True)
        raise SystemExit(1)

    numeric_id = int(river_cfg["numeric_id"])
    river_id = river_cfg.get("id", "")
    print(f"河流: {river_cfg.get('name')} (id={river_id}, numeric_id={numeric_id})", flush=True)
    print("查库: path_km = accumulated_km（行进距离，不乘修正系数）", flush=True)
    print(flush=True)

    db_path = args.db
    if not db_path:
        for candidate in [
            os.path.join(ROOT, "assets", "db", "rivtrek_base.db"),
            os.path.join(ROOT, "tools", "out", "rivtrek_base.db"),
        ]:
            if os.path.isfile(candidate):
                db_path = candidate
                break
    if db_path and not os.path.isabs(db_path) and not os.path.isfile(db_path):
        db_path_under_root = os.path.join(ROOT, db_path)
        if os.path.isfile(db_path_under_root):
            db_path = db_path_under_root
    if not db_path or not os.path.isfile(db_path):
        print(f"错误: 未找到 DB 文件: {args.db or '(默认)'}", flush=True)
        raise SystemExit(1)
    print(f"DB: {db_path}", flush=True)
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    cur = conn.execute(
        "SELECT MIN(distance_km) as lo, MAX(distance_km) as hi, COUNT(*) as n FROM river_pois WHERE numeric_id = ?",
        (numeric_id,),
    )
    row = cur.fetchone()
    if not row or row["n"] == 0:
        print(f"该河流 (numeric_id={numeric_id}) 在 river_pois 中无数据。请先用 fetch_river_pois.py 为该河流打 POI 数据。", flush=True)
        conn.close()
        raise SystemExit(1)
    print(f"river_pois 范围: distance_km ∈ [{row['lo']}, {row['hi']}], 共 {row['n']} 条", flush=True)
    print(flush=True)

    cols = [r[1] for r in conn.execute("PRAGMA table_info(river_pois)").fetchall()]
    test_km = args.test_km if args.test_km else [0, 1, 5, 10, 50, 100, 500, 1000]

    print("按 accumulated_km 查最近 POI（与 App 一致）:", flush=True)
    print("-" * 60, flush=True)
    for acc_km in test_km:
        path_km = acc_km
        cur = conn.execute(
            "SELECT * FROM river_pois WHERE numeric_id = ? AND distance_km <= ? ORDER BY distance_km DESC LIMIT 1",
            (numeric_id, path_km),
        )
        before = cur.fetchone()
        cur = conn.execute(
            "SELECT * FROM river_pois WHERE numeric_id = ? AND distance_km >= ? ORDER BY distance_km ASC LIMIT 1",
            (numeric_id, path_km),
        )
        after = cur.fetchone()
        if before is None and after is None:
            print(f"  accumulated_km={acc_km:.1f}  path_km={path_km:.2f}  -> 无结果 (before/after 皆空)", flush=True)
            continue
        if before is None:
            chosen = after
            side = "after"
        elif after is None:
            chosen = before
            side = "before"
        else:
            d_before = before["distance_km"]
            d_after = after["distance_km"]
            chosen = before if (path_km - d_before) <= (d_after - path_km) else after
            side = "before" if chosen == before else "after"
        dist = chosen["distance_km"]
        addr = chosen["formatted_address"] or " ".join(
            str(x or "") for x in (chosen["province"], chosen["city"], chosen["district"])
        )
        addr_preview = (addr or "")[:48] + "..." if len(addr or "") > 48 else (addr or "")
        pois_json = chosen["pois_json"] if "pois_json" in chosen.keys() else None
        poi_name = _first_poi_name(pois_json)
        poi_suffix = f"  POI: {poi_name}" if poi_name else ""
        print(f"  accumulated_km={acc_km:.1f}  path_km={path_km:.2f}  -> distance_km={dist} ({side})  {addr_preview}{poi_suffix}", flush=True)
    conn.close()
    print(flush=True)
    print("若 0 有结果、大里程无结果，常见原因：", flush=True)
    print("  1) DB 中该河流只有前几公里有数据（例如只跑了 --from 0 --to 2）", flush=True)
    print("  2) numeric_id 与 DB 中写入的不一致（config 与打库时用的 config 不同）", flush=True)
    print("  3) 该河流 POI 表为空或逆地理时地址多为空", flush=True)
    print(flush=True)
    print("与 App 逻辑一致：path_km=accumulated_km，before/after 取更近。若 App 内 1km 就查不到：", flush=True)
    print("  1) 确保 assets/db/rivtrek_base.db 与当前验证用的 DB 一致并已重新 build", flush=True)
    print("  2) 检查 RiverRepository.ensureLoaded() 已执行且 getRiverSlugToNumericId()[riverId] 有值", flush=True)
    print("  3) 若 baseDatabase 加载失败（asset 缺失等）或查询抛错，getNearestPoi 会静默返回 null", flush=True)
    sys.stdout.flush()


if __name__ == "__main__":
    main()
