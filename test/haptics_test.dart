import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diary_app/utils/haptics.dart';

/// 震动链路的回归测试。
///
/// 这类 bug 在真机上「感觉不到」但代码里可以精确验证，
/// 重点是三条：只发一次请求、失败要兜底、太密的请求要丢弃。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance!.defaultBinaryMessenger;

  const channel = MethodChannel('vector_diary/haptic');
  late List<MethodCall> calls;
  Object? respondWith; // 让原生侧返回什么
  bool throwOnCall = false;

  setUp(() {
    calls = [];
    respondWith = true;
    throwOnCall = false;
    Haptics.throttleEnabled = false;
    Haptics.resetThrottle();

    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (throwOnCall) {
        throw PlatformException(code: 'UNAVAILABLE');
      }
      return respondWith;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    Haptics.throttleEnabled = true;
  });

  group('只发一次震动请求', () {
    test('mediumNow 只调用一次原生通道，不再叠加 HapticFeedback', () async {
      Haptics.mediumNow();
      await Future<void>.delayed(Duration.zero);
      expect(calls.length, 1, reason: '同时发两次会让后一次取消前一次');
      expect(calls.single.method, 'vibrate');
      expect(calls.single.arguments['ms'], 24);
      expect(calls.single.arguments['amplitude'], 160);
    });

    test('lightNow 同样只发一次', () async {
      Haptics.lightNow();
      await Future<void>.delayed(Duration.zero);
      expect(calls.length, 1);
      expect(calls.single.arguments['ms'], 12);
    });

    test('light / medium / tick 各只发一次', () async {
      await Haptics.light();
      await Haptics.medium();
      await Haptics.tick();
      expect(calls.length, 3);
      expect(calls.map((c) => c.arguments['ms']), [12, 24, 8]);
    });
  });

  group('失败兜底', () {
    test('原生返回 false 时不抛异常', () async {
      respondWith = false;
      await expectLater(Haptics.light(), completes);
      expect(calls.length, 1);
    });

    test('原生抛异常时被吞掉，不影响调用方', () async {
      throwOnCall = true;
      await expectLater(Haptics.medium(), completes);
      await expectLater(Haptics.tick(), completes);
    });

    test('fire-and-forget 版本抛异常也不会变成未捕获错误', () async {
      throwOnCall = true;
      Haptics.mediumNow();
      Haptics.lightNow();
      // 给 catchError 的执行机会；若有未捕获异常，此处会失败
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
  });

  group('节流', () {
    test('同一瞬间的重复请求只发一次', () async {
      Haptics.throttleEnabled = true;
      Haptics.resetThrottle();
      Haptics.lightNow();
      Haptics.lightNow();
      Haptics.mediumNow();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(calls.length, 1, reason: '40ms 内的重复请求应被丢弃');
    });

    test('间隔足够时每次都能发出', () async {
      Haptics.throttleEnabled = true;
      Haptics.resetThrottle();
      Haptics.lightNow();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      Haptics.lightNow();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(calls.length, 2);
    });
  });

  group('参数合法性', () {
    test('振幅落在 Android 允许的 1..255', () async {
      await Haptics.light();
      await Haptics.medium();
      await Haptics.tick();
      for (final c in calls) {
        final amp = c.arguments['amplitude'] as int;
        expect(amp, greaterThanOrEqualTo(1));
        expect(amp, lessThanOrEqualTo(255));
      }
    });

    test('时长都是正数且不超过 50ms（触感不该拖沓）', () async {
      await Haptics.light();
      await Haptics.medium();
      await Haptics.tick();
      for (final c in calls) {
        final ms = c.arguments['ms'] as int;
        expect(ms, greaterThan(0));
        expect(ms, lessThanOrEqualTo(50));
      }
    });

    test('中等震动的振幅必须大于轻触，才有区分度', () async {
      await Haptics.light();
      await Haptics.medium();
      final light = calls[0].arguments['amplitude'] as int;
      final medium = calls[1].arguments['amplitude'] as int;
      expect(medium, greaterThan(light));
    });
  });

  group('振动自检 diagnose', () {
    test('原生返回状态 Map 时能正确解析', () async {
      respondWith = {
        'hasVibrator': true,
        'hasAmplitudeControl': true,
        'sdkInt': 33,
        'powerSaveMode': false,
        'ringerMode': 2,
      };
      final info = await Haptics.diagnose();
      expect(info, isNotNull);
      expect(info!['hasVibrator'], true);
      expect(info['hasAmplitudeControl'], true);
      expect(info['powerSaveMode'], false);
      expect(info['sdkInt'], 33);
      expect(info['ringerMode'], 2);
      // 自检只发 diagnose，不触发 vibrate
      expect(calls.single.method, 'diagnose');
    });

    test('原生抛异常时返回 null，不崩溃', () async {
      throwOnCall = true;
      final info = await Haptics.diagnose();
      expect(info, isNull);
    });
  });
}
