import 'package:pure_live/core/interface/live_input_recipe.dart';
import 'package:pure_live/core/site/fc2live/fc2_api.dart';
import 'package:pure_live/core/site/fc2live/fc2_input_recipe.dart';

import 'fc2_hls_input.dart';
import 'owned_record_input.dart';
import 'recorder_proxy_routing.dart';

typedef LiveInputRecordingBinder = OwnedRecordSource Function(LiveInputRecipe recipe);
OwnedRecordSource bindLiveInputForRecording(LiveInputRecipe recipe) => switch (recipe) {
  Fc2InputRecipe() => bindFc2Recording(recipe),
  _ => throw UnsupportedError('No recording binding for this input recipe'),
};

OwnedRecordSource bindFc2Recording(
  Fc2InputRecipe recipe, {
  Fc2Api? api,
  String Function(Uri) findProxy = resolveRecorderProxyDirective,
}) => OwnedRecordSource(
  identity: recipe.identity,
  createInput: (cancel) =>
      Fc2HlsInput.open(recipe.channelId, recording: true, api: api, findProxy: findProxy, cancel: cancel),
);
