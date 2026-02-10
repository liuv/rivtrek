import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cache/flutter_map_cache.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:latlong2/latlong.dart';
import 'dart:ui' as ui;
import 'package:provider/provider.dart';
import '../services/geo_service.dart';
import '../models/river_data.dart';
import '../providers/challenge_provider.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final String tiandituKey = '1e3ac648e1213f4c6ebc1248e9c8ba0d';
  bool isSatellite = false;
  
  RiverFullData? fullData;
  RiverPointsData? pointsData;
  LatLng? currentUserPos;
  int currentSubSectionIdx = 0;
  bool isLoading = true;
  String? _loadedRiverId;

  CacheStore? _cacheStore;
  int selectedSubSectionIdx = -1;

  @override
  void initState() {
    super.initState();
    _cacheStore = MemCacheStore();
  }

  Future<void> _initMapData(ChallengeProvider challenge) async {
    if (challenge.activeRiver == null) return;
    if (_loadedRiverId == challenge.activeRiver!.id && !isLoading) return;

    setState(() => isLoading = true);

    try {
      final fd = await GeoService.loadRiverFullData(challenge.activeRiver!.masterJsonPath);
      final pd = await GeoService.loadRiverPointsData(challenge.activeRiver!.pointsJsonPath);
      
      final posInfo = GeoService.findPositionInPoints(pd, fd, challenge.currentDistance);
      
      if (mounted) {
        setState(() {
          fullData = fd;
          pointsData = pd;
          currentUserPos = posInfo['position'];
          currentSubSectionIdx = posInfo['subSectionIndex'];
          _loadedRiverId = challenge.activeRiver!.id;
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading map data: $e");
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Color _getSectionColor(int index) {
    if (index == selectedSubSectionIdx) return Colors.yellowAccent;
    if (index < currentSubSectionIdx) return const Color(0xFF4CAF50);
    if (index == currentSubSectionIdx) return const Color(0xFF2196F3);
    return const Color(0xFFFF9800).withOpacity(0.6);
  }

  @override
  Widget build(BuildContext context) {
    final challenge = context.watch<ChallengeProvider>();
    
    // 异步触发数据加载
    if (_loadedRiverId != challenge.activeRiver?.id) {
      _initMapData(challenge);
    }

    if (isLoading || _cacheStore == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (fullData == null || pointsData == null) {
      return const Scaffold(body: Center(child: Text("数据加载失败")));
    }

    List<Polyline> polylines = [];
    for (int i = 0; i < pointsData!.sectionsPoints.length; i++) {
      final points = pointsData!.sectionsPoints[i].map((p) => LatLng(p[1], p[0])).toList();
      polylines.add(Polyline(
        points: points,
        strokeWidth: i == selectedSubSectionIdx ? 8 : 5,
        color: _getSectionColor(i),
      ));
    }

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: currentUserPos ?? const LatLng(30.0, 105.0),
              initialZoom: 6.0,
              onTap: (tapPosition, point) => _handleMapTap(point),
            ),
            children: [
              TileLayer(
                urlTemplate: isSatellite 
                  ? 'https://t{s}.tianditu.gov.cn/img_w/wmts?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0&LAYER=img&STYLE=default&TILEMATRIXSET=w&FORMAT=tiles&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&tk=$tiandituKey'
                  : 'https://t{s}.tianditu.gov.cn/vec_w/wmts?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0&LAYER=vec&STYLE=default&TILEMATRIXSET=w&FORMAT=tiles&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&tk=$tiandituKey',
                subdomains: const ['0', '1', '2', '3', '4', '5', '6', '7'],
                userAgentPackageName: 'cn.lindenliu.river_meet',
                tileProvider: CachedTileProvider(store: _cacheStore!),
              ),
              TileLayer(
                urlTemplate: isSatellite
                  ? 'https://t{s}.tianditu.gov.cn/cia_w/wmts?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0&LAYER=cia&STYLE=default&TILEMATRIXSET=w&FORMAT=tiles&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&tk=$tiandituKey'
                  : 'https://t{s}.tianditu.gov.cn/cva_w/wmts?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0&LAYER=cva&STYLE=default&TILEMATRIXSET=w&FORMAT=tiles&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&tk=$tiandituKey',
                subdomains: const ['0', '1', '2', '3', '4', '5', '6', '7'],
                userAgentPackageName: 'cn.lindenliu.river_meet',
                tileProvider: CachedTileProvider(store: _cacheStore!),
              ),
              PolylineLayer(polylines: polylines),
              if (currentUserPos != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: currentUserPos!,
                      width: 40,
                      height: 40,
                      child: const Icon(Icons.location_on, color: Colors.red, size: 40),
                    ),
                  ],
                ),
            ],
          ),
          
          Positioned(
            right: 20,
            bottom: selectedSubSectionIdx != -1 ? 220 : 150,
            child: FloatingActionButton(
              mini: true,
              backgroundColor: Colors.white.withOpacity(0.8),
              onPressed: () => setState(() => isSatellite = !isSatellite),
              child: Icon(isSatellite ? Icons.map : Icons.satellite_alt, color: Colors.black87),
            ),
          ),

          _buildHeader(challenge.activeRiver?.name ?? "徒步地图"),
          if (selectedSubSectionIdx != -1) _buildSectionInfo(),
        ],
      ),
    );
  }

  void _handleMapTap(LatLng point) {
    int closestIdx = -1;
    double minDistance = 20.0; 
    
    for (int i = 0; i < pointsData!.sectionsPoints.length; i++) {
      var sPoints = pointsData!.sectionsPoints[i];
      var checkIndices = [0, sPoints.length ~/ 2, sPoints.length - 1];
      for (var idx in checkIndices) {
        if (idx >= sPoints.length) continue;
        var p = sPoints[idx];
        double dist = GeoService.calculateDistance(point, LatLng(p[1], p[0]));
        if (dist < minDistance) {
          minDistance = dist;
          closestIdx = i;
        }
      }
    }
    setState(() => selectedSubSectionIdx = (selectedSubSectionIdx == closestIdx) ? -1 : closestIdx);
  }

  Widget _buildSectionInfo() {
    int subIdx = selectedSubSectionIdx;
    SubSection? target;
    int currentTotal = 0;
    for (var section in fullData!.challengeSections) {
      if (subIdx < currentTotal + section.subSections.length) {
        target = section.subSections[subIdx - currentTotal];
        break;
      }
      currentTotal += section.subSections.length;
    }

    if (target == null) return const SizedBox();

    return Positioned(
      bottom: 20, left: 20, right: 20,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.9),
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(child: Text(target.subSectionName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => setState(() => selectedSubSectionIdx = -1),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text("${target.startPoint} -> ${target.endPoint}", style: TextStyle(fontSize: 14, color: Colors.grey[700])),
            const SizedBox(height: 8),
            Text(target.subSectionDesc, style: const TextStyle(fontSize: 14), maxLines: 3, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildInfoTag("长度: ${target.subSectionLengthKm} km", Colors.blue),
                _buildInfoTag("累积: ${target.accumulatedLengthKm} km", Colors.green),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoTag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500)),
    );
  }

  Widget _buildHeader(String title) {
    return Positioned(
      top: 0, left: 0, right: 0,
      child: ClipRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            height: 100,
            padding: const EdgeInsets.only(top: 50, left: 25),
            color: Colors.white.withOpacity(0.4),
            child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w400)),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _cacheStore?.close();
    super.dispose();
  }
}
