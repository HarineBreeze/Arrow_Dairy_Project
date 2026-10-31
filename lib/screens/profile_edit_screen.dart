import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../models/user_profile.dart';
import '../services/user_storage.dart';
import '../widgets/avatar.dart';
import '../widgets/unsaved_guard.dart';
import '../widgets/pressable.dart';
import '../widgets/save_done_button.dart';

class ProfileEditScreen extends StatefulWidget {
  final UserProfile profile;
  const ProfileEditScreen({Key? key, required this.profile})
      : super(key: key);

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  late final TextEditingController _nicknameCtrl;
  late String _gender;
  late String _avatarPath;
  bool _saving = false;

  /// 完成动画的进度（0 = 常态，1 = 已收缩），用于让「取消」按钮同步淡出。
  Animation<double> get _doneAnim =>
      _doneKey.currentState?.collapse ?? const AlwaysStoppedAnimation(1);

  final GlobalKey<SaveDoneButtonState> _doneKey =
      GlobalKey<SaveDoneButtonState>();


  /// 进入页面时的内容快照，用于判断是否有未保存的修改
  String _initial = '';

  /// 当前编辑内容（用于 dirty 比较）
  String _snapshot() => [_nicknameCtrl.text, _gender, _avatarPath].join('\u0001');

  bool get _dirty => _snapshot() != _initial;

  /// 主动返回（AppBar 返回键 / 系统返回键）：有改动时弹框，确定即放弃保存返回
  Future<bool> _handleLeave() => confirmLeaveIfDirty(context, dirty: _dirty);

  @override
  void initState() {
    super.initState();
    _nicknameCtrl = TextEditingController(text: widget.profile.nickname);
    _gender = widget.profile.gender;
    _avatarPath = widget.profile.avatarPath;
    _initial = _snapshot();
  }

  @override
  void dispose() {
    _nicknameCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    try {
      final picker = ImagePicker();
      final XFile? file = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (file == null) return;
      final dir = await getApplicationDocumentsDirectory();
      final newPath =
          '${dir.path}/avatar_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await File(file.path).copy(newPath);
      if (!mounted) return;
      setState(() => _avatarPath = newPath);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('选择头像失败，请重试')),
      );
    }
  }

  /// 资料页没有必填校验，保留接口一致性（返回 null 表示通过）
  String? _validate() => null;

  Future<void> _save() async {
    setState(() => _saving = true);
    final profile = UserProfile(
      nickname: _nicknameCtrl.text.trim(),
      gender: _gender,
      avatarPath: _avatarPath,
    );
    await UserStorage.save(profile);
    if (!mounted) return;
    // 落盘完成：续播对勾 + 粒子，播完由 onDone 返回
    _doneKey.currentState?.finish();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _handleLeave,
      child: Scaffold(
      appBar: AppBar(
        title: const Text('个人信息'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: '返回',
          onPressed: () => Navigator.maybePop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
        child: Column(
          children: [
            GestureDetector(
              onTap: _pickAvatar,
              child: Stack(
                children: [
                  buildAppAvatar(
                    UserProfile(avatarPath: _avatarPath),
                    radius: 48,
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Color(0xFF3B6FE0),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.camera_alt,
                          size: 14, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '点击更换头像',
              style: TextStyle(fontSize: 12, color: Color(0xFF9AA8BF)),
            ),
            const SizedBox(height: 28),
            _buildNicknameField(),
            const Divider(height: 1),
            const SizedBox(height: 20),
            _buildGenderRow(),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
          child: _buildSaveBar(),
        ),
      ),
    ),
    );
  }


  /// 保存栏：点完成后取消按钮淡出让出整行，完成按钮收缩成居中圆形，
  /// 打勾描边 + 粒子迸发，停留片刻再保存返回。
  Widget _buildSaveBar() {
    return SizedBox(
      height: 48,
      child: Stack(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: _doneAnim.value >= 1
                ? const SizedBox.shrink()
                : FractionallySizedBox(
                    widthFactor: 0.5,
                    child: Opacity(
                      opacity: (1 - _doneAnim.value * 1.6).clamp(0.0, 1.0),
                      child: IgnorePointer(
                        ignoring: _saving,
                        child: Pressable(
                          enabled: true,
                          child: OutlinedButton(
                            onPressed: _saving ? null : () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              side: const BorderSide(color: Color(0xFF3B6FE0)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text('取消',
                                style: TextStyle(fontSize: 16)),
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
          SaveDoneButton(
            key: _doneKey,
            color: Theme.of(context).colorScheme.primary,
            validate: _validate,
            onTap: _save,
            onDone: () {
              if (mounted) Navigator.pop(context, true);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildNicknameField() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Text(
          '昵称',
          style: TextStyle(fontSize: 15, color: Color(0xFF2A3B52)),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: TextField(
            controller: _nicknameCtrl,
            maxLength: 8,
            style: const TextStyle(fontSize: 16),
            decoration: const InputDecoration(
              hintText: '未设置昵称',
              hintStyle: TextStyle(color: Color(0xFF9AA8BF)),
              border: InputBorder.none,
              counterText: '',
            ),
          ),
        ),
        Text(
          '${_nicknameCtrl.text.length}/8',
          style: const TextStyle(fontSize: 12, color: Color(0xFF9AA8BF)),
        ),
      ],
    );
  }

  Widget _buildGenderRow() {
    return Row(
      children: [
        const Text(
          '性别',
          style: TextStyle(fontSize: 15, color: Color(0xFF2A3B52)),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Row(
            children: [
              _buildGenderOption('男', 'male'),
              const SizedBox(width: 12),
              _buildGenderOption('女', 'female'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGenderOption(String label, String value) {
    final selected = _gender == value;
    return GestureDetector(
      onTap: () => setState(() => _gender = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF3B6FE0) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? const Color(0xFF3B6FE0)
                : const Color(0xFFDCE7FF),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: selected ? Colors.white : const Color(0xFF5A6B82),
          ),
        ),
      ),
    );
  }
}
