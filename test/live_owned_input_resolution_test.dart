import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/core/interface/live_site.dart';
import 'package:pure_live/core/interface/live_input_recipe.dart';
import 'package:pure_live/core/site/fc2live/fc2_input_recipe.dart';
import 'package:pure_live/model/live_play_quality.dart';
import 'package:pure_live/modules/live_play/states/player_state.dart';
import 'package:pure_live/player/core/live_input_playback_binding.dart';

void main() {
  test('owned resolution normalization preserves public recipe and quality without media URLs', () async {
    final input = Fc2InputRecipe('123');
    final site = _OwnedSite(input);
    final result = await site.resolvePlayUrls(
      detail: LiveRoom(roomId: '123'),
      quality: LivePlayQuality(quality: '450p'),
    );
    expect(result.inputRecipe, same(input));
    expect(result.urls, isEmpty);
    expect(result.sourceQueryPolicies, isEmpty);
    expect(result.lineCount, 1);
    expect(result.hasSources, true);
    expect(result.appliedQualityData, 'ack');
    expect(result.qualityUnconfirmed, true);
    final again = await site.resolvePlayUrlsForRecovery(
      detail: LiveRoom(roomId: '123'),
      quality: LivePlayQuality(quality: '450p'),
    );
    expect(again.inputRecipe, same(input));
  });

  test('empty and multi-line direct resolutions keep existing semantics', () {
    expect(const LivePlayUrlResolution(urls: []).normalized().hasSources, false);
    final result = const LivePlayUrlResolution(urls: [' a ', 'a', 'b']).normalized();
    expect(result.urls, ['a', 'b']);
    expect(result.lineCount, 2);
    expect(result.inputRecipe, isNull);
  });

  test('production fc2 binding is lazy and does not export the channel or local URI', () {
    final recipe = Fc2InputRecipe('123');
    final source = bindLiveInputForPlayback(recipe);
    expect(source.identity, recipe.identity);
    expect(source.url, isNull);
    expect(bindLiveInputForPlayback(recipe), isNot(same(source)));
  });

  test('owned UI state keeps one logical line but clears capability on ordinary replacement', () {
    final recipe = Fc2InputRecipe('123');
    final source = bindLiveInputForPlayback(recipe);
    final state = const PlayerState().copyWith(playUrls: const [], ownedSource: source);
    expect(state.hasPlaybackSource, true);
    expect(state.lineCount, 1);
    expect(state.playUrlSafe, isEmpty);
    expect(state.copyWith(isCurrentRoomAudioOnly: true).ownedSource, same(source));
    expect(state.copyWith(currentLineIndex: 0).ownedSource, same(source));
    expect(state.copyWith(playUrls: ['https://fixture/real.m3u8']).ownedSource, isNull);
    expect(state.copyWith(clearOwnedSource: true).ownedSource, isNull);
    expect(state.copyWith(), state);
    expect(state.copyWith().hashCode, state.hashCode);
    expect(state.copyWith(ownedSource: bindLiveInputForPlayback(recipe)), isNot(state));
    expect(state.toString(), isNot(contains('fc2live:123')));
    // Even malformed presentation state must not export stale remote media.
    expect(PlayerState(ownedSource: source, playUrls: const ['https://fixture/stale']).playUrlSafe, isEmpty);
  });
}

class _OwnedSite extends LiveSite implements LivePlayUrlResolver {
  _OwnedSite(this.input);
  final LiveInputRecipe input;
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async => LivePlayUrlResolution.owned(input: input, appliedQualityData: 'ack', qualityUnconfirmed: true);
}
