import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../providers/user_profile_provider.dart';

/// 个人资料编辑：昵称、头像
class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  late TextEditingController _nameController;
  late TextEditingController _signatureController;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    final profile = context.read<UserProfileProvider>();
    _nameController = TextEditingController(text: profile.nickname);
    _signatureController = TextEditingController(text: profile.signature);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _signatureController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final XFile? file = await _picker.pickImage(
        source: source, maxWidth: 512, maxHeight: 512, imageQuality: 90);
    if (file == null || !mounted) return;
    await context
        .read<UserProfileProvider>()
        .setAvatarFromFile(File(file.path));
  }

  void _showAvatarOptions() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('从相册选择'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('拍照'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('移除头像'),
              onTap: () async {
                Navigator.pop(ctx);
                await context.read<UserProfileProvider>().clearAvatar();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<UserProfileProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      appBar: AppBar(
        title: const Text('编辑资料'),
        backgroundColor: Colors.transparent,
        foregroundColor: const Color(0xFF222222),
        elevation: 0,
        actions: [
          TextButton(
            onPressed: () {
              profile.setNickname(_nameController.text);
              profile.setSignature(_signatureController.text);
              if (context.mounted) Navigator.of(context).pop();
            },
            child: const Text('保存'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            const SizedBox(height: 32),
            GestureDetector(
              onTap: _showAvatarOptions,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircleAvatar(
                    radius: 48,
                    backgroundColor: Colors.white,
                    child: profile.avatarPath != null
                        ? ClipOval(
                            child: Image.file(
                              File(profile.avatarPath!),
                              key: ValueKey(
                                  'avatar_${profile.avatarPath}_${profile.avatarVersion}'),
                              width: 96,
                              height: 96,
                              fit: BoxFit.cover,
                            ),
                          )
                        : const Icon(Icons.person_outline_rounded,
                            size: 48, color: Color(0xFF888888)),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: Color(0xFF0097A7),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.camera_alt,
                          size: 18, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '点击更换头像',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
            const SizedBox(height: 40),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '昵称',
                hintText: '江河行者',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              onSubmitted: (_) => profile.setNickname(_nameController.text),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _signatureController,
              decoration: const InputDecoration(
                labelText: '个性签名',
                hintText: '江河不语，步履生光',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              maxLines: 2,
              onSubmitted: (_) =>
                  profile.setSignature(_signatureController.text),
            ),
          ],
        ),
      ),
    );
  }
}
