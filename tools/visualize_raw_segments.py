import json
import os
import glob
import argparse
import random

def generate_map(pattern, output_html="river_inspection.html"):
    print(f"🔍 正在搜集原始数据: {pattern}")
    
    files = []
    for p in pattern.split('|'):
        glob_p = p if '*' in p or '?' in p else f"{p}*"
        files.extend(glob.glob(f"tools/{glob_p}.geojson"))
        files.extend(glob.glob(f"tools/{glob_p}.json"))
    files = sorted(list(set(files)))

    if not files:
        print("⚠️ 未找到匹配的文件")
        return

    # Leaflet 模板
    html_template = """
    <!DOCTYPE html>
    <html>
    <head>
        <title>河流原始数据验证</title>
        <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" />
        <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
        <style>#map { height: 900px; width: 100%; }</style>
    </head>
    <body>
        <div id="map"></div>
        <script>
            var map = L.map('map').setView([45, 125], 5);
            L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png').addTo(map);
            
            var colors = ['#e6194b', '#3cb44b', '#ffe119', '#4363d8', '#f58231', '#911eb4', '#46f0f0', '#f032e6', '#bcf60c', '#fabebe', '#008080', '#e6beff', '#9a6324', '#fffac8', '#800000', '#aaffc3', '#808000', '#ffd8b1', '#000075', '#808080'];
            var colorIdx = 0;
    """

    for f_path in files:
        if '_raw_path_' in f_path or '_points' in f_path: continue
        with open(f_path, 'r', encoding='utf-8') as f:
            data = json.load(f)
            segs = []
            # 兼容多种格式
            if isinstance(data, dict) and 'coordinates' in data:
                segs = data['coordinates']
            elif isinstance(data, dict) and 'features' in data:
                for feat in data['features']:
                    if feat['geometry']['type'] == 'LineString':
                        segs.append(feat['geometry']['coordinates'])
            
            if not segs: continue
            
            color = "colors[colorIdx % colors.length]"
            filename = os.path.basename(f_path)
            
            # 将经纬度转换并添加到地图
            for i, seg in enumerate(segs):
                # Leaflet 需要 [lat, lng]
                latlngs = [[p[1], p[0]] for p in seg]
                html_template += f"""
                L.polyline({latlngs}, {{color: {color}, weight: 3}})
                    .addTo(map)
                    .bindPopup("<b>文件:</b> {filename}<br><b>段索引:</b> {i}<br><b>点数:</b> {len(seg)}");
                """
            html_template += "colorIdx++;\n"

    html_template += """
        </script>
    </body>
    </html>
    """

    with open(output_html, 'w', encoding='utf-8') as f:
        f.write(html_template)
    
    print(f"✅ 可视化地图已生成: {output_html}")
    print(f"👉 请在浏览器中打开该文件查看原始数据分布")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument('pattern', help='匹配模式，如 "松花江"')
    args = parser.parse_args()
    generate_map(args.pattern)
