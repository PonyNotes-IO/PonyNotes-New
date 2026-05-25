import 'package:flutter_bloc/flutter_bloc.dart';

class CalendarContentCubit extends Cubit<int> {
  CalendarContentCubit() : super(0);

  void refresh() => emit(state + 1);
}



