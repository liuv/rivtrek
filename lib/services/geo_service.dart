// lib/services/geo_service.dart

import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'dart:math' as math;
import '../models/river_data.dart';

class GeoService {
  /// 加载河流业务配置
  static Future<RiverFullData> loadRiverFullData(String masterJsonPath) async {
    final String response = await rootBundle.loadString(masterJsonPath);
    final data = json.decode(response);
    return RiverFullData.fromJson(data);
  }

  /// 加载河流坐标点集
  static Future<RiverPointsData> loadRiverPointsData(String pointsJsonPath) async {
    final String response = await rootBundle.loadString(pointsJsonPath);
    final data = json.decode(response);
    return RiverPointsData.fromJson(data);
  }

  /// 计算两个经纬度点之间的距离 (Haversine公式, 单位: km)
  static double calculateDistance(LatLng p1, LatLng p2) {
    var d1 = p1.latitude * (math.pi / 180.0);
    var num1 = p1.longitude * (math.pi / 180.0);
    var d2 = p2.latitude * (math.pi / 180.0);
    var num2 = p2.longitude * (math.pi / 180.0);
    var d3 = num2 - num1;
    var d4 = d2 - d1;
    var res = math.pow(math.sin(d4 / 2.0), 2.0) +
        math.cos(d1) * math.cos(d2) * math.pow(math.sin(d3 / 2.0), 2.0);
    var res2 = 2.0 * math.atan2(math.sqrt(res), math.sqrt(1.0 - res));
    return 6371.0 * res2;
  }

  /// 从 GeoJSON 资源加载坐标点序列
  static Future<List<LatLng>> loadPathFromGeoJson(String assetPath) async {
    try {
      final String response = await rootBundle.loadString(assetPath);
      final data = json.decode(response);

      List<LatLng> points = [];
      var features = data['features'] as List;
      for (var feature in features) {
        var geometry = feature['geometry'];
        if (geometry['type'] == 'LineString') {
          var coords = geometry['coordinates'] as List;
          for (var coord in coords) {
            points.add(LatLng(coord[1].toDouble(), coord[0].toDouble()));
          }
        }
      }
      return points;
    } catch (e) {
      print("Error loading GeoJSON: $e");
      return [];
    }
  }

  /// 根据当前里程计算所在的 sub_section 索引以及在该 section 内部的插值位置
  static Map<String, dynamic> findPositionInPoints(
      RiverPointsData pointsData, RiverFullData fullData, double currentKm) {
    int subSectionIndex = 0;
    double accumulatedKm = 0.0;

    List<SubSection> allSubSections = [];
    for (var section in fullData.challengeSections) {
      allSubSections.addAll(section.subSections);
    }

    for (int i = 0; i < allSubSections.length; i++) {
      double sectionLen = allSubSections[i].subSectionLengthKm;
      if (currentKm <= accumulatedKm + sectionLen) {
        subSectionIndex = i;
        double kmInSection = currentKm - accumulatedKm;

        // 在对应的坐标点包中进行线性插值
        if (subSectionIndex < pointsData.sectionsPoints.length) {
          var points = pointsData.sectionsPoints[subSectionIndex];
          LatLng? pos = _getPointInPointsList(points, kmInSection, sectionLen);

          return {
            'subSectionIndex': subSectionIndex,
            'position': pos ?? LatLng(points.first[1], points.first[0]),
            'progress': kmInSection / sectionLen,
          };
        }
      }
      accumulatedKm += sectionLen;
    }

    // 如果超过总长
    var lastPoints = pointsData.sectionsPoints.last;
    return {
      'subSectionIndex': pointsData.sectionsPoints.length - 1,
      'position': LatLng(lastPoints.last[1], lastPoints.last[0]),
      'progress': 1.0,
    };
  }

  static LatLng? _getPointInPointsList(
      List<List<double>> points, double targetKm, double totalSectionKm) {
    if (points.isEmpty) return null;
    if (targetKm <= 0) return LatLng(points.first[1], points.first[0]);
    if (targetKm >= totalSectionKm)
      return LatLng(points.last[1], points.last[0]);

    double ratio = targetKm / totalSectionKm;
    double floatIdx = ratio * (points.length - 1);
    int idx = floatIdx.floor();
    double subRatio = floatIdx - idx;

    if (idx >= points.length - 1) return LatLng(points.last[1], points.last[0]);

    double lat =
        points[idx][1] + (points[idx + 1][1] - points[idx][1]) * subRatio;
    double lng =
        points[idx][0] + (points[idx + 1][0] - points[idx][0]) * subRatio;

    return LatLng(lat, lng);
  }
}
