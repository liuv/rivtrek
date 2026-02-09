import json
import numpy as np
from pyproj import Geod
import os
import glob

KEYWORDS = ['长江', '金沙江', '通天河', '沱沱河', 'part']

def get_line_length(coords):
    geod = Geod(ellps="WGS84")
    if len(coords) < 2: return 0
    _, _, dist = geod.inv([p[0] for p in coords[:-1]], [p[1] for p in coords[:-1]], 
                          [p[0] for p in coords[1:]], [p[1] for p in coords[1:]])
    return np.sum(dist)

def extract_segments(f_path):
    with open(f_path, 'r', encoding='utf-8') as f:
        data = json.load(f)
    segments = []
    # 递归提取
    def _walk(obj):
        if isinstance(obj, dict):
            if obj.get('type') == 'LineString': segments.append(obj['coordinates'])
            elif obj.get('type') == 'MultiLineString': segments.extend(obj['coordinates'])
            else:
                for v in obj.values(): _walk(v)
        elif isinstance(obj, list):
            if len(obj) > 0 and isinstance(obj[0], (list, tuple)) and not isinstance(obj[0][0], list):
                if len(obj) > 1: segments.append(obj)
            else:
                for v in obj: _walk(v)
    _walk(data)
    return segments

def run_diagnostic():
    files = []
    for kw in KEYWORDS:
        files.extend(glob.glob(f"{kw}*.geojson"))
        files.extend(glob.glob(f"{kw}*.json"))
    files = sorted(list(set(files)))
    
    print("=== 长江里程差距诊断报告 ===")
    total_raw_len = 0
    all_segments = []
    
    file_stats = []
    for f in files:
        if 'full_50m' in f or 'waterwaymap' in f: continue
        segs = extract_segments(f)
        f_len = sum(get_line_length(s) for s in segs)
        total_raw_len += f_len
        file_stats.append((f, f_len / 1000))
        for s in segs:
            avg_lng = np.mean([p[0] for p in s])
            all_segments.append({'file': f, 'coords': s, 'len': get_line_length(s), 'lng': avg_lng})

    # 按文件名打印长度
    for name, length in sorted(file_stats, key=lambda x: x[1], reverse=True):
        print(f"📄 文件: {name:<15} | 长度: {length:>8.2f} km")

    print(f"\n全部原始片段总和: {total_raw_len/1000:.2f} km")
    
    # 查找断缝
    all_segments.sort(key=lambda x: x['lng'])
    print("\n--- 关键连接点分析 ---")
    for i in range(len(all_segments) - 1):
        s1 = all_segments[i]
        s2 = all_segments[i+1]
        
        # 计算 s1 尾到 s2 头的距离
        p1 = s1['coords'][-1]
        p2 = s2['coords'][0]
        geod = Geod(ellps="WGS84")
        _, _, gap = geod.inv(p1[0], p1[1], p2[0], p2[1])
        
        if gap > 1000: # 超过 1 公里的裂缝
            print(f"❌ 发现裂缝! {s1['file']} -> {s2['file']}")
            print(f"   距离: {gap/1000:.2f} km (这段里程在合并时会变为直线，从而丢失)")

    # 检查源头
    source_p = all_segments[0]['coords'][0]
    print(f"\n📍 当前数据最西端 (源头): {source_p}")
    print("   注: 长江正源格拉丹冬约在 91.1°E, 33.4°N。如果你的数据没到这里，说明缺了源头。")
    
    # 检查入海口
    mouth_p = all_segments[-1]['coords'][-1]
    print(f"📍 当前数据最东端 (入海口): {mouth_p}")
    print("   注: 长江口约在 121.9°E, 31.5°N。")

if __name__ == "__main__":
    run_diagnostic()