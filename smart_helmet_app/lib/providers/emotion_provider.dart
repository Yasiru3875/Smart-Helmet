import 'package:flutter/material.dart';

class EmotionState {
  final String emotion;
  final String emoji;

  EmotionState({
    this.emotion = "Neutral",
    this.emoji = "😐",
  });

  EmotionState copyWith({String? emotion, String? emoji}) {
    return EmotionState(
      emotion: emotion ?? this.emotion,
      emoji: emoji ?? this.emoji,
    );
  }
}

class EmotionProvider with ChangeNotifier {
  EmotionState _state = EmotionState();

  EmotionState get state => _state;


  get stressState => null;

  void updateEmotion(String emotion, String emoji) {
    _state = _state.copyWith(emotion: emotion, emoji: emoji);
    notifyListeners();
  }

  void reset() {
    _state = EmotionState();
    notifyListeners();
  }

}

