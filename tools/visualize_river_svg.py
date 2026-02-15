#!/usr/bin/env python3
"""根据河流配置与坐标生成精简采样的 SVG 图，支持可配置采样间距与线宽，曲线连接。"""
import json
import os
import argparse
from pyproj import Geod

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def geod_dist_km(p1, p2):
    """两点 [lng, lat] 的球面距离，单位 km。"""
    geod = Geod(ellps="WGS84")
    _, _, d = geod.inv(p1[0], p1[1], p2[0], p2[1])
    return d / 1000.0


def sample_by_spacing_km(all_points, spacing_km):
    """按累计里程每隔 spacing_km 取一个点。all_points: [[lng,lat], ...]。"""
    if not all_points or spacing_km <= 0:
        return list(all_points) if all_points else []
    out = [all_points[0]]
    acc_km = 0.0
    for i in range(1, len(all_points)):
        acc_km += geod_dist_km(all_points[i - 1], all_points[i])
        if acc_km >= spacing_km:
            out.append(all_points[i])
            acc_km = 0.0
    if all_points and out[-1] != all_points[-1]:
        out.append(all_points[-1])
    return out


# 与 visualize_final.py 一致的分段配色
SECTION_COLORS = [
    "#e6194b", "#3cb44b", "#ffe119", "#4363d8", "#f58231", "#911eb4",
    "#46f0f0", "#f032e6", "#bcf60c", "#fabebe", "#008080", "#e6beff",
    "#9a6324", "#fffac8", "#800000", "#aaffc3", "#808000", "#ffd8b1",
    "#000075", "#808080",
]


def xy_to_svg_path_d(xy):
    """将 [(x,y), ...] 转为平滑曲线 path d（三次贝塞尔）。"""
    if len(xy) < 2:
        return ""
    if len(xy) == 2:
        return "M %.2f %.2f L %.2f %.2f" % (xy[0][0], xy[0][1], xy[1][0], xy[1][1])
    d = ["M %.2f %.2f" % (xy[0][0], xy[0][1])]
    for i in range(len(xy) - 1):
        x0, y0 = xy[i]
        x1, y1 = xy[i + 1]
        if i == 0:
            xc0, yc0 = x0, y0
        else:
            xc0 = x0 + (xy[i + 1][0] - xy[i - 1][0]) / 6
            yc0 = y0 + (xy[i + 1][1] - xy[i - 1][1]) / 6
        if i == len(xy) - 2:
            xc1, yc1 = x1, y1
        else:
            xc1 = x1 - (xy[i + 2][0] - xy[i][0]) / 6
            yc1 = y1 - (xy[i + 2][1] - xy[i][1]) / 6
        d.append("C %.2f %.2f %.2f %.2f %.2f %.2f" % (xc0, yc0, xc1, yc1, x1, y1))
    return " ".join(d)


def make_projector(lng_min, lng_max, lat_min, lat_max, width, height, padding=20):
    """返回统一的 (lng, lat) -> (x, y) 投影函数。"""
    span_lng = lng_max - lng_min or 1
    span_lat = lat_max - lat_min or 1
    usable_w = width - 2 * padding
    usable_h = height - 2 * padding

    def project(lng, lat):
        x = padding + (lng - lng_min) / span_lng * usable_w
        y = padding + (1 - (lat - lat_min) / span_lat) * usable_h
        return x, y

    return project


def generate_svg(river_base, spacing_km=30, stroke_width=16, width=1200, height=800, output_path=None, padding=20, segmented=True):
    """
    segmented: True=分段多色绘制（每 sub_section 一色），False=一条完整线路单色绘制。
    """
    master_path = os.path.join(ROOT, "assets", "json", "rivers", river_base + "_master.json")
    points_path = os.path.join(ROOT, "assets", "json", "rivers", river_base + "_points.json")
    if not os.path.exists(master_path) or not os.path.exists(points_path):
        print("找不到文件:", master_path, "或", points_path)
        return
    with open(master_path, "r", encoding="utf-8") as f:
        master = json.load(f)
    with open(points_path, "r", encoding="utf-8") as f:
        points_data = json.load(f)
    sections_points = points_data["sections_points"]
    all_points = []
    for pts in sections_points:
        all_points.extend(pts)
    if not all_points:
        print("无坐标点")
        return
    lng_min = min(p[0] for p in all_points)
    lng_max = max(p[0] for p in all_points)
    lat_min = min(p[1] for p in all_points)
    lat_max = max(p[1] for p in all_points)
    project = make_projector(lng_min, lng_max, lat_min, lat_max, width, height, padding)

    path_elements = []
    total_sampled = 0

    if segmented:
        # 分段多色：每段一条 path，按 SECTION_COLORS 循环
        for i, pts in enumerate(sections_points):
            if not pts:
                continue
            sampled = sample_by_spacing_km(pts, spacing_km)
            total_sampled += len(sampled)
            xy = [project(p[0], p[1]) for p in sampled]
            path_d = xy_to_svg_path_d(xy)
            if not path_d:
                continue
            color = SECTION_COLORS[i % len(SECTION_COLORS)]
            path_elements.append(
                '  <path d="%s" fill="none" stroke="%s" stroke-width="%s" stroke-linecap="round" stroke-linejoin="round"/>'
                % (path_d, color, stroke_width)
            )
    else:
        # 一条完整线路：合并所有点后采样，使用 master 主题色
        sampled = sample_by_spacing_km(all_points, spacing_km)
        total_sampled = len(sampled)
        xy = [project(p[0], p[1]) for p in sampled]
        path_d = xy_to_svg_path_d(xy)
        if path_d:
            theme_color = master.get("default_theme_color") or "#2E6195"
            path_elements.append(
                '  <path d="%s" fill="none" stroke="%s" stroke-width="%s" stroke-linecap="round" stroke-linejoin="round"/>'
                % (path_d, theme_color, stroke_width)
            )

    out = output_path or os.path.join(ROOT, river_base + "_river.svg")
    title = master.get("game_challenge_name", river_base)
    with open(out, "w", encoding="utf-8") as f:
        f.write('<?xml version="1.0" encoding="UTF-8"?>\n')
        f.write('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d" width="%d" height="%d">\n' % (width, height, width, height))
        f.write("  <title>%s</title>\n" % title.replace("<", "&lt;").replace(">", "&gt;"))
        f.write('  <g id="rivers">\n')
        f.write("\n".join(path_elements) + "\n")
        f.write("  </g>\n")
        f.write("</svg>\n")
    mode_str = "分段多色" if segmented else "一条完整线路"
    print("SVG 已生成:", out, "(%s, 采样间距 %s km, 线宽 %s, 总采样点数 %d)" % (mode_str, spacing_km, stroke_width, total_sampled))
    return out


def main():
    parser = argparse.ArgumentParser(description="根据河流配置与坐标生成 SVG 图")
    parser.add_argument("river_base", help="河流基础名，如 yangtze、songhua_river")
    parser.add_argument("--spacing-km", type=float, default=30, help="采样间距(km)，默认 30")
    parser.add_argument("--stroke-width", type=float, default=16, help="线条宽度，默认 16")
    parser.add_argument("--width", type=int, default=1200, help="SVG 宽度")
    parser.add_argument("--height", type=int, default=800, help="SVG 高度")
    parser.add_argument("-o", "--output", help="输出 SVG 路径")
    parser.add_argument("--unified", action="store_true",
                       help="一条完整线路单色绘制；不传则分段多色绘制")
    args = parser.parse_args()
    generate_svg(
        args.river_base,
        spacing_km=args.spacing_km,
        stroke_width=args.stroke_width,
        width=args.width,
        height=args.height,
        output_path=args.output,
        segmented=not args.unified,
    )


if __name__ == "__main__":
    main()
