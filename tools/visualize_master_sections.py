import json
import webbrowser
import os
import random

MASTER_PATH = 'assets/json/rivers/yangtze_master.json'
HTML_PATH = 'verify_sections.html'

def get_color():
    return "#{:06x}".format(random.randint(0, 0xFFFFFF))

def generate():
    if not os.path.exists(MASTER_PATH):
        print("❌ 找不到 Master 文件，请先运行 align_and_split.py")
        return

    with open(MASTER_PATH, 'r', encoding='utf-8') as f:
        data = json.load(f)
    
    sections_js = []
    for s in data['challenge_sections']:
        color = get_color()
        leaflet_coords = [[p[1], p[0]] for p in s['points']]
        sections_js.append({
            "name": s['section_name'],
            "color": color,
            "coords": leaflet_coords,
            "km": s['section_length_km']
        })

    html_content = f"""
    <!DOCTYPE html>
    <html>
    <head>
        <title>长江业务分段路径验证</title>
        <meta charset="utf-8" />
        <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" />
        <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
        <style>
            #map {{ height: 100vh; width: 100%; }}
            .legend {{ position: fixed; top: 10px; left: 10px; background: white; padding: 10px; z-index: 1000; border: 2px solid #333; border-radius: 5px; font-size: 12px; max-height: 90vh; overflow-y: auto; }}
        </style>
    </head>
    <body>
        <div id="map"></div>
        <div class="legend"><b>业务河段划分 (总 {data['total_length_km']}km)</b><hr>
        {"".join([f'<div><span style="background:{s["color"]};width:10px;height:10px;display:inline-block"></span> {s["name"]} ({s["km"]}km)</div>' for s in sections_js])}
        </div>
        <script>
            var map = L.map('map').setView([30, 110], 5);
            L.tileLayer('https://{{s}}.tile.openstreetmap.org/{{z}}/{{x}}/{{y}}.png').addTo(map);
            var sections = {json.dumps(sections_js)};
            var group = new L.featureGroup();
            sections.forEach(s => {{
                var line = L.polyline(s.coords, {{color: s.color, weight: 5, opacity: 0.8}}).addTo(map).bindPopup(s.name);
                group.addLayer(line);
            }});
            map.fitBounds(group.getBounds());
        </script>
    </body>
    </html>
    """
    with open(HTML_PATH, 'w', encoding='utf-8') as f:
        f.write(html_content)
    
    print(f"✅ 业务分段地图已生成: {HTML_PATH}")
    webbrowser.open('file://' + os.path.abspath(HTML_PATH))

if __name__ == "__main__":
    generate()