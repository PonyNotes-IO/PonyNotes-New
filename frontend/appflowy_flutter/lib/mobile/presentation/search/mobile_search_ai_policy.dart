bool shouldShowMobileSearchAiEntrance({
  required bool isAndroid,
  required bool aiEnabled,
  required String query,
  required bool hasResults,
  required bool searching,
}) {
  if (!aiEnabled) {
    return false;
  }
  if (isAndroid) {
    return true;
  }
  return query.isNotEmpty && !hasResults && !searching;
}

Map<String, Object> buildMobileSearchChatExtra({
  required bool isAndroid,
  required String query,
}) {
  final message = isAndroid ? query.trim() : query;
  return {
    'initial_message': message,
    if (isAndroid && message.isNotEmpty) 'auto_send': true,
  };
}

bool shouldAutoSendMobileSearchMessage({
  required bool isAndroid,
  required bool requested,
  required bool alreadyHandled,
  required String message,
}) =>
    isAndroid && requested && !alreadyHandled && message.trim().isNotEmpty;

bool shouldUseMobileSearchAskAction({required bool isAndroid}) => isAndroid;
