import 'dart:io';
import 'package:flutter/material.dart';
import '../models/user_profile.dart';

/// 未设置头像时的默认头像（App 内置资源：蓝色书本 + 爱心书签）。
const String kDefaultAvatarAsset = 'assets/images/default_avatar.png';

/// 构建用户头像：有自定义照片用照片，否则用内置默认头像图。
Widget buildAppAvatar(UserProfile profile, {double radius = 40}) {
  if (profile.avatarPath.isNotEmpty && File(profile.avatarPath).existsSync()) {
    return CircleAvatar(
      radius: radius,
      backgroundImage: FileImage(File(profile.avatarPath)),
    );
  }
  return CircleAvatar(
    radius: radius,
    backgroundColor: Colors.white,
    backgroundImage: const AssetImage(kDefaultAvatarAsset),
  );
}
