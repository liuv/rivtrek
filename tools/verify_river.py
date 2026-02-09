import json
import webbrowser
import os

# 目标文件路径
JSON_PATH = 'assets/json/rivers/yangtze_full_50m.json'
HTML_PATH = 'verify_map.html'

def generate_verify_map():
    if not os.path.exists(JSON_PATH):
        print(f"❌ 找不到验证文件: {JSON_PATH}")
        return

    with open(JSON_PATH, 'r', encoding='utf-8') as f:
        data = json.load(f)
    
    # 提取坐标点 [lng, lat] -> Leaflet 需要 [lat, lng]
    points = data.get('coordinates', [])
    leaflet_points = [[p[1], p[0]] for p in points]
    
    river_name = data.get('river_name', '长江')
    total_km = data.get('total_km', 0)
    point_count = data.get('point_count', 0)

    html_content = f"""
    <!DOCTYPE html>
    <html>
    <head>
        <title>长江最终合并结果验证</title>
        <meta charset="utf-8" />
        <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" />
        <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
        <style>
            #map {{ height: 100vh; width: 100%; }}
            .info {{ position: fixed; top: 10px; right: 10px; background: white; padding: 15px; z-index: 1000; border: 2px solid #0077ff; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.2); font-family: sans-serif; }}
        </style>
    </head>
    <body>
        <div class="info">
            <h3 style="margin:0;">{river_name}</h3>
            <hr>
            <b>总长度:</b> {total_km} km<br>
            <b>点位数量:</b> {point_count} (50m间距)<br>
            <small style="color:gray;">* 蓝线应从青海丝滑连至上海</small>
        </div>
        <div id="map"></div>
        <script>
            var map = L.map('map').setView([30, 110], 5);
            L.tileLayer('https://{{s}}.tile.openstreetmap.org/{{z}}/{{x}}/{{y}}.png', {{ attribution: 'OSM' }}).addTo(map);
            
            var latlngs = {json.dumps(leaflet_points)};
            if (latlngs.length > 0) {{
                var polyline = L.polyline(latlngs, {{ color: '#0077ff', weight: 4, opacity: 0.8 }}).addTo(map);
                L.marker(latlngs[0]).addTo(map).bindPopup("源头 (起点)");
                L.marker(latlngs[latlngs.length-1]).addTo(map).bindPopup("入海口 (终点)");
                map.fitBounds(polyline.getBounds());
            }}
        </script>
    </body>
    </html>
    """
    with open(HTML_PATH, 'w', encoding='utf-8') as f:
        f.write(html_content)
    
    print(f"✅ 验证地图已生成: {HTML_PATH}")
    webbrowser.open('file://' + os.path.abspath(HTML_PATH))

if __name__ == "__main__":
    generate_verify_map()