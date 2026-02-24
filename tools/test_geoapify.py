#!/usr/bin/env python3
"""
Geoapify API独立测试工具：先验证API有效性，再跑主脚本，避免反复折腾
用法：
  python3 test_geoapify.py --key 你的GeoapifyKey --lat 21.185887 --lon 100.699552
"""
import argparse
import json
import ssl
import urllib.parse
import urllib.request

# macOS 证书兼容（和主脚本一致）
def _http_context():
    try:
        import certifi
        return ssl.create_default_context(cafile=certifi.where())
    except ImportError:
        return ssl._create_unverified_context()

def test_geoapify_single_point(api_key: str, lat: float, lon: float) -> dict:
    lat_str = f"{lat:.6f}"
    lon_str = f"{lon:.6f}"
    
    # 合并请求参数（include=pois）
    params = urllib.parse.urlencode({
        "lat": lat_str,
        "lon": lon_str,
        "apiKey": api_key,
        "format": "json",
        "include": "pois",
        "pois_radius": 1000,
        "pois_limit": 20
    })
    request_url = f"https://api.geoapify.com/v1/geocode/reverse?{params}"

    print(f"\n=== 开始测试 Geoapify API（合并地址+POI）===")
    print(f"API Key: {api_key[:10]}****")
    print(f"测试坐标: {lat_str}, {lon_str}")
    print(f"请求URL: {request_url}")
    print("-" * 50)

    result = {"success": False, "data": None, "error": None, "status_code": None}

    try:
        headers = {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Accept": "application/json"
        }
        req = urllib.request.Request(request_url, headers=headers, method="GET")
        with urllib.request.urlopen(req, timeout=15, context=_http_context()) as resp:
            result["status_code"] = resp.getcode()
            if resp.getcode() == 200:
                data = json.loads(resp.read().decode("utf-8"))
                result["success"] = True
                result["data"] = data
                print(f"✅ 请求成功（状态码: 200）")
                # 解析地址
                if data.get("results") and len(data["results"]) > 0:
                    props = data["results"][0]
                    print(f"📌 地址: {props.get('formatted') or '无'}")
                # 解析POI
                poi_count = len(data.get("pois", []))
                print(f"📍 POI数量: {poi_count}")
            else:
                result["error"] = f"状态码错误: {resp.getcode()}"
                print(f"❌ {result['error']}")

    except urllib.error.HTTPError as e:
        result["status_code"] = e.code
        error_detail = e.read().decode("utf-8") if hasattr(e, "read") else "无"
        result["error"] = f"HTTP {e.code}: {error_detail}"
        print(f"❌ {result['error']}")
    except Exception as e:
        result["error"] = f"未知错误: {str(e)}"
        print(f"❌ {result['error']}")

    print("-" * 50)
    return result

# -------------------------- 批量测试（可选） --------------------------
def batch_test_geoapify(api_key: str, coordinate_list: list[tuple[float, float]]):
    """批量测试多个坐标"""
    print(f"\n=== 开始批量测试（共{len(coordinate_list)}个坐标）===")
    success_count = 0
    for i, (lat, lon) in enumerate(coordinate_list):
        print(f"\n【测试点 {i+1}】")
        res = test_geoapify_single_point(api_key, lat, lon)
        if res["success"]:
            success_count += 1
    print(f"\n=== 批量测试完成 ===")
    print(f"✅ 成功: {success_count} 个 | ❌ 失败: {len(coordinate_list)-success_count} 个")

if __name__ == "__main__":
    # 命令行参数
    parser = argparse.ArgumentParser(description="Geoapify API独立测试工具")
    parser.add_argument("--key", required=True, help="Geoapify API Key")
    parser.add_argument("--lat", type=float, required=True, help="测试纬度（如21.185887）")
    parser.add_argument("--lon", type=float, required=True, help="测试经度（如100.699552）")
    parser.add_argument("--batch", action="store_true", help="是否批量测试湄公河常用坐标")
    args = parser.parse_args()

    # 单坐标测试
    test_result = test_geoapify_single_point(args.key, args.lat, args.lon)

    # 批量测试（可选）
    if args.batch:
        # 湄公河常用坐标列表（覆盖老挝/中国边境）
        mekong_coords = [
            (18.146023, 102.016618),  # 老挝琅勃拉邦
            (21.185887, 100.699552),  # 中国西双版纳
            (19.97705, 102.67658),    # 泰国清莱
            (11.5624, 104.9201)       # 柬埔寨金边
        ]
        batch_test_geoapify(args.key, mekong_coords)