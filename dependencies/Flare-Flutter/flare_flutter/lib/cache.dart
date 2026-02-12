import 'dart:async';
import 'cache_asset.dart';

typedef CacheAsset AssetFactoryMethod();

/// A base class for loading cached resources
abstract class Cache<T extends CacheAsset> {
  final Map<String, T> _assets = {};
  final Set<T> _toPrune = <T>{};
  late Timer _pruneTimer;

  T makeAsset();

  bool get isPruningEnabled => true;
  Duration get pruneAfter;

  void _prune() {
    for (final T asset in _toPrune) {
      _assets.removeWhere((String filename, T cached) {
        return cached == asset;
      });
    }
    _toPrune.clear();
    // _pruneTimer = <Timer>[];
  }

  void drop(T asset) {
    _toPrune.add(asset);
    _pruneTimer.cancel();
      if (isPruningEnabled) {
      _pruneTimer = Timer(pruneAfter, _prune);
    }
  }

  void hold(T asset) {
    _toPrune.remove(asset);
  }

  Future<T> getAsset(String filename) async {
    T? asset = _assets[filename];
    if (asset != null) {
      if (asset.isAvailable) {
        return asset;
      } else {
        return await asset.onLoaded() as T;
      }
    }
    asset = makeAsset();
    _assets[filename] = asset;
    asset.load(this, filename);
    if (asset.isAvailable) {
      return asset;
    } else {
      return await asset.onLoaded() as T;
    }
  }
}
