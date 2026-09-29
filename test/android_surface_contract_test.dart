import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('media_kit_video patch snapshot is an adoption candidate, not compiled code', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final note = File('third_party/media_kit_video/PURELIVE_PATCH.md').readAsStringSync();

    // The replaceable-Surface assertions below inspect a file that is NOT part
    // of the build: the dependency resolves from the pinned git revision instead
    // (confirmed through pubspec.lock and .dart_tool/package_config.json). That
    // made them a false green for the running renderer, so the state is asserted
    // here explicitly. Adopting the snapshot has to update this test.
    expect(pubspec, contains('https://github.com/Predidit/media-kit.git'));
    expect(pubspec, isNot(contains('path: ./third_party/media_kit_video')));
    expect(note, contains('NOT WIRED INTO THE BUILD'));
  });

  test('media_kit_video patch snapshot keeps the replaceable Surface contract', () {
    final source = File(
      'third_party/media_kit_video/android/src/main/java/com/alexmercerind/media_kit_video/VideoOutput.java',
    ).readAsStringSync();

    expect(source, contains('final Surface currentSurface = surfaceProducer.getSurface()'));
    expect(source, contains('currentSurface != referencedSurface'));
    expect(source, contains('surfaceProducer.setCallback(null)'));
    expect(source, isNot(contains('surfaceProducer.getSurface().release()')));
    expect(source, isNot(contains('deletedGlobalObjectRefs')));
  });

  test('vendored fvp renderer obtains its Surface through the producer API', () {
    final source = File(
      'third_party/fvp/android/src/main/java/com/mediadevkit/fvp/FvpPlugin.java',
    ).readAsStringSync();

    // The legacy SurfaceTexture entry point registers no surface callback, so a
    // background/foreground cycle left the renderer writing into an abandoned
    // buffer queue: black video, live audio, and no recovery short of restarting
    // the process. Selecting the API from the `EnableImpeller` manifest flag was
    // wrong because Flutter 3.29+ enables Impeller by default, so an absent flag
    // means "engine default" rather than "Skia".
    expect(source, isNot(contains('getBoolean("io.flutter.embedding.android.EnableImpeller"')));
    expect(source, contains('texRegistry.createSurfaceProducer()'));
    expect(source, contains('sp.setCallback('));
    expect(source, contains('public void onSurfaceAvailable()'));
    expect(source, contains('nativeSetSurface(handle, texId, newSurface, width, height, tunnel)'));
    expect(source, contains('public void onSurfaceCleanup()'));
    // The entry still owns engine resources after cleanup; dropping it here
    // leaked one ImageReader per background/foreground cycle.
    expect(source, isNot(contains('textures.remove(texId);')));
  });

  test('fvp adapter re-asserts its video output after the app is foregrounded', () {
    final adapter = File('lib/player/adapters/fvp_adapter.dart').readAsStringSync();

    expect(adapter, contains('VideoOutputRestorablePlayer'));
    expect(adapter, contains('Future<void> restoreVideoOutput()'));
    // An unbounded attach never produced a texture for a stalled source.
    expect(adapter, contains('_textureAttachTimeout'));
    expect(adapter, isNot(contains('final size = await player.textureSize;')));

    final manager = File('lib/player/core/player_manager.dart').readAsStringSync();
    expect(manager, contains('_restoreVideoOutputAfterForeground'));
  });
}
