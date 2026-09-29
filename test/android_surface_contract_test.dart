import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('media_kit_video patch is the dependency that is compiled', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final lock = File('pubspec.lock').readAsStringSync();
    final note = File('third_party/media_kit_video/PURELIVE_PATCH.md').readAsStringSync();

    // The replaceable-Surface assertions below are only meaningful while this
    // directory is the resolved dependency. Between the e828a14c merge and
    // 2026-09-29 it was not, which silently turned them into a green light for a
    // file that nothing compiled; assert the wiring so that cannot recur.
    expect(pubspec, contains('path: ./third_party/media_kit_video'));
    expect(pubspec, isNot(contains('path: ./media_kit_video')));
    expect(lock, contains('path: "third_party/media_kit_video"'));
    expect(note, contains('WIRED INTO THE BUILD'));
    expect(note, isNot(contains('NOT WIRED')));
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

  test('the vendored mdk player republishes the video size after a source switch', () {
    final player = File('third_party/fvp/lib/src/player.dart').readAsStringSync();
    final adapter = File('lib/player/adapters/fvp_adapter.dart').readAsStringSync();

    // updateTexture() resolves the size from _videoSize. A source switch used to
    // leave that future completed with null - the previous media unloaded before
    // the next one loaded, and the "already completed" guard then refused to
    // publish the new size - so no texture was ever created. Every source after
    // the first, including a quality or line switch inside the same room, played
    // audio with a black picture.
    expect(player, contains('_videoSize = Completer<ui.Size?>();'));
    expect(player, isNot(contains('// loading=>loaded, then frame decoded')));
    // The adapter re-reads the current size before it restarts a live stream.
    expect(adapter, contains('Future<Size?> _readTextureSize('));
    expect(adapter, contains('size = await _readTextureSize(player);'));
  });

  test('an adapter that cannot reuse its source is released with the room', () {
    final adapter = File('lib/player/adapters/fvp_adapter.dart').readAsStringSync();
    final manager = File('lib/player/core/player_manager.dart').readAsStringSync();
    final player = File('third_party/fvp/lib/src/player.dart').readAsStringSync();

    // mdk only renders the first source opened on a player instance: a second
    // open keeps the audio and leaves the picture black, so the room must not
    // hand its player to the next one. The behavioural path cannot be unit
    // tested here (the harness cannot complete a close), so the contract is
    // asserted directly instead.
    expect(adapter, contains('SourceReuseAwarePlayer'));
    expect(adapter, contains('bool get supportsSourceReuse => false;'));
    expect(manager, contains('SourceReuseAwarePlayer'));
    expect(manager, contains('reuseBlocked'));
    // Creating the next player while the previous teardown still runs leaves it
    // without a working video output, so the teardown has to be awaitable.
    expect(player, contains('Future<void> dispose() async'));
    expect(adapter, contains('await player.dispose().timeout('));
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
