import 'package:appflowy/core/notification/notification_helper.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-handwriting-saber/notification.pbenum.dart';

// This value should be the same as the HANDWRITING_SABER_OBSERVABLE_SOURCE value
const String _source = 'HandwritingSaber';

class HandwritingSaberNotificationParser
    extends NotificationParser<HandwritingSaberNotification, FlowyError> {
  HandwritingSaberNotificationParser({
    super.id,
    required super.callback,
  }) : super(
          tyParser: (ty, source) =>
              source == _source ? HandwritingSaberNotification.valueOf(ty) : null,
          errorParser: (bytes) => FlowyError.fromBuffer(bytes),
        );
}
