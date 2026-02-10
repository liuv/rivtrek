import json
import os
import numpy as np
from pyproj import Geod
import sys
import argparse

def process(master_base, spacing=50):
    """
    master_base: 配置文件基础名，如 "yangtze" 或 "songhua_river"
    """
    master_path = f'assets/json/rivers/{master_base}_master.json'
    raw_path_in = f'assets/json/rivers/{master_base}_raw_path_{spacing}m.json'
    points_out = f'assets/json/rivers/{master_base}_points.json'
    
    # 如果是非标准 50m，输出点位文件名带上间隔
    if spacing != 50:
        points_out = points_out.replace(".json", f"_{spacing}m.json")

    print(f"🚀 开始分割河流数据: {master_base} (间隔: {spacing}m)")

    # 1. 加载主配置文件 (master)
    if not os.path.exists(master_path):
        print(f"❌ 找不到主配置文件: {master_path}")
        return
    
    with open(master_path, 'r', encoding='utf-8') as f:
        master_data = json.load(f)
    target_total_km = master_data['total_length_km']
    
    # 展平所有的 sub_sections 用于分配点位
    all_sub_sections = []
    for section in master_data['challenge_sections']:
        for sub in section['sub_sections']:
            all_sub_sections.append(sub)
    
    # 计算每个 sub_section 的累计截止里程
    acc = 0
    for sub in all_sub_sections:
        acc += sub['sub_section_length_km']
        sub['target_end_km'] = acc
        sub['points_list'] = [] # 临时存放点位

    # 2. 加载 Raw GPS 路径
    if not os.path.exists(raw_path_in):
        print(f"❌ 找不到原始路径文件: {raw_path_in}. 请先运行 merge_rivers.py")
        return

    with open(raw_path_in, 'r', encoding='utf-8') as f:
        gps_data = json.load(f)
    coords = gps_data['coordinates']
    
    # 计算真实路径的累计里程
    geod = Geod(ellps="WGS84")
    real_dists = [0]
    for i in range(len(coords)-1):
        _, _, d = geod.inv(coords[i][0], coords[i][1], coords[i+1][0], coords[i+1][1])
        real_dists.append(real_dists[-1] + d/1000.0)
    
    # 3. 核心修正系数 (目标长度 / 实际长度)
    k = target_total_km / real_dists[-1]
    
    # 4. 顺着路径“装填”分段 (按 sub_section)
    curr_sub_idx = 0
    for i, p in enumerate(coords):
        mapped_km = real_dists[i] * k
        
        if curr_sub_idx < len(all_sub_sections):
            all_sub_sections[curr_sub_idx]['points_list'].append([p[0], p[1]])
            
            # 越界判定
            if mapped_km >= all_sub_sections[curr_sub_idx]['target_end_km']:
                # 保证平滑，下一段开头包含上一段结尾点
                if curr_sub_idx + 1 < len(all_sub_sections):
                    all_sub_sections[curr_sub_idx + 1]['points_list'].append([p[0], p[1]])
                curr_sub_idx += 1

    # 5. 准备输出数据
    points_data = {
        "river_name": master_data['game_challenge_name'],
        "correction_coefficient": round(k, 6),
        "sections_points": [sub['points_list'] for sub in all_sub_sections]
    }
    
    # 更新 master 数据
    master_data['correction_coefficient'] = round(k, 6)
    master_data['real_path_km'] = round(real_dists[-1], 2)
    # 移除临时的辅助字段
    for sub in all_sub_sections:
        sub.pop('target_end_km', None)
        sub.pop('points_list', None)

    # 6. 保存文件
    with open(master_path, 'w', encoding='utf-8') as f:
        json.dump(master_data, f, ensure_ascii=False, indent=2)
    
    with open(points_out, 'w', encoding='utf-8') as f:
        json.dump(points_data, f, ensure_ascii=False, separators=(',', ':'))
    
    print(f"✅ 处理完成！修正系数: {k:.4f}")
    print(f"💾 已更新配置: {master_path}")
    print(f"💾 已生成点位: {points_out}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='河流数据分割工具')
    parser.add_argument('master_base', help='主配置文件基础名，如 "songhua_river"')
    parser.add_argument('--spacing', type=int, default=50, help='插值间隔（米），默认50')
    
    args = parser.parse_args()
    process(args.master_base, args.spacing)
