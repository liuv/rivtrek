import json
import numpy as np
from pyproj import Geod
from scipy.interpolate import interp1d
import os
import glob
import sys

# 河流配置
RIVER_CONFIGS = {
    'yangtze': {
        'name': '长江',
        'keywords': ['长江', '金沙江', '通天河', '沱沱河'],
        'output_suffix': 'yangtze_raw_path_50m.json'
    },
    'yellow': {
        'name': '黄河',
        'keywords': ['黄河'],
        'output_suffix': 'yellow_river_raw_path_50m.json'
    }
}

DEFAULT_SPACING = 50
MAX_GAP_METERS = 20000  # 放宽到 20 公里，适应水库等区域的间断

def get_line_length(coords):
    if len(coords) < 2: return 0
    geod = Geod(ellps="WGS84")
    lons, lats = [p[0] for p in coords], [p[1] for p in coords]
    _, _, dists = geod.inv(lons[:-1], lats[:-1], lons[1:], lats[1:])
    return np.sum(dists)

def smart_merge(river_key, spacing=DEFAULT_SPACING):
    if river_key not in RIVER_CONFIGS:
        print(f"❌ 未知的河流: {river_key}. 可用选项: {list(RIVER_CONFIGS.keys())}")
        return

    config = RIVER_CONFIGS[river_key]
    keywords = config['keywords']
    output_file = f'assets/json/rivers/{config["output_suffix"].replace("50m", f"{spacing}m")}'
    
    print(f"🚀 开始合并河流: {config['name']} (间隔: {spacing}m)")
    
    files = []
    for kw in keywords:
        files.extend(glob.glob(f"tools/{kw}*.geojson"))
        files.extend(glob.glob(f"tools/{kw}*.json"))
    files = sorted(list(set(files)))
    
    if not files:
        print(f"⚠️ 未找到匹配的 GeoJSON/JSON 文件，关键词: {keywords}")
        return

    all_segs = []
    for f_path in files:
        if 'full' in f_path: continue
        with open(f_path, 'r', encoding='utf-8') as f:
            data = json.load(f)
            temp = []
            def _walk(obj):
                if isinstance(obj, dict):
                    if obj.get('type') == 'LineString': temp.append(obj['coordinates'])
                    elif obj.get('type') == 'MultiLineString': temp.extend(obj['coordinates'])
                    else: [ _walk(v) for v in obj.values() if isinstance(v, (dict, list)) ]
                elif isinstance(obj, list):
                    if len(obj) > 0 and isinstance(obj[0], list) and not isinstance(obj[0][0], list): temp.append(obj)
                    else: [ _walk(v) for v in obj if isinstance(v, (dict, list)) ]
            _walk(data)
            for i, s in enumerate(temp):
                if len(s) >= 2: all_segs.append({"coords": list(s), "file": os.path.basename(f_path), "id": i})

    if not all_segs:
        print("❌ 未在文件中找到有效的 LineString 数据")
        return

    # 1. 找最西边的段作为起点
    all_segs.sort(key=lambda x: min(p[0] for p in x['coords']))
    first = all_segs.pop(0)
    merged_path = list(first['coords'])
    if merged_path[0][0] > merged_path[-1][0]: merged_path = merged_path[::-1]
    
    total_real_river_len = get_line_length(merged_path)
    
    print(f"\n{'文件名':<20} | {'段号':<4} | {'净长度(km)':<10} | {'累计干流(km)'}")
    print("-" * 65)
    print(f"{first['file']:<20} | {first['id']:<4} | {total_real_river_len/1000:>10.2f} | {total_real_river_len/1000:>10.2f}")

    geod = Geod(ellps="WGS84")
    
    # 2. 严格按地理顺序拼接
    while all_segs:
        tail = merged_path[-1]
        best_idx, best_dist, is_rev = -1, float('inf'), False
        
        for i, s in enumerate(all_segs):
            c = s['coords']
            _, _, d_h = geod.inv(tail[0], tail[1], c[0][0], c[0][1])
            _, _, d_t = geod.inv(tail[0], tail[1], c[-1][0], c[-1][1])
            if d_h < best_dist: best_dist, best_idx, is_rev = d_h, i, False
            if d_t < best_dist: best_dist, best_idx, is_rev = d_t, i, True
        
        if best_idx == -1 or best_dist > MAX_GAP_METERS:
            reason = "距离太远" if best_dist > MAX_GAP_METERS else "没有符合流向的数据"
            print(f"\n--- 拼接自然结束：{reason} ({best_dist/1000:.2f} km) ---")
            break 
            
        target = all_segs.pop(best_idx)
        next_coords = list(target['coords'])
        if is_rev: next_coords = next_coords[::-1]
        
        seg_len = get_line_length(next_coords)
        merged_path.extend(next_coords[1:])
        total_real_river_len += seg_len
        print(f"{target['file']:<20} | {target['id']:<4} | {seg_len/1000:>10.2f} | {total_real_river_len/1000:>10.2f}")

    # 3. 生成插值点
    coords = np.array(merged_path)
    mask = np.ones(len(coords), dtype=bool); mask[1:] = np.any(np.diff(coords, axis=0) != 0, axis=1)
    coords = coords[mask]
    
    actual_dists = [0]
    for i in range(len(coords)-1):
        _, _, d = geod.inv(coords[i][0], coords[i][1], coords[i+1][0], coords[i+1][1])
        actual_dists.append(actual_dists[-1] + d)
    
    visual_path_len = actual_dists[-1]
    target_d = np.arange(0, visual_path_len, spacing)
    f_lng = interp1d(actual_dists, coords[:, 0], kind='linear', fill_value="extrapolate")
    f_lat = interp1d(actual_dists, coords[:, 1], kind='linear', fill_value="extrapolate")
    final_points = [[round(float(f_lng(d)), 6), round(float(f_lat(d)), 6)] for d in target_d]
    
    res = {
        "river_name": f"{config['name']}全流路 (物理逻辑版)", 
        "total_km": round(total_real_river_len/1000, 2), 
        "point_count": len(final_points), 
        "coordinates": final_points
    }
    
    os.makedirs(os.path.dirname(output_file), exist_ok=True)
    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(res, f, ensure_ascii=False, separators=(',', ':'))
    
    print(f"\n✅ 合并与插值完成！")
    print(f"📊 最终统计：")
    print(f"   - 真实干流净长: {total_real_river_len/1000:.2f} km")
    print(f"   - 落地文件: {output_file}")

if __name__ == "__main__":
    river = sys.argv[1] if len(sys.argv) > 1 else 'yangtze'
    dist = int(sys.argv[2]) if len(sys.argv) > 2 else DEFAULT_SPACING
    smart_merge(river, dist)
