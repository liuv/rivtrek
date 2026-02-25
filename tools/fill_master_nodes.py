#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
补齐 master JSON 中缺失的节点（sub_section）与根级字段，使结构与 songhua_river_master 等完整版一致。
不覆盖已有字段，只补充缺失项。需在项目根目录执行。

用法:
  python tools/fill_master_nodes.py nu_river
  python tools/fill_master_nodes.py lmekong_river --dry-run
"""
import json
import os
import argparse

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MASTER_DIR = os.path.join(ROOT, "assets", "json", "rivers")


def _river_prefix(master_base: str) -> str:
    """从 master_base 得到 medal_id 前缀，如 nu_river -> nu, yangtze -> yangtze."""
    if master_base.endswith("_river"):
        return master_base[:-6]
    return master_base


def _infer_difficulty_rating(game_difficulty: str) -> int:
    """从 game_difficulty 文本推断难度 1-5."""
    if not game_difficulty:
        return 3
    s = game_difficulty.strip()
    if "高" in s and "中" not in s:
        return 4
    if "中" in s or "中-" in s:
        return 3
    if "低" in s:
        return 2
    return 3


# section theme_color 轮换，与 songhua 风格一致
SECTION_THEME_COLORS = ["#A5C9E1", "#C85A3C", "#5C9E7B", "#8B7355", "#6B8E9E", "#9B7B8C", "#7A9E6B"]


def fill_root(data: dict, master_base: str) -> None:
    """补全根级缺失字段."""
    prefix = _river_prefix(master_base)
    root_defaults = [
        ("challenge_id", f"{master_base}_epic_001"),
        ("version", "2026.02.14.01"),
        ("author", "WaveChaser Team"),
        ("difficulty_stars", 4),
        ("default_theme_color", "#4A90E2"),
        ("cover_asset", f"covers/{master_base}_cover.png"),
    ]
    for key, default in root_defaults:
        if key not in data:
            data[key] = default


def fill_section(sec: dict, section_index: int) -> None:
    """补全 section 缺失的 theme_color."""
    if "theme_color" not in sec:
        sec["theme_color"] = SECTION_THEME_COLORS[section_index % len(SECTION_THEME_COLORS)]


def fill_sub_section(sub: dict, prefix: str) -> None:
    """补全单个 sub_section 缺失字段."""
    sub_id = sub.get("sub_section_id", 0)
    # 游戏/环境相关
    if "difficulty_rating" not in sub:
        sub["difficulty_rating"] = _infer_difficulty_rating(sub.get("game_difficulty", ""))
    if "base_flow_speed" not in sub:
        sub["base_flow_speed"] = 0.5
    if "environment_type" not in sub:
        sub["environment_type"] = "plateau_glacier"
    if "bg_asset" not in sub:
        sub["bg_asset"] = "JaggedPeaks/001.png"
    if "ambient_sound" not in sub:
        sub["ambient_sound"] = "wind_plateau"

    ach = sub.get("achievement")
    if not isinstance(ach, dict):
        sub["achievement"] = ach = {}
    if "medal_id" not in ach:
        ach["medal_id"] = f"medal_{prefix}_{sub_id}"
    if "medal_icon" not in ach:
        ach["medal_icon"] = f"icons/medal_{prefix}_{sub_id}.webp"


def process(master_base: str, dry_run: bool = False) -> None:
    master_path = os.path.join(MASTER_DIR, f"{master_base}_master.json")
    if not os.path.isfile(master_path):
        print(f"❌ 找不到: {master_path}")
        return

    with open(master_path, "r", encoding="utf-8") as f:
        data = json.load(f)

    fill_root(data, master_base)
    prefix = _river_prefix(master_base)
    for i, sec in enumerate(data.get("challenge_sections", [])):
        fill_section(sec, i)
        for sub in sec.get("sub_sections", []):
            fill_sub_section(sub, prefix)

    if dry_run:
        print(f"[dry-run] 将写入 {master_path}")
        print(json.dumps(data, ensure_ascii=False, indent=2)[:2000] + "\n...")
        return

    # 根级字段顺序与 songhua 一致，便于阅读
    root_order = [
        "game_challenge_name", "challenge_id", "version", "author",
        "total_length_km", "total_sections", "total_sub_sections",
        "difficulty_stars", "default_theme_color", "cover_asset",
        "challenge_sections",
    ]
    ordered = {k: data[k] for k in root_order if k in data}
    for k, v in data.items():
        if k not in ordered:
            ordered[k] = v
    data = ordered

    with open(master_path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

    print(f"✅ 已补齐: {master_path}")


def main():
    parser = argparse.ArgumentParser(
        description="补齐 master JSON 中缺失的节点与根级字段（参考 songhua 等完整版）"
    )
    parser.add_argument(
        "master_base",
        help="master 文件名前缀，如 nu_river、lmekong_river",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="只打印将要写入的内容，不写文件",
    )
    args = parser.parse_args()
    process(args.master_base, dry_run=args.dry_run)


if __name__ == "__main__":
    main()
