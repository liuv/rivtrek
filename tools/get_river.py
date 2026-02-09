import requests
import json

# 长江的 OSM Relation ID
RELATION_ID = 73038

# 使用 OSMLab 的汇聚接口，这个比 Overpass 快且不容易超时
url = f"https://polygons.openstreetmap.fr/get_geojson.py?id={RELATION_ID}&params=0"

print("正在获取长江全线数据，请稍候...")
try:
    response = requests.get(url, timeout=60)
    if response.status_code == 200:
        data = response.json()
        with open("assets/json/rivers/yangtze_full_path.json", "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
        print("成功！文件已保存到 assets/json/rivers/yangtze_full_path.json")
    else:
        print(f"获取失败，错误代码: {response.status_code}")
except Exception as e:
    print(f"发生错误: {e}")