import 'package:pure_live/core/interface/live_input_recipe.dart';

import 'playback_source.dart';

typedef LiveInputPlaybackBinder = OwnedPlaybackSource Function(LiveInputRecipe recipe);

/// Binds public resolution data to a playback recipe without opening a seat.
/// Every actual native open acquires independent resources inside the manager.
/// No bundled platform currently exposes an owned playback input; an adapter
/// that needs one registers its own binder at the call site.
OwnedPlaybackSource bindLiveInputForPlayback(LiveInputRecipe recipe) =>
    throw UnsupportedError('No playback binding for ${recipe.identity}');
