import json
import os
import numpy as np
from pyproj import Geod
import sys

# 输入输出配置
RIVER_CONFIGS = {
    'yangtze': {
        'name': '长江',
        'master_config': 'assets/json/rivers/yangtze_master.json',
        'full_path_suffix': 'yangtze_raw_path_50m.json',
        'output_points': 'assets/json/rivers/yangtze_points.json'
    },
    'yellow': {
        'name': '黄河',
        'master_config': 'assets/json/rivers/yellow_river_master.json',
        'full_path_suffix': 'yellow_river_raw_path_50m.json',
        'output_points': 'assets/json/rivers/yellow_river_points.json'
    }
}

DEFAULT_SPACING = 50

def process(river_key, spacing=DEFAULT_SPACING):
    if river_key not in RIVER_CONFIGS:
        print(f"❌ 未知的河流: {river_key}. 可用选项: {list(RIVER_CONFIGS.keys())}")
        return

    config = RIVER_CONFIGS[river_key]
    master_path = config['master_config']
    path_in = f'assets/json/rivers/{config["full_path_suffix"].replace("50m", f"{spacing}m")}'
    
    # 输出点位文件名处理
    points_out = config['output_points']
    if spacing != DEFAULT_SPACING:
        points_out = points_out.replace(".json", f"_{spacing}m.json")

    print(f"🚀 开始处理河流数据: {river_key} (间隔: {spacing}m)")

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

    # 2. 加载 GPS 路径
    if not os.path.exists(path_in):
        print(f"❌ 找不到 GPS 路径文件: {path_in}. 请先运行 merge_rivers.py")
        return

    with open(path_in, 'r', encoding='utf-8') as f:
        gps_data = json.load(f)
    coords = gps_data['coordinates']
    
    # 计算真实路径的累计里程
    geod = Geod(ellps="WGS84")
    real_dists = [0]
    for i in range(len(coords)-1):
        _, _, d = geod.inv(coords[i][0], coords[i][1], coords[i+1][0], coords[i+1][1])
        real_dists.append(real_dists[-1] + d/1000.0)
    
    # 3. 核心修正系数
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
    # 分离后的 points 数据
    points_data = {
        "river_name": master_data['game_challenge_name'],
        "correction_coefficient": round(k, 6),
        "sections_points": [sub['points_list'] for sub in all_sub_sections]
    }
    
    # 更新 master 数据 (元数据)
    master_data['correction_coefficient'] = round(k, 6)
    master_data['real_path_km'] = round(real_dists[-1], 2)
    # 移除临时的辅助字段
    for sub in all_sub_sections:
        sub.pop('target_end_km', None)
        sub.pop('points_list', None)

    # 6. 保存文件
    # 更新原有的 master 文件
    with open(master_path, 'w', encoding='utf-8') as f:
        json.dump(master_data, f, ensure_ascii=False, indent=2)
    
    # 保存分离出的 points 文件
    with open(points_out, 'w', encoding='utf-8') as f:
        json.dump(points_data, f, ensure_ascii=False, separators=(',', ':'))
    
    print(f"✅ 处理完成！")
    print(f"修正系数: {k:.4f}")
    print(f"💾 已更新业务配置: {master_path}")
    print(f"💾 已生成坐标点集: {points_out}")
    print(f"📊 包含 {len(all_sub_sections)} 个子路段，总里程 {target_total_km}km")

if __name__ == "__main__":
    river = sys.argv[1] if len(sys.argv) > 1 else 'yangtze'
    dist = int(sys.argv[2]) if len(sys.argv) > 2 else DEFAULT_SPACING
    process(river, dist)

