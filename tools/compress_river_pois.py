#!/usr/bin/env python3
"""
对 river_pois 表做「变化点」压缩：只保留 (formatted_address, pois_json) 发生变化的行，
同一河段内连续相同地址/POI 的中间点删除。表结构与主键不变，getNearestPoi 的「前后各查一次取更近」逻辑仍适用。

用法:
  python3 compress_river_pois.py
  python3 compress_river_pois.py --db tools/out/river_pois.db
  python3 compress_river_pois.py --db tools/out/river_pois.db --dry-run
"""

import argparse
import os
import sqlite3

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main() -> None:
    parser = argparse.ArgumentParser(description="按变化点压缩 river_pois，减少行数")
    parser.add_argument(
        "--db",
        default=os.path.join(ROOT, "tools", "out", "river_pois.db"),
        help="SQLite 文件路径",
    )
    parser.add_argument("--dry-run", action="store_true", help="只打印将保留的行数，不写回")
    args = parser.parse_args()

    if not os.path.isfile(args.db):
        raise SystemExit(f"数据库不存在: {args.db}")

    conn = sqlite3.connect(args.db)
    conn.row_factory = sqlite3.Row
    cur = conn.execute(
        "SELECT * FROM river_pois ORDER BY numeric_id, distance_km"
    )
    rows = cur.fetchall()
    if not rows:
        conn.close()
        print("表 river_pois 为空，无需压缩")
        return

    cols = [d[0] for d in cur.description]
    # 按 (numeric_id, formatted_address, pois_json) 变化保留：每河第一条必留，之后仅当 address 或 pois 变化才留
    kept = []
    prev_nid = prev_addr = prev_pois = None
    for row in rows:
        nid = row["numeric_id"]
        addr = row["formatted_address"] or ""
        pois = row["pois_json"] or ""
        if prev_nid != nid or prev_addr != addr or prev_pois != pois:
            kept.append(row)
            prev_nid, prev_addr, prev_pois = nid, addr, pois

    print(f"原行数: {len(rows)}, 保留行数: {len(kept)}, 减少: {len(rows) - len(kept)}")

    if args.dry_run:
        conn.close()
        return

    placeholders = ",".join(["?"] * len(cols))
    conn.execute("DELETE FROM river_pois")
    conn.executemany(
        f"INSERT INTO river_pois ({','.join(cols)}) VALUES ({placeholders})",
        [[row[c] for c in cols] for row in kept],
    )
    conn.commit()
    conn.close()
    print(f"已写回: {args.db}")


if __name__ == "__main__":
    main()
