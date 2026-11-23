import 'dart:io';

import 'package:ayodiray/screens/app_lock_setup_wizard.dart';
import 'package:ayodiray/services/app_lock_storage.dart';
import 'package:ayodiray/theme/app_palette.dart';
import 'package:ayodiray/utils/app_version.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// v5.0.2 行为回归：
/// 1. 隐私锁设置拆成 4 个弹窗：形式 → 密码 → 确认 → 密保；
/// 2. 任一步中断视为取消，不写任何凭证；
/// 3. 关闭需验证凭证；关闭后重开必须重新设置新密码；
/// 4. 「凭证仅保存在本机」文案移除；
/// 5. 弹窗主题化（背景走 AppPalette.c、按钮随主题色），深浅/主题色一致；
/// 6. 版本号 V5.0.2。

class _FakePathProvider extends PathProviderPlatform {
  final String path;
  _FakePathProvider(this.path);
  @override
  Future<String?> getTemporaryPath() async => path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;

  setUp(() async {
    dir = Directory('/tmp/v5002_${DateTime.now().microsecondsSinceEpoch}');
    dir.createSync(recursive: true);
    PathProviderPlatform.instance = _FakePathProvider(dir.path);
    AppPalette.dark = false;
    AppPalette.accent = AccentCatalog.byId('bamboo');
  });

  tearDown(() {
    AppPalette.dark = false;
    AppPalette.accent = AccentCatalog.byId('bamboo');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('版本号', () {
    test('展示版本同步到 V5.0.2', () {
      expect(AppVersion.displayVersion, 'V5.0.2');
    });
  });

  group('4 步向导 · 步骤与文案', () {
    test('4 步顺序固定：形式 → 密码 → 确认 → 密保', () {
      expect(AppLockSetupStep.values, [
        AppLockSetupStep.type,
        AppLockSetupStep.credential,
        AppLockSetupStep.confirm,
        AppLockSetupStep.security,
      ]);
    });

    test('密码锁与手势锁的步骤标题正确', () {
      expect(lockStepTitle(AppLockSetupStep.type, AppLockType.password),
          '选择隐私锁形式');
      expect(lockStepTitle(AppLockSetupStep.credential, AppLockType.password),
          '设置密码');
      expect(lockStepTitle(AppLockSetupStep.confirm, AppLockType.password),
          '确认密码');
      expect(lockStepTitle(AppLockSetupStep.security, AppLockType.password),
          '设置密保');
      expect(lockStepTitle(AppLockSetupStep.credential, AppLockType.gesture),
          '设置解锁手势');
      expect(lockStepTitle(AppLockSetupStep.confirm, AppLockType.gesture),
          '确认解锁手势');
    });

    test('源码不含「凭证仅保存在本机」旧文案', () {
      final source = File(
              '${Directory.current.path}/lib/screens/app_lock_setup_wizard.dart')
          .readAsStringSync();
      expect(source.contains('凭证仅保存在本机'), false);
    });
  });

  group('4 步向导 · 中断即取消（UI 流程，注入假保存）', () {
    bool? setupResult;
    int saveCalls = 0;

    Future<void> startWizard(WidgetTester tester) async {
      setupResult = null;
      saveCalls = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(builder: (context) {
            return ElevatedButton(
              onPressed: () async {
                setupResult = await showAppLockSetupWizard(
                  context,
                  saveOverride: ({required type, required pin, required pattern,
                      required question, required answer}) async {
                    saveCalls++;
                  },
                );
              },
              child: const Text('start'),
            );
          }),
        ),
      ));
    }

    testWidgets('第 1 步取消 → 整体取消且不保存', (tester) async {
      await startWizard(tester);
      await tester.tap(find.text('start'));
      await tester.pumpAndSettle();

      expect(find.text('1 / 4'), findsOneWidget);
      expect(find.text('选择隐私锁形式'), findsOneWidget);

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(setupResult, false);
      expect(saveCalls, 0);
    });

    testWidgets('第 2 步取消 → 整体取消且不保存', (tester) async {
      await startWizard(tester);
      await tester.tap(find.text('start'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      expect(find.text('2 / 4'), findsOneWidget);
      expect(find.text('设置密码'), findsOneWidget);

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(setupResult, false);
      expect(saveCalls, 0);
    });

    testWidgets('走完 4 步 → 保存一次并回填凭证', (tester) async {
      await startWizard(tester);
      await tester.tap(find.text('start'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '4321');
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      expect(find.text('确认密码'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, '4321');
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      expect(find.text('设置密保'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, '上海');
      await tester.tap(find.text('完成设置'));
      await tester.pumpAndSettle();

      expect(setupResult, true);
      expect(saveCalls, 1);
    });

    testWidgets('确认密码不一致 → 停留本步且不保存', (tester) async {
      await startWizard(tester);
      await tester.tap(find.text('start'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '1111');
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '2222');
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();

      expect(find.text('确认密码'), findsOneWidget);
      expect(find.textContaining('不一致'), findsOneWidget);
      expect(saveCalls, 0);

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(setupResult, false);
    });
  });

  group('关闭需验证（UI 流程，注入假校验）', () {
    testWidgets('密码错误不关闭，正确才返回 true', (tester) async {
      bool? verifyResult;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(builder: (context) {
            return ElevatedButton(
              onPressed: () async {
                verifyResult = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AppLockVerifyDialog(
                    typeOverride: Future<AppLockType>.value(AppLockType.password),
                    verifyOverride: (type, value) async => value == '8888',
                  ),
                );
              },
              child: const Text('verify'),
            );
          }),
        ),
      ));

      await tester.tap(find.text('verify'));
      await tester.pumpAndSettle();
      expect(find.text('验证隐私锁'), findsOneWidget);

      await tester.enterText(find.byType(TextField).last, '0000');
      await tester.tap(find.text('确认关闭'));
      await tester.pumpAndSettle();
      expect(find.textContaining('密码错误'), findsOneWidget);
      expect(verifyResult, isNull);

      await tester.enterText(find.byType(TextField).last, '8888');
      await tester.tap(find.text('确认关闭'));
      await tester.pumpAndSettle();
      expect(verifyResult, true);
    });

    testWidgets('验证弹窗取消 → 返回 false（不关闭）', (tester) async {
      bool? verifyResult;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(builder: (context) {
            return ElevatedButton(
              onPressed: () async {
                verifyResult = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AppLockVerifyDialog(
                    typeOverride: Future<AppLockType>.value(AppLockType.password),
                    verifyOverride: (type, value) async => true,
                  ),
                );
              },
              child: const Text('verify'),
            );
          }),
        ),
      ));
      await tester.tap(find.text('verify'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(verifyResult, false);
    });
  });

  group('存储层 · 关闭后重开重置（纯 IO）', () {
    test('关闭后重开写入全新凭证，不沿用旧密码', () async {
      await AppLockStorage.saveLock(
        type: AppLockType.password,
        pin: '1111',
        question: 'q',
        answer: 'a',
      );
      expect(await AppLockStorage.verifyPin('1111'), true);

      await AppLockStorage.clearLock();
      expect(await AppLockStorage.hasLock(), false);

      await AppLockStorage.saveLock(
        type: AppLockType.password,
        pin: '9999',
        question: '新密保',
        answer: '新答案',
      );
      expect(await AppLockStorage.verifyPin('9999'), true);
      expect(await AppLockStorage.verifyPin('1111'), false);
    });
  });

  group('弹窗主题适配', () {
    testWidgets('常规/深色模式下弹窗背景均走 AppPalette.c', (tester) async {
      for (final dark in [false, true]) {
        AppPalette.dark = dark;
        AppPalette.accent = AccentCatalog.byId('bamboo');
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: Builder(builder: (context) {
              return ElevatedButton(
                onPressed: () => showAppLockSetupWizard(
                  context,
                  saveOverride: ({required type, required pin, required pattern,
                      required question, required answer}) async {},
                ),
                child: const Text('go'),
              );
            }),
          ),
        ));
        await tester.tap(find.text('go'));
        await tester.pumpAndSettle();

        final dialog = tester.widget<AlertDialog>(
            find.byKey(const ValueKey('app_lock_step_type')));
        expect(dialog.backgroundColor, AppPalette.c(0xFFFFFFFF));
        expect(dialog.shape, isA<RoundedRectangleBorder>());

        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
      }
    });

    testWidgets('主题色切换时主色跟随 accentColor', (tester) async {
      AppPalette.dark = false;
      AppPalette.accent = AccentCatalog.byId('lotus');
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(builder: (context) {
            return ElevatedButton(
              onPressed: () => showAppLockSetupWizard(
                context,
                saveOverride: ({required type, required pin, required pattern,
                    required question, required answer}) async {},
              ),
              child: const Text('go'),
            );
          }),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(AppPalette.accentColor,
          Color(0xFF000000 | AccentCatalog.byId('lotus').rgb));
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
    });
  });
}
