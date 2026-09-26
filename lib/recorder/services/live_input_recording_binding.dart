import 'package:pure_live/core/interface/live_input_recipe.dart';

import 'owned_record_input.dart';

typedef LiveInputRecordingBinder = OwnedRecordSource Function(LiveInputRecipe recipe);

/// No bundled platform currently exposes an owned recording input; an adapter
/// that needs one registers its own binder at the call site.
OwnedRecordSource bindLiveInputForRecording(LiveInputRecipe recipe) =>
    throw UnsupportedError('No recording binding for ${recipe.identity}');
