import 'dart:io';
import 'package:flutter/material.dart';
import '../models/user_profile.dart';

/// 构建用户头像：有自定义照片用照片，否则用默认 logo（蓝底「矢」字）
Widget buildAppAvatar(UserProfile profile, {double radius = 40}) {
  if (profile.avatarPath.isNotEmpty && File(profile.avatarPath).existsSync()) {
    return CircleAvatar(
      radius: radius,
      backgroundImage: FileImage(File(profile.avatarPath)),
    );
  }
  return CircleAvatar(
    radius: radius,
    backgroundColor: const Color(0xFF3B6FE0),
    child: Text(
      '矢',
      style: TextStyle(color: Colors.white, fontSize: radius * 0.9),
    ),
  );
}
