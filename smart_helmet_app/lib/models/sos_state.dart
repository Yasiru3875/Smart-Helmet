class SOSState {
  final bool isActive;
  final int countdown;
  final String status;

  SOSState({
    this.isActive = false,
    this.countdown = 60,
    this.status = 'Idle',
  });

  SOSState copyWith({
    bool? isActive,
    int? countdown,
    String? status,
  }) {
    return SOSState(
      isActive: isActive ?? this.isActive,
      countdown: countdown ?? this.countdown,
      status: status ?? this.status,
    );
  }

  static SOSState initial() => SOSState();
}
