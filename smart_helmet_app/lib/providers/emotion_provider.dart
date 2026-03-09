import 'package:flutter/material.dart';

class EmotionState {
  final String emotion;
  final String emoji;
  final Color color;

  EmotionState({
    this.emotion = "No Signal",
    this.emoji = "📡",
    this.color = Colors.grey,
  });

  EmotionState copyWith({
    String? emotion,
    String? emoji,
    Color? color,
  }) {
    return EmotionState(
      emotion: emotion ?? this.emotion,
      emoji: emoji ?? this.emoji,
      color: color ?? this.color,
    );
  }
}

class EmotionProvider with ChangeNotifier {
  // Stress / Mood state
  EmotionState _stressState = EmotionState();

  // Fatigue state
  EmotionState _fatigueState = EmotionState();

  // Getters
  EmotionState get stressState => _stressState;
  EmotionState get fatigueState => _fatigueState;

  // Update stress/mood
  void updateStress({
    required String emotion,
    required String emoji,
    required Color color,
  }) {
    _stressState = _stressState.copyWith(
      emotion: emotion,
      emoji: emoji,
      color: color,
    );

    notifyListeners();
  }

  // Update fatigue
  void updateFatigue({
    required String emotion,
    required String emoji,
    required Color color,
  }) {
    _fatigueState = _fatigueState.copyWith(
      emotion: emotion,
      emoji: emoji,
      color: color,
    );
    notifyListeners();
  }

  // Reset everything
  void reset() {
    _stressState = EmotionState();
    _fatigueState = EmotionState();
    notifyListeners();
  }

  // Optional: combined reset when signal is lost
  void resetOnNoSignal() {
    _stressState =
        EmotionState(emotion: "No Signal", emoji: "📡", color: Colors.grey);
    _fatigueState =
        EmotionState(emotion: "No Signal", emoji: "📡", color: Colors.grey);
    notifyListeners();
  }

}

