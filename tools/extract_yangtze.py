import requests
import json
import os

# Natural Earth 1:10m 比例尺河流数据集（全球最权威的开源地理数据集）
DATA_URL = "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_10m_rivers_lake_centerlines.geojson"
OUTPUT_PATH = "assets/json/rivers/yangtze_coords.json"

def download_and_extract():
    print("开始下载全球河流数据 (约 25MB)，请稍候...")
    try:
        response = requests.get(DATA_URL, timeout=120)
        if response.status_code != 200:
            print(f"下载失败: {response.status_code}")
            return
        
        all_data = response.json()
        print("下载完成，正在筛选长江数据...")
        
        # 查找长江（Natural Earth 中标记为 Yangtze 或 Chang Jiang）
        yangtze_features = []
        for feature in all_data['features']:
            name = feature['properties'].get('name', '')
            # 匹配多种可能的名称
            if name in ['Yangtze', 'Chang Jiang', 'Yangzi']:
                yangtze_features.append(feature)
        
        if not yangtze_features:
            print("未在数据集中找到长江，请检查名称。")
            return

        # 提取坐标点
        # 注意：Natural Earth 数据中长江可能被拆成了几段大的 Feature
        final_path = []
        for feat in yangtze_features:
            coords = feat['geometry']['coordinates']
            # GeoJSON LineString 是 [ [lng, lat], ... ]
            # MultiLineString 是 [ [ [lng, lat], ... ], ... ]
            if feat['geometry']['type'] == 'LineString':
                final_path.extend(coords)
            elif feat['geometry']['type'] == 'MultiLineString':
                for segment in coords:
                    final_path.extend(segment)

        print(f"成功提取长江路径！原始点数: {len(final_path)}")
        
        # 创建目录并保存
        os.makedirs(os.path.dirname(OUTPUT_PATH), exist_ok=True)
        with open(OUTPUT_PATH, 'w', encoding='utf-8') as f:
            # 只保存坐标数组，方便 Flutter 读取
            json.dump({
                "river_name": "Yangtze River",
                "point_count": len(final_path),
                "coordinates": final_path
            }, f, ensure_ascii=False, indent=2)
            
        print(f"文件已保存至: {OUTPUT_PATH}")

    except Exception as e:
        print(f"发生错误: {e}")

if __name__ == "__main__":
    download_and_extract()