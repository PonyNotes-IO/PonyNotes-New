import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/repositories/settings_repository.dart';
import 'data_location_event.dart';
import 'data_location_state.dart';

class DataLocationBloc extends Bloc<DataLocationEvent, DataLocationState> {
  DataLocationBloc({
    required SettingsRepository repository,
  })  : _repository = repository,
        super(DataLocationState.initial()) {
    on<DataLocationInitial>(_onStarted);
    on<DataLocationResetToDefault>(_onResetToDefault);
    on<DataLocationSetCustomPath>(_onSetCustomPath);
    on<DataLocationClearState>(_onClearState);
  }

  final SettingsRepository _repository;

  Future<void> _onStarted(
    DataLocationInitial event,
    Emitter<DataLocationState> emit,
  ) async {
    final result = await _repository.getUserDataLocation();
    result.fold(
      (userDataLocation) => emit(
        DataLocationState(
          userDataLocation: userDataLocation,
          didResetToDefault: false,
          migrationScheduled: false,
        ),
      ),
      (error) => emit(
        DataLocationState(
          userDataLocation: state.userDataLocation,
          didResetToDefault: false,
          migrationScheduled: false,
          errorMessage: error.msg,
        ),
      ),
    );
  }

  Future<void> _onResetToDefault(
    DataLocationResetToDefault event,
    Emitter<DataLocationState> emit,
  ) async {
    final result = await _repository.resetUserDataLocation();
    result.fold(
      (defaultLocation) => emit(
        DataLocationState(
          userDataLocation: defaultLocation,
          didResetToDefault: true,
          migrationScheduled: true,
        ),
      ),
      (error) => emit(
        DataLocationState(
          userDataLocation: state.userDataLocation,
          didResetToDefault: false,
          migrationScheduled: false,
          errorMessage: error.msg,
        ),
      ),
    );
  }

  Future<void> _onClearState(
    DataLocationClearState event,
    Emitter<DataLocationState> emit,
  ) async {
    emit(
      state.copyWith(
        didResetToDefault: false,
        migrationScheduled: false,
        clearError: true,
      ),
    );
  }

  Future<void> _onSetCustomPath(
    DataLocationSetCustomPath event,
    Emitter<DataLocationState> emit,
  ) async {
    final result = await _repository.setCustomLocation(event.path);
    result.fold(
      (userDataLocation) => emit(
        DataLocationState(
          userDataLocation: userDataLocation,
          didResetToDefault: false,
          migrationScheduled: true,
        ),
      ),
      (error) => emit(
        DataLocationState(
          userDataLocation: state.userDataLocation,
          didResetToDefault: false,
          migrationScheduled: false,
          errorMessage: error.msg,
        ),
      ),
    );
  }
}
