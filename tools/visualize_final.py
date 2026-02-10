import json
import os
import argparse

def visualize_result(river_base):
    master_path = f'assets/json/rivers/{river_base}_master.json'
    points_path = f'assets/json/rivers/{river_base}_points.json'
    
    if not os.path.exists(master_path) or not os.path.exists(points_path):
        print(f"❌ 找不到文件: {master_path} 或 {points_path}")
        return

    with open(master_path, 'r', encoding='utf-8') as f:
        master = json.load(f)
    with open(points_path, 'r', encoding='utf-8') as f:
        points_data = json.load(f)

    print(f"📈 正在生成 {river_base} 的合并结果验证页面...")

    # 提取所有子路段点位
    sections_points = points_data['sections_points']
    
    html_template = f"""
    <!DOCTYPE html>
    <html>
    <head>
        <title>验证合并结果 - {river_base}</title>
        <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" />
        <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
        <style>
            #map {{ height: 800px; width: 100%; }}
            .info-panel {{ position: fixed; top: 10px; right: 10px; z-index: 1000; background: white; padding: 15px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.2); max-width: 300px; }}
        </style>
    </head>
    <body>
        <div class="info-panel">
            <h3>{master['game_challenge_name']}</h3>
            <p><b>总里程 (业务):</b> {master['total_length_km']} km</p>
            <p><b>实际里程 (路径):</b> {points_data.get('total_km', 'N/A')} km</p>
            <p><b>修正系数:</b> {master.get('correction_coefficient', 'N/A')}</p>
            <hr>
            <div id="section-list"></div>
        </div>
        <div id="map"></div>
        <script>
            var map = L.map('map');
            L.tileLayer('https://{{s}}.tile.openstreetmap.org/{{z}}/{{x}}/{{y}}.png').addTo(map);
            
            var colors = ['#e6194b', '#3cb44b', '#ffe119', '#4363d8', '#f58231', '#911eb4', '#46f0f0', '#f032e6', '#bcf60c', '#fabebe', '#008080', '#e6beff', '#9a6324', '#fffac8', '#800000', '#aaffc3', '#808000', '#ffd8b1', '#000075', '#808080'];
            var bounds = [];
    """

    # 展平业务段名称
    all_sub_names = []
    for sec in master['challenge_sections']:
        for sub in sec['sub_sections']:
            all_sub_names.append(sub['sub_section_name'])

    for i, pts in enumerate(sections_points):
        if not pts: continue
        latlngs = [[p[1], p[0]] for p in pts]
        name = all_sub_names[i] if i < len(all_sub_names) else f"段 {i}"
        html_template += f"""
            var line_{i} = L.polyline({latlngs}, {{color: colors[{i} % colors.length], weight: 5}})
                .addTo(map)
                .bindPopup("<b>{name}</b><br>点数: {len(pts)}");
            bounds.push(line_{i}.getBounds());
        """

    html_template += """
            if (bounds.length > 0) {
                var group = new L.featureGroup(bounds.map(b => L.rectangle(b, {opacity: 0, fill: false})));
                map.fitBounds(group.getBounds());
            }
        </script>
    </body>
    </html>
    """

    output_file = f"verify_{river_base}.html"
    with open(output_file, 'w', encoding='utf-8') as f:
        f.write(html_template)
    
    print(f"✅ 验证页面已生成: {output_file}")
    print(f"👉 请在浏览器中直接打开该文件，查看最终生成的单条河流路径。")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument('river_base', help='河流基础名，如 songhua_river')
    args = parser.parse_args()
    visualize_result(args.river_base)
