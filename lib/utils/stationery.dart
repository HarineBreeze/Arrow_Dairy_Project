import 'package:flutter/material.dart';

/// 「VIP 信纸」：信纸样式的集中定义。
///
/// 渲染全部走本地 CustomPainter，不加载任何网络图片、不上传任何内容。
///
/// - [id] 稳定字符串，落进 DiaryEntry.stationery 做持久化；
///   空串表示经典（无信纸底纹）。
/// - [vip] 是否 VIP 专属：仅经典款（无信纸）免费，其余全部 VIP。
/// - v4.9.41：移除「和风信笺」「花间私语」两款；旧数据里的这两个 id
///   会被 DiaryEntry.fromJson 视为未知样式回退为经典。
/// - 「抹茶格纹」更名「抹茶横纹」（id 保持 'lined' 不变，老数据无缝）。
const String stationeryNone = ''; // 经典：无信纸底纹

const List<StationeryStyle> stationeryStyles = [
  StationeryStyle(
    id: 'grid',
    name: '手账方格',
    en: 'GRID NOTE',
    vip: true,
  ),
  StationeryStyle(
    id: 'lined',
    name: '抹茶横纹',
    en: 'CLASSIC LINED',
    vip: true,
  ),
  StationeryStyle(
    id: 'night',
    name: '星夜来信',
    en: 'STARRY NIGHT',
    vip: true,
  ),
  StationeryStyle(
    id: 'kraft',
    name: '牛皮旧信',
    en: 'KRAFT VINTAGE',
    vip: true,
  ),
];

class StationeryStyle {
  final String id;
  final String name;
  final String en;
  final bool vip;
  final String tip;

  const StationeryStyle({
    required this.id,
    required this.name,
    required this.en,
    required this.vip,
    this.tip = '',
  });
}

/// 按 id 取样式；未知/空 id 返回 null（= 经典）。
StationeryStyle? stationeryById(String id) {
  for (final s in stationeryStyles) {
    if (s.id == id) return s;
  }
  return null;
}

/// 该 id 是否为 VIP 信纸。
bool isVipStationery(String id) => stationeryById(id)?.vip ?? false;

/// 该 id 是否为有效信纸（空串/未知 = 经典）。
bool isValidStationery(String id) => stationeryById(id) != null;

/// 样式展示名（经典返回「经典」）。
String stationeryName(String id) => stationeryById(id)?.name ?? '经典';
