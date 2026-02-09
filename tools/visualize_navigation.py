import json
import webbrowser
import os

# 路径定义
CONFIG_PATH = 'assets/json/rivers/yangtze_master.json'
POINTS_PATH = 'assets/json/rivers/yangtze_points.json'
HTML_PATH = 'nav_verify.html'

def generate():
    if not os.path.exists(CONFIG_PATH) or not os.path.exists(POINTS_PATH):
        print("❌ 缺少数据文件，请确保 yangtze_master.json 和 yangtze_points.json 存在")
        return

    with open(CONFIG_PATH, 'r', encoding='utf-8') as f:
        config = json.load(f)
    with open(POINTS_PATH, 'r', encoding='utf-8') as f:
        points_data = json.load(f)

    # 准备给 JS 使用的数据
    # 将业务信息和坐标合并到一个对象中
    sections_for_js = []
    start_km = 0
    for i, s in enumerate(config['challenge_sections']):
        length = s['section_length_km']
        sections_for_js.append({
            "id": i,
            "name": s['section_name'],
            "start_km": start_km,
            "end_km": start_km + length,
            "coords": [[p[1], p[0]] for p in points_data['sections_points'][i]] # [lat, lng]
        })
        start_km += length

    html_content = f"""
    <!DOCTYPE html>
    <html>
    <head>
        <title>长江徒步效果模拟验证</title>
        <meta charset="utf-8" />
        <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" />
        <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
        <style>
            #map {{ height: 100vh; width: 100%; }}
            .control-panel {{ position: fixed; top: 10px; left: 50%; transform: translateX(-50%); background: white; padding: 20px; z-index: 1000; border-radius: 10px; box-shadow: 0 4px 15px rgba(0,0,0,0.3); width: 80%; text-align: center; }}
            input[type=range] {{ width: 100%; margin: 10px 0; }}
            .status {{ font-family: sans-serif; font-weight: bold; color: #2c3e50; }}
        </style>
    </head>
    <body>
        <div class="control-panel">
            <div class="status">当前模拟行进距离: <span id="dist-val">0</span> km</div>
            <input type="range" id="progress-slider" min="0" max="{config['total_length_km']}" value="0" step="1">
            <div id="section-info" style="color: #e74c3c;">当前所处河段：源头</div>
        </div>
        <div id="map"></div>
        <script>
            var sections = {json.dumps(sections_for_js)};
            var map = L.map('map').setView([30, 110], 5);
            L.tileLayer('https://{{s}}.tile.openstreetmap.org/{{z}}/{{x}}/{{y}}.png').addTo(map);

            var polylineLayers = [];
            var userMarker = L.marker([0,0]).addTo(map);

            function updateMap(currentDist) {{
                document.getElementById('dist-val').innerText = currentDist;
                
                // 清除旧线
                polylineLayers.forEach(l => map.removeLayer(l));
                polylineLayers = [];

                sections.forEach(s => {{
                    var color, weight, opacity;
                    
                    if (currentDist >= s.end_km) {{
                        // 1. 已走过的河段 - 蓝色
                        color = '#3498db'; weight = 4; opacity = 0.6;
                    }} else if (currentDist >= s.start_km && currentDist < s.end_km) {{
                        // 2. 当前正在走的河段 - 红色高亮
                        color = '#e74c3c'; weight = 8; opacity = 1.0;
                        document.getElementById('section-info').innerText = "当前所处河段：" + s.name;
                        
                        // 计算用户在该段内的具体坐标索引
                        var ratio = (currentDist - s.start_km) / (s.end_km - s.start_km);
                        var idx = Math.floor(s.coords.length * ratio);
                        if (idx >= s.coords.length) idx = s.coords.length - 1;
                        userMarker.setLatLng(s.coords[idx]).bindPopup("我在这里: " + s.name).openPopup();
                    }} else {{
                        // 3. 未开始的河段 - 灰色
                        color = '#bdc3c7'; weight = 3; opacity = 0.4;
                    }}

                    var line = L.polyline(s.coords, {{color: color, weight: weight, opacity: opacity}}).addTo(map);
                    line.on('click', function() {{ alert("这是：" + s.name + "\\n长度：" + (s.end_km - s.start_km).toFixed(2) + " km"); }});
                    polylineLayers.push(line);
                }});
            }}

            document.getElementById('progress-slider').oninput = function() {{
                updateMap(parseFloat(this.value));
            }};

            // 初始加载
            updateMap(0);
            map.fitBounds(L.featureGroup(sections[0].coords.map(c => L.polyline([c]))).getBounds());
        </script>
    </body>
    </html>
    """
    with open(HTML_PATH, 'w', encoding='utf-8') as f:
        f.write(html_content)
    print(f"✅ 徒步模拟验证工具已生成: {HTML_PATH}")
    webbrowser.open('file://' + os.path.abspath(HTML_PATH))

if __name__ == "__main__":
    generate()