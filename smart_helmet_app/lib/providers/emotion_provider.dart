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

  // EEG Data
  Map<String, double> _eegBands = {
    'Delta': 0.0,
    'Theta': 0.0,
    'Alpha': 0.0,
    'Beta': 0.0,
    'Gamma': 0.0,
  };
  int _attention = 0;
  int _meditation = 0;

  // Getters
  EmotionState get stressState => _stressState;
  EmotionState get fatigueState => _fatigueState;
  Map<String, double> get eegBands => _eegBands;
  int get attention => _attention;
  int get meditation => _meditation;

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

  // Update EEG data
  void updateEEG({
    Map<String, double>? bands,
    int? attention,
    int? meditation,
  }) {
    if (bands != null) {
      _eegBands = Map.from(bands);
    }
    if (attention != null) {
      _attention = attention;
    }
    if (meditation != null) {
      _meditation = meditation;
    }
    notifyListeners();
  }

  // Reset everything
  void reset() {
    _stressState = EmotionState();
    _fatigueState = EmotionState();
    _eegBands = {
      'Delta': 0.0,
      'Theta': 0.0,
      'Alpha': 0.0,
      'Beta': 0.0,
      'Gamma': 0.0,
    };
    _attention = 0;
    _meditation = 0;
    notifyListeners();
  }

  // Reset on no signal
  void resetOnNoSignal() {
    _stressState =
        EmotionState(emotion: "No Signal", emoji: "📡", color: Colors.grey);
    _fatigueState =
        EmotionState(emotion: "No Signal", emoji: "📡", color: Colors.grey);
    _eegBands.updateAll((key, value) => 0.0);
    _attention = 0;
    _meditation = 0;
    notifyListeners();
  }
}

