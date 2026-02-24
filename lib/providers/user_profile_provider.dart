// 用户资料：昵称、头像路径，持久化到 SharedPreferences + 应用目录

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

const String _keyNickname = 'user_nickname';
const String _keyAvatarPath = 'user_avatar_path';
const String _keySignature = 'user_signature';
const String _defaultNickname = '江河行者';
const String _defaultSignature = '一条江河，一场行走，一次内心的朝圣之旅。';

class UserProfileProvider extends ChangeNotifier {
  String _nickname = _defaultNickname;
  String? _avatarPath; // 应用目录下的头像文件绝对路径
  String _signature = _defaultSignature;
  int _avatarVersion = 0; // 每次更换头像递增，用于强制 Image 刷新

  String get nickname => _nickname;
  String? get avatarPath => _avatarPath;
  String get signature => _signature;
  int get avatarVersion => _avatarVersion;

  /// 展示用昵称：空则用默认「涉川」（分享卡用）
  String get displayNameForShare =>
      _nickname.trim().isEmpty ? '涉川' : _nickname.trim();

  UserProfileProvider() {
    _load();
  }

  /// 从 SharedPreferences 重新加载（如恢复备份后调用）
  Future<void> reloadFromPrefs() async => _load();

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _nickname = prefs.getString(_keyNickname) ?? _defaultNickname;
    _signature = prefs.getString(_keySignature) ?? _defaultSignature;
    final saved = prefs.getString(_keyAvatarPath);
    if (saved != null && saved.isNotEmpty) {
      final f = File(saved);
      if (f.existsSync())
        _avatarPath = saved;
      else
        await prefs.remove(_keyAvatarPath);
    } else {
      _avatarPath = null;
    }
    notifyListeners();
  }

  Future<void> setNickname(String value) async {
    _nickname = value.trim().isEmpty ? _defaultNickname : value.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyNickname, _nickname);
    notifyListeners();
  }

  Future<void> setSignature(String value) async {
    _signature = value.trim().isEmpty ? _defaultSignature : value.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySignature, _signature);
    notifyListeners();
  }

  /// 将选中的图片复制到应用目录并设为头像
  Future<void> setAvatarFromFile(File imageFile) async {
    if (!imageFile.existsSync()) return;
    final dir = await getApplicationDocumentsDirectory();
    const name = 'avatar.jpg';
    final dest = File(p.join(dir.path, name));
    if (dest.existsSync()) await dest.delete();
    await imageFile.copy(dest.path);
    _avatarPath = dest.path;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAvatarPath, _avatarPath!);
    _avatarVersion++;
    imageCache.evict(FileImage(dest));
    notifyListeners();
  }

  Future<void> clearAvatar() async {
    if (_avatarPath != null) {
      try {
        final f = File(_avatarPath!);
        if (f.existsSync()) await f.delete();
      } catch (_) {}
      _avatarPath = null;
      _avatarVersion++;
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyAvatarPath);
      notifyListeners();
    }
  }
}
