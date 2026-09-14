import 'package:flutter_riverpod/flutter_riverpod.dart';

/// State holding joined chat channels and currently active channel view.
class ChannelsState {
  final Set<String> joinedChannels;
  final String activeChannel;

  const ChannelsState({
    this.joinedChannels = const {'#mesh', '#general'},
    this.activeChannel = '#mesh',
  });

  ChannelsState copyWith({
    Set<String>? joinedChannels,
    String? activeChannel,
  }) {
    return ChannelsState(
      joinedChannels: joinedChannels ?? this.joinedChannels,
      activeChannel: activeChannel ?? this.activeChannel,
    );
  }
}

/// StateNotifier managing public and geohash location channels.
class ChannelsNotifier extends StateNotifier<ChannelsState> {
  ChannelsNotifier([ChannelsState? initial]) : super(initial ?? const ChannelsState());

  /// Joins a channel, normalizing with '#' prefix if missing.
  void joinChannel(String channelName) {
    var clean = channelName.trim().toLowerCase();
    if (!clean.startsWith('#')) {
      clean = '#$clean';
    }

    final newSet = Set<String>.from(state.joinedChannels)..add(clean);
    state = state.copyWith(
      joinedChannels: newSet,
      activeChannel: clean,
    );
  }

  /// Leaves a channel. The default '#mesh' broadcast channel cannot be left.
  bool leaveChannel(String channelName) {
    final clean = channelName.trim().toLowerCase();
    if (clean == '#mesh') return false; // Invariant: #mesh cannot be removed

    final newSet = Set<String>.from(state.joinedChannels);
    final removed = newSet.remove(clean);
    if (!removed) return false;

    final nextActive = state.activeChannel == clean ? '#mesh' : state.activeChannel;
    state = state.copyWith(
      joinedChannels: newSet,
      activeChannel: nextActive,
    );
    return true;
  }

  /// Switches active channel view in the UI.
  void setActiveChannel(String channelName) {
    final clean = channelName.trim().toLowerCase();
    if (state.joinedChannels.contains(clean)) {
      state = state.copyWith(activeChannel: clean);
    }
  }

  /// Emergency panic wipe: resets channels to fresh default set.
  void clear() {
    state = const ChannelsState();
  }
}

/// Global provider for chat channels.
final channelsProvider = StateNotifierProvider<ChannelsNotifier, ChannelsState>((ref) {
  return ChannelsNotifier();
});
