import json
import numpy as np
from pyproj import Geod
from scipy.interpolate import interp1d
import os
import glob
import heapq
import argparse

def get_line_length(coords):
    if len(coords) < 2: return 0
    geod = Geod(ellps="WGS84")
    lons, lats = [p[0] for p in coords], [p[1] for p in coords]
    _, _, dists = geod.inv(lons[:-1], lats[:-1], lons[1:], lats[1:])
    return np.sum(dists)

def get_dist(p1, p2):
    geod = Geod(ellps="WGS84")
    _, _, d = geod.inv(p1[0], p1[1], p2[0], p2[1])
    return d

def smart_merge(pattern, output_base, spacing=50):
    output_file = f'assets/json/rivers/{output_base}_raw_path_{spacing}m.json'
    print(f"🚀 重新重构：长路径拓扑提取模式")
    
    files = []
    for p in pattern.split('|'):
        glob_p = p if '*' in p or '?' in p else f"{p}*"
        files.extend(glob.glob(f"tools/{glob_p}.geojson"))
        files.extend(glob.glob(f"tools/{glob_p}.json"))
    files = sorted(list(set(files)))
    
    all_segments = []
    for f_path in files:
        if '_raw_path_' in f_path or '_points' in f_path: continue
        with open(f_path, 'r', encoding='utf-8') as f:
            data = json.load(f); file_segs = []
            def _walk(obj):
                if isinstance(obj, dict):
                    if obj.get('type') == 'LineString': file_segs.append(obj['coordinates'])
                    elif obj.get('type') == 'MultiLineString': file_segs.extend(obj['coordinates'])
                    else: [ _walk(v) for v in obj.values() if isinstance(v, (dict, list)) ]
                elif isinstance(obj, list):
                    if len(obj) > 0 and isinstance(obj[0], list) and not isinstance(obj[0][0], list): file_segs.append(obj)
                    else: [ _walk(v) for v in obj if isinstance(v, (dict, list)) ]
            _walk(data)
            for s in file_segs:
                if len(s) >= 2: all_segments.append({"coords": s, "len": get_line_length(s), "file": os.path.basename(f_path)})

    if not all_segments: return

    # 逻辑核心：全量拓扑拼接（种子增长法，但允许更聪明的方向选择）
    # 选最长的一段作为主干种子
    all_segments.sort(key=lambda x: x['len'], reverse=True)
    current_main = list(all_segments.pop(0)['coords'])
    
    while True:
        changed = False
        head, tail = current_main[0], current_main[-1]
        
        best_match_idx = -1
        best_d = 50000 # 50km 阈值，适应可能的断缺
        target_pos = "" # 'head' or 'tail'
        should_reverse = False
        
        for i, seg in enumerate(all_segments):
            s = seg['coords']
            # 四种衔接可能
            d_tail_start = get_dist(tail, s[0])
            d_tail_end = get_dist(tail, s[-1])
            d_head_end = get_dist(head, s[-1])
            d_head_start = get_dist(head, s[0])
            
            opts = [
                (d_tail_start, 'tail', False),
                (d_tail_end, 'tail', True),
                (d_head_end, 'head', False),
                (d_head_start, 'head', True)
            ]
            
            d, pos, rev = min(opts, key=lambda x: x[0])
            if d < best_d:
                best_d, best_match_idx, target_pos, should_reverse = d, i, pos, rev
        
        if best_match_idx != -1:
            match_seg = all_segments.pop(best_match_idx)['coords']
            if should_reverse: match_seg = match_seg[::-1]
            
            if target_pos == 'tail':
                current_main.extend(match_seg[1:])
            else:
                current_main = match_seg[:-1] + current_main
            changed = True
        else:
            break

    total_km = get_line_length(current_main)
    print(f"✅ 合并完成！总里程: {total_km/1000:.2f} km")

    # 插值与输出
    coords = np.array(current_main); mask = np.ones(len(coords), dtype=bool); mask[1:] = np.any(np.diff(coords, axis=0) != 0, axis=1); coords = coords[mask]
    actual_dists = [0]; geod = Geod(ellps="WGS84")
    for i in range(len(coords)-1): _, _, d = geod.inv(coords[i][0], coords[i][1], coords[i+1][0], coords[i+1][1]); actual_dists.append(actual_dists[-1] + d)
    target_d = np.arange(0, actual_dists[-1], spacing); f_lng = interp1d(actual_dists, coords[:, 0], kind='linear', fill_value="extrapolate"); f_lat = interp1d(actual_dists, coords[:, 1], kind='linear', fill_value="extrapolate")
    final_points = [[round(float(f_lng(d)), 6), round(float(f_lat(d)), 6)] for d in target_d]
    
    res = {"river_name": f"{output_base} combined", "total_km": round(total_km/1000, 2), "point_count": len(final_points), "coordinates": final_points}
    with open(output_file, 'w', encoding='utf-8') as f: json.dump(res, f, ensure_ascii=False, separators=(',', ':'))
    print(f"💾 落地文件: {output_file}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(); parser.add_argument('pattern'); parser.add_argument('output_base'); parser.add_argument('--spacing', type=int, default=50); args = parser.parse_args()
    smart_merge(args.pattern, args.output_base, args.spacing)
