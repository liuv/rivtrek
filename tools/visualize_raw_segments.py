import json
import os
import glob
import webbrowser
import random

KEYWORDS = ['长江', '金沙江', '通天河', '沱沱河']
HTML_PATH = 'raw_segments_map.html'

def get_color():
    return "#{:06x}".format(random.randint(0, 0xFFFFFF))

def extract_all_segments(f_path):
    with open(f_path, 'r', encoding='utf-8') as f:
        data = json.load(f)
    segments = []
    def _walk(obj):
        if isinstance(obj, dict):
            if obj.get('type') == 'LineString': segments.append(obj['coordinates'])
            elif obj.get('type') == 'MultiLineString': segments.extend(obj['coordinates'])
            else:
                for v in obj.values(): _walk(v)
        elif isinstance(obj, list):
            if len(obj) > 0 and isinstance(obj[0], list) and not isinstance(obj[0][0], list):
                segments.append(obj)
            else:
                for v in obj: _walk(v)
    _walk(data)
    return segments

def generate_map():
    files = []
    for kw in KEYWORDS:
        files.extend(glob.glob(f"{kw}*.geojson"))
        files.extend(glob.glob(f"{kw}*.json"))
    files = sorted(list(set(files)))
    
    layers_js = []
    print("=== 正在准备原始片段地图 (全量模式) ===")
    for f in files:
        color = get_color()
        segs = extract_all_segments(f)
        if not segs: continue
        
        file_layer = {"name": f, "color": color, "lines": []}
        for s in segs:
            leaflet_coords = [[p[1], p[0]] for p in s]
            file_layer["lines"].append(leaflet_coords)
        
        layers_js.append(file_layer)
        print(f"🎨 文件: {f:<15} | 包含线段: {len(segs)} 条 | 颜色: {color}")

    html_content = f"""
    <!DOCTYPE html>
    <html>
    <head>
        <title>长江全量原始数据检查</title>
        <meta charset="utf-8" />
        <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" />
        <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
        <style>#map {{ height: 100vh; width: 100%; }} .legend {{ position: fixed; bottom: 20px; left: 20px; background: white; padding: 10px; z-index: 1000; border: 1px solid gray; max-height: 300px; overflow-y: auto; font-size: 12px; }}</style>
    </head>
    <body>
        <div id="map"></div>
        <div class="legend"><b>文件列表</b><hr>{"".join([f'<div><span style="background:{l["color"]};width:10px;height:10px;display:inline-block"></span> {l["name"]}</div>' for l in layers_js])}</div>
        <script>
            var map = L.map('map').setView([30, 110], 5);
            L.tileLayer('https://{{s}}.tile.openstreetmap.org/{{z}}/{{x}}/{{y}}.png').addTo(map);
            var layers = {json.dumps(layers_js)};
            var group = new L.featureGroup();
            layers.forEach(l => {{
                l.lines.forEach(coords => {{
                    var line = L.polyline(coords, {{color: l.color, weight: 3, opacity: 0.7}}).addTo(map).bindPopup(l.name);
                    group.addLayer(line);
                    // 标记每段的头尾，方便看哪里断了
                    L.circle(coords[0], {{radius: 500, color: l.color}}).addTo(map);
                    L.circle(coords[coords.length-1], {{radius: 500, color: l.color}}).addTo(map);
                }});
            }});
            map.fitBounds(group.getBounds());
        </script>
    </body>
    </html>
    """
    with open(HTML_PATH, 'w', encoding='utf-8') as f: f.write(html_content)
    webbrowser.open('file://' + os.path.abspath(HTML_PATH))

if __name__ == "__main__": generate_map()