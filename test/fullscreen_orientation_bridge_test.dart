import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/player/utils/fullscreen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('pure_live/orientation');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('playback fullscreen asks Android for sensor-driven landscape', () async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return true;
    });

    expect(await requestSensorLandscape(), isTrue);
    expect(calls, <String>['setSensorLandscape']);
  });

  test('releasing the native request restores the system rotation lock', () async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });

    await releaseNativeOrientation();
    expect(calls, <String>['releaseOrientation']);
  });

  test('a missing platform handler falls back to the Flutter orientation API', () async {
    // No mock handler is registered, so the platform side reports the plugin as
    // unavailable: the bridge must answer instead of throwing, which is what
    // lets WindowService.landScape() keep using SystemChrome on iOS and desktop.
    expect(await requestSensorLandscape(), isFalse);
    await releaseNativeOrientation();
  });

  test('MainActivity exposes the orientation bridge used by fullscreen playback', () {
    final source = File('android/app/src/main/kotlin/com/mystyle/pure_live/MainActivity.kt').readAsStringSync();

    // SystemChrome.setPreferredOrientations can only map onto lock-respecting
    // constants ([] -> UNSPECIFIED, [landscapeLeft, landscapeRight] ->
    // USER_LANDSCAPE), so the sensor-driven mode has to exist on the platform
    // side. A device with the system rotation lock enabled would otherwise never
    // rotate while native video players do.
    expect(source, contains('ORIENTATION_CHANNEL = "pure_live/orientation"'));
    expect(source, contains('SCREEN_ORIENTATION_SENSOR_LANDSCAPE'));
    expect(source, contains('SCREEN_ORIENTATION_UNSPECIFIED'));
  });
}
