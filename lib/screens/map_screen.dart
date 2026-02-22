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

/// 底图来源：天地图 / 高德
enum MapProvider { tianditu, amap }

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  final String tiandituKey = '1e3ac648e1213f4c6ebc1248e9c8ba0d';
  MapProvider mapProvider = MapProvider.tianditu;
  bool isSatellite = false;
  
  RiverFullData? fullData;
  RiverPointsData? pointsData;
  LatLng? currentUserPos;
  int currentSubSectionIdx = 0;
  bool isLoading = true;
  String? _loadedRiverId;

  CacheStore? _cacheStore;
  int selectedSubSectionIdx = -1;

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _cacheStore = MemCacheStore();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _cacheStore?.close();
    _pulseController.dispose();
    super.dispose();
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
          // 默认选中当前进度所在的河段
          selectedSubSectionIdx = currentSubSectionIdx;
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

  List<Widget> _buildTileLayers() {
    const userAgent = 'cn.lindenliu.rivtrek';
    final cache = CachedTileProvider(store: _cacheStore!);

    if (mapProvider == MapProvider.tianditu) {
      return [
        TileLayer(
          urlTemplate: isSatellite
              ? 'https://t{s}.tianditu.gov.cn/img_w/wmts?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0&LAYER=img&STYLE=default&TILEMATRIXSET=w&FORMAT=tiles&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&tk=$tiandituKey'
              : 'https://t{s}.tianditu.gov.cn/vec_w/wmts?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0&LAYER=vec&STYLE=default&TILEMATRIXSET=w&FORMAT=tiles&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&tk=$tiandituKey',
          subdomains: const ['0', '1', '2', '3', '4', '5', '6', '7'],
          userAgentPackageName: userAgent,
          tileProvider: cache,
        ),
        TileLayer(
          urlTemplate: isSatellite
              ? 'https://t{s}.tianditu.gov.cn/cia_w/wmts?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0&LAYER=cia&STYLE=default&TILEMATRIXSET=w&FORMAT=tiles&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&tk=$tiandituKey'
              : 'https://t{s}.tianditu.gov.cn/cva_w/wmts?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0&LAYER=cva&STYLE=default&TILEMATRIXSET=w&FORMAT=tiles&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&tk=$tiandituKey',
          subdomains: const ['0', '1', '2', '3', '4', '5', '6', '7'],
          userAgentPackageName: userAgent,
          tileProvider: cache,
        ),
      ];
    }

    // 高德：非卫星 style=7 单层；卫星无「一张图」style，只能两层：底层 style=6 卫星 + 上层 style=8 路网注记
    if (!isSatellite) {
      return [
        TileLayer(
          urlTemplate: 'http://wprd0{s}.is.autonavi.com/appmaptile?x={x}&y={y}&z={z}&lang=zh_cn&size=1&scl=1&style=7',
          subdomains: const ['1', '2', '3', '4'],
          userAgentPackageName: userAgent,
          tileProvider: cache,
        ),
      ];
    }
    return [
      TileLayer(
        urlTemplate: 'http://webst0{s}.is.autonavi.com/appmaptile?style=6&x={x}&y={y}&z={z}',
        subdomains: const ['1', '2', '3', '4'],
        userAgentPackageName: userAgent,
        tileProvider: cache,
      ),
      TileLayer(
        urlTemplate: 'http://wprd0{s}.is.autonavi.com/appmaptile?x={x}&y={y}&z={z}&lang=zh_cn&size=1&scl=1&style=8',
        subdomains: const ['1', '2', '3', '4'],
        userAgentPackageName: userAgent,
        tileProvider: cache,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final challenge = context.watch<ChallengeProvider>();
    
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
    List<Marker> markers = [];

    LatLng? sectionStart;
    LatLng? sectionEnd;

    for (int i = 0; i < pointsData!.sectionsPoints.length; i++) {
      final points = pointsData!.sectionsPoints[i].map((p) => LatLng(p[1], p[0])).toList();
      polylines.add(Polyline(
        points: points,
        strokeWidth: i == selectedSubSectionIdx ? 8 : 5,
        color: _getSectionColor(i),
      ));

      if (i == selectedSubSectionIdx && points.isNotEmpty) {
        sectionStart = points.first;
        sectionEnd = points.last;
      }
    }

    // 1. 当前位置 Marker
    if (currentUserPos != null) {
      markers.add(Marker(
        point: currentUserPos!,
        width: 60,
        height: 60,
        child: AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            return Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 20 + (20 * _pulseController.value),
                  height: 20 + (20 * _pulseController.value),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: (challenge.activeRiver?.color ?? Colors.blue).withOpacity(0.4 * (1 - _pulseController.value)),
                  ),
                ),
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    border: Border.all(color: challenge.activeRiver?.color ?? Colors.blue, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: (challenge.activeRiver?.color ?? Colors.blue).withOpacity(0.5),
                        blurRadius: 10,
                      )
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ));
    }

    // 2. 起终点 Marker
    if (sectionStart != null && sectionEnd != null) {
      markers.add(Marker(
        point: sectionStart,
        width: 40, height: 40,
        child: _buildLocationMarker(challenge.activeRiver?.color ?? Colors.blue),
      ));
      markers.add(Marker(
        point: sectionEnd,
        width: 40, height: 40,
        child: _buildLocationMarker(Colors.orange),
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
              ..._buildTileLayers(),
              PolylineLayer(polylines: polylines),
              MarkerLayer(markers: markers),
            ],
          ),
          
          Positioned(
            right: 20,
            bottom: 150,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _buildMapProviderChip(),
                const SizedBox(height: 8),
                FloatingActionButton(
                  mini: true,
                  backgroundColor: Colors.white.withOpacity(0.8),
                  onPressed: () => setState(() => isSatellite = !isSatellite),
                  child: Icon(isSatellite ? Icons.map : Icons.satellite_alt, color: Colors.black87),
                ),
              ],
            ),
          ),

          _buildHeader(challenge.activeRiver?.name ?? "徒步地图"),
          if (selectedSubSectionIdx != -1) _buildSectionInfo(),
        ],
      ),
    );
  }

  Widget _buildMapProviderChip() {
    return Material(
      color: Colors.white.withOpacity(0.8),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: () => setState(() {
          mapProvider = mapProvider == MapProvider.tianditu ? MapProvider.amap : MapProvider.tianditu;
        }),
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(mapProvider == MapProvider.tianditu ? Icons.public : Icons.map, size: 18, color: Colors.black87),
              const SizedBox(width: 6),
              Text(mapProvider == MapProvider.tianditu ? '天地图' : '高德', style: const TextStyle(fontSize: 13, color: Colors.black87)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLocationMarker(Color color) {
    return Icon(Icons.location_on, color: color, size: 36);
  }

  void _handleMapTap(LatLng point) {
    int closestIdx = -1;
    double minDistance = 30.0; // 扩大感应范围到 30km
    
    for (int i = 0; i < pointsData!.sectionsPoints.length; i++) {
      var sPoints = pointsData!.sectionsPoints[i];
      // 增加采样密度：每段路径采样 10 个点进行检测，而不仅仅是 3 个
      int sampleCount = 10;
      for (int s = 0; s < sampleCount; s++) {
        int idx = ((sPoints.length - 1) * (s / (sampleCount - 1))).round();
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

    // 扁平化所有子路段以便索引
    List<SubSection> allFlattened = [];
    for (var section in fullData!.challengeSections) {
      allFlattened.addAll(section.subSections);
    }

    if (subIdx >= 0 && subIdx < allFlattened.length) {
      target = allFlattened[subIdx];
    }

    if (target == null) return const SizedBox();

    return Positioned(
      top: 110,
      left: 20, right: 20,
      child: TweenAnimationBuilder<double>(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutQuint,
        tween: Tween(begin: 0.0, end: 1.0),
        builder: (context, value, child) {
          return Transform.translate(
            offset: Offset(0, -20 * (1 - value)),
            child: Opacity(opacity: value, child: child),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.9),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 20,
                offset: const Offset(0, 10),
              )
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildBadgeIcon(target),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(target.subSectionName, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600))),
                            IconButton(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              icon: const Icon(Icons.close, size: 18, color: Colors.black26),
                              onPressed: () => setState(() => selectedSubSectionIdx = -1),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text("${target.startPoint} → ${target.endPoint}", style: const TextStyle(fontSize: 12, color: Colors.black45)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(target.subSectionDesc, style: TextStyle(fontSize: 13, color: Colors.black.withOpacity(0.6), height: 1.4), maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(height: 16),
              const Divider(height: 1, color: Colors.black12),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // 上一段按钮
                  IconButton(
                    onPressed: subIdx > 0 ? () => setState(() => selectedSubSectionIdx--) : null,
                    icon: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: subIdx > 0 ? Colors.black87 : Colors.black12),
                  ),
                  Row(
                    children: [
                      _buildInfoTag("${target.subSectionLengthKm}km", Colors.blue),
                      const SizedBox(width: 8),
                      _buildInfoTag("累计 ${target.accumulatedLengthKm}km", Colors.green),
                    ],
                  ),
                  // 下一段按钮
                  IconButton(
                    onPressed: subIdx < allFlattened.length - 1 ? () => setState(() => selectedSubSectionIdx++) : null,
                    icon: Icon(Icons.arrow_forward_ios_rounded, size: 18, color: subIdx < allFlattened.length - 1 ? Colors.black87 : Colors.black12),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBadgeIcon(SubSection target) {
    final medalIcon = target.achievement?.medalIcon;
    final isUnlocked = selectedSubSectionIdx <= currentSubSectionIdx;

    return Container(
      width: 80,
      height: 80,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (medalIcon != null)
            Opacity(
              opacity: isUnlocked ? 1.0 : 0.2,
              child: Image.asset(
                'assets/$medalIcon',
                errorBuilder: (context, error, stackTrace) => const Icon(Icons.military_tech_outlined, size: 40, color: Colors.black12),
              ),
            )
          else
            const Icon(Icons.military_tech_outlined, size: 40, color: Colors.black12),
          
          if (!isUnlocked)
            const Icon(Icons.lock_outline_rounded, size: 20, color: Colors.black26),
        ],
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
      child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w500)),
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
}
