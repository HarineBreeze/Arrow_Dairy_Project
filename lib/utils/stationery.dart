import 'package:flutter/material.dart';

/// v4.9.40「VIP 信纸」：6 套信纸样式的集中定义。
///
/// 视觉与 HTML 提案一一对应（抹茶格纹 / 手账方格 / 和风信笺 /
/// 花间私语 / 星夜来信 / 牛皮旧信），渲染全部走本地 CustomPainter，
/// 不加载任何网络图片、不上传任何内容。
///
/// - [id] 稳定字符串，落进 DiaryEntry.stationery 做持久化；
///   空串 / 'normal' 表示普通（无信纸）。
/// - [vip] 是否 VIP 专属：方格、牛皮免费，其余 4 款 VIP。
/// - 抽屉顺序：免费款置顶，VIP 款在下。
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

const String stationeryNone = ''; // 普通：无信纸

const List<StationeryStyle> stationeryStyles = [
  // —— 免费两款（抽屉置顶）——
  StationeryStyle(
    id: 'grid',
    name: '手账方格',
    en: 'GRID NOTE',
    vip: false,
  ),
  StationeryStyle(
    id: 'kraft',
    name: '牛皮旧信',
    en: 'KRAFT VINTAGE',
    vip: false,
  ),
  // —— VIP 四款 ——
  StationeryStyle(
    id: 'lined',
    name: '抹茶格纹',
    en: 'CLASSIC LINED',
    vip: true,
  ),
  StationeryStyle(
    id: 'washi',
    name: '和风信笺',
    en: 'WASHI LETTER',
    vip: true,
  ),
  StationeryStyle(
    id: 'botanical',
    name: '花间私语',
    en: 'BOTANICAL',
    vip: true,
  ),
  StationeryStyle(
    id: 'night',
    name: '星夜来信',
    en: 'STARRY NIGHT',
    vip: true,
  ),
];

/// 按 id 取样式；未知/空 id 返回 null（= 普通信纸）。
StationeryStyle? stationeryById(String id) {
  for (final s in stationeryStyles) {
    if (s.id == id) return s;
  }
  return null;
}

/// 该 id 是否为 VIP 信纸。
bool isVipStationery(String id) => stationeryById(id)?.vip ?? false;

/// 该 id 是否为有效信纸（空串/未知 = 普通）。
bool isValidStationery(String id) => stationeryById(id) != null;

/// 样式展示名（普通返回「普通」）。
String stationeryName(String id) => stationeryById(id)?.name ?? '普通';
