import 'package:equatable/equatable.dart';

import '../data/models/user_data_location.dart';

class DataLocationState extends Equatable {
  const DataLocationState({
    required this.userDataLocation,
    required this.didResetToDefault,
    required this.migrationScheduled,
    this.errorMessage,
  });

  factory DataLocationState.initial() => const DataLocationState(
        userDataLocation: null,
        didResetToDefault: false,
        migrationScheduled: false,
      );

  final UserDataLocation? userDataLocation;
  final bool didResetToDefault;
  final bool migrationScheduled;
  final String? errorMessage;

  @override
  List<Object?> get props => [
        userDataLocation,
        didResetToDefault,
        migrationScheduled,
        errorMessage,
      ];

  DataLocationState copyWith({
    UserDataLocation? userDataLocation,
    bool? didResetToDefault,
    bool? migrationScheduled,
    String? errorMessage,
    bool clearError = false,
  }) {
    return DataLocationState(
      userDataLocation: userDataLocation ?? this.userDataLocation,
      didResetToDefault: didResetToDefault ?? this.didResetToDefault,
      migrationScheduled: migrationScheduled ?? this.migrationScheduled,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}
