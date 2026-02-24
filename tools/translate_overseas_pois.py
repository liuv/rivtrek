#!/usr/bin/env python3
"""
适配你现有脚本的海外地址翻译工具：只翻译海外英文，不改动表结构，不覆盖国内数据
用法：
  python3 translate_overseas_pois.py --db 你的数据库路径 --river mekong
  python3 translate_overseas_pois.py --db 你的数据库路径 --river mekong --use-baidu --baidu-key 你的Key --baidu-secret 你的Secret
"""
import argparse
import json
import sqlite3
import time
import urllib.parse
import urllib.request
import hashlib
import random
import ssl

# 与你脚本一致的中国坐标范围（核心判断海外）
CHINA_LON_MIN = 73.66
CHINA_LON_MAX = 135.05
CHINA_LAT_MIN = 3.86
CHINA_LAT_MAX = 53.55

def is_overseas(lat, lon):
    """判断是否海外坐标（和你脚本的is_china_coordinate反向）"""
    return not (CHINA_LON_MIN <= lon <= CHINA_LON_MAX and CHINA_LAT_MIN <= lat <= CHINA_LAT_MAX)

def is_english(text):
    """判断是否英文（无中文字符）"""
    if not text:
        return False
    return not any('\u4e00' <= char <= '\u9fff' for char in str(text))

# 基础映射表（优先精准翻译，可按需扩展）
PLACE_NAME_MAP = {
    # 国家
    "Germany": "德国", "Laos": "老挝", "Lao People's Democratic Republic": "老挝",
    "Thailand": "泰国", "Cambodia": "柬埔寨", "Vietnam": "越南",
    "Myanmar": "缅甸", "Burma": "缅甸",
    # 城市
    "Luang Prabang": "琅勃拉邦", "Vientiane": "万象", "Pakse": "巴色",
    "Chiang Rai": "清莱", "Chiang Mai": "清迈", "Nong Khai": "廊开",
    "Phnom Penh": "金边", "Siem Reap": "暹粒", "Ho Chi Minh City": "胡志明市",
    # 后缀
    "Province": "省", "City": "市", "District": "区", "Town": "镇", "Village": "村"
}

# 基础翻译函数（无需API）
def translate_base(text):
    if not text or not is_english(text):
        return text
    # 精准匹配
    if text in PLACE_NAME_MAP:
        return PLACE_NAME_MAP[text]
    # 拆分单词匹配
    words = text.split()
    translated_words = []
    for word in words:
        translated_words.append(PLACE_NAME_MAP.get(word, word))
    translated = " ".join(translated_words)
    # 替换行政后缀
    suffix_map = {
        " Province": "省", " City": "市", " District": "区",
        " Town": "镇", " Village": "村"
    }
    for en_suffix, zh_suffix in suffix_map.items():
        translated = translated.replace(en_suffix, zh_suffix)
    return translated

# 百度翻译函数（可选，需申请API）
def translate_baidu(text, api_key, secret_key):
    if not text or not is_english(text):
        return text
    try:
        salt = random.randint(32768, 65536)
        sign = hashlib.md5(f"{api_key}{text}{salt}{secret_key}".encode()).hexdigest()
        url = (
            f"https://fanyi-api.baidu.com/api/trans/vip/translate"
            f"?q={urllib.parse.quote(text)}&from=en&to=zh&appid={api_key}&salt={salt}&sign={sign}"
        )
        req = urllib.request.Request(url, headers={"User-Agent": "RivtrekPOI/1.0"})
        ctx = ssl._create_unverified_context()
        with urllib.request.urlopen(req, timeout=10, context=ctx) as resp:
            data = json.loads(resp.read().decode())
        if "trans_result" in data and len(data["trans_result"]) > 0:
            return data["trans_result"][0]["dst"]
    except Exception as e:
        print(f"  [WARN] 百度翻译失败: {e}")
    # 翻译失败则用基础映射
    return translate_base(text)

# 翻译POI的JSON字段
def translate_poi_json(pois_json, trans_func):
    if not pois_json:
        return None
    try:
        pois = json.loads(pois_json)
        for poi in pois:
            if poi.get("name") and is_english(poi["name"]):
                poi["name"] = trans_func(poi["name"])
            if poi.get("address") and is_english(poi["address"]):
                poi["address"] = trans_func(poi["address"])
        return json.dumps(pois, ensure_ascii=False)
    except Exception as e:
        print(f"  [WARN] POI解析失败: {e}")
        return pois_json

def main():
    parser = argparse.ArgumentParser(description="翻译海外英文地址（适配你的现有脚本）")
    parser.add_argument("--db", required=True, help="SQLite数据库路径（和你采集脚本的--out一致）")
    parser.add_argument("--river", required=True, help="河流id（如mekong/salween）")
    parser.add_argument("--use-baidu", action="store_true", help="使用百度翻译API（需填写key和secret）")
    parser.add_argument("--baidu-key", default="", help="百度翻译API Key")
    parser.add_argument("--baidu-secret", default="", help="百度翻译Secret Key")
    parser.add_argument("--delay", type=float, default=0.3, help="翻译请求间隔（秒）")
    args = parser.parse_args()

    # 校验百度翻译参数
    if args.use_baidu and (not args.baidu_key or not args.baidu_secret):
        raise SystemExit("使用百度翻译需填写 --baidu-key 和 --baidu-secret")

    # 连接数据库
    conn = sqlite3.connect(args.db)
    cur = conn.cursor()
    conn.execute("BEGIN TRANSACTION")

    # 1. 查询指定河流的所有记录
    query_sql = """
        SELECT rowid, numeric_id, distance_km, latitude, longitude,
               formatted_address, country, province, city, district, township, pois_json
        FROM river_pois
        WHERE river_id = ?
    """
    cur.execute(query_sql, (args.river,))
    records = cur.fetchall()
    if not records:
        print(f"未找到河流 {args.river} 的数据")
        conn.close()
        return
    print(f"共查询到 {len(records)} 条 {args.river} 数据，开始筛选需翻译的海外英文记录...")

    # 2. 选择翻译函数
    if args.use_baidu:
        trans_func = lambda x: translate_baidu(x, args.baidu_key, args.baidu_secret)
    else:
        trans_func = translate_base

    # 3. 逐条处理：只翻译海外+英文记录
    update_sql = """
        UPDATE river_pois
        SET formatted_address=?, country=?, province=?, city=?, district=?, township=?, pois_json=?
        WHERE rowid = ?
    """
    translated_count = 0
    for i, record in enumerate(records):
        rowid, numeric_id, distance_km, lat, lon, fa, country, province, city, district, township, pois_json = record
        
        # 跳过国内坐标
        if not is_overseas(lat, lon):
            continue
        
        # 跳过非英文/空数据（避免翻译国内中文）
        if not fa or not is_english(fa):
            continue
        
        # 翻译字段
        fa_zh = trans_func(fa)
        country_zh = trans_func(country) if country else None
        province_zh = trans_func(province) if province else None
        city_zh = trans_func(city) if city else None
        district_zh = trans_func(district) if district else None
        township_zh = trans_func(township) if township else None
        pois_json_zh = translate_poi_json(pois_json, trans_func)

        # 更新数据库
        cur.execute(update_sql, (
            fa_zh, country_zh, province_zh, city_zh, district_zh, township_zh, pois_json_zh, rowid
        ))
        translated_count += 1
        print(f"  [翻译完成] 距离 {distance_km}km → {fa} → {fa_zh}")

        # 频率控制
        if i > 0:
            time.sleep(args.delay)
        
        # 每50条提交一次事务
        if (i + 1) % 50 == 0:
            conn.commit()
            print(f"  进度：已处理 {i + 1}/{len(records)} 条，翻译 {translated_count} 条")

    # 最终提交
    conn.commit()
    conn.close()
    print(f"\n翻译完成！共翻译 {translated_count} 条海外英文记录")
    print(f"验证方法：sqlite3 {args.db} \"SELECT distance_km, formatted_address FROM river_pois WHERE river_id='{args.river}' AND latitude={lat} LIMIT 1;\"")

if __name__ == "__main__":
    main()