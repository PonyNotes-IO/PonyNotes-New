use crate::{ErrorCode, FlowyError};
use client_api::error::{AppResponseError, ErrorCode as AppErrorCode};

impl From<AppResponseError> for FlowyError {
  fn from(error: AppResponseError) -> Self {
    let code = match error.code {
      AppErrorCode::Ok => ErrorCode::Internal,
      AppErrorCode::Unhandled => ErrorCode::Internal,
      AppErrorCode::RecordNotFound => ErrorCode::RecordNotFound,
      AppErrorCode::RecordAlreadyExists => ErrorCode::RecordAlreadyExists,
      AppErrorCode::InvalidEmail => ErrorCode::EmailFormatInvalid,
      AppErrorCode::InvalidPassword => ErrorCode::PasswordFormatInvalid,
      AppErrorCode::OAuthError => ErrorCode::UserUnauthorized,
      AppErrorCode::MissingPayload => ErrorCode::MissingPayload,
      AppErrorCode::OpenError => ErrorCode::Internal,
      AppErrorCode::InvalidUrl => ErrorCode::InvalidURL,
      AppErrorCode::InvalidRequest => ErrorCode::InvalidRequest,
      AppErrorCode::InvalidOAuthProvider => ErrorCode::InvalidAuthConfig,
      AppErrorCode::NotLoggedIn => ErrorCode::UserUnauthorized,
      AppErrorCode::NotEnoughPermissions => ErrorCode::NotEnoughPermissions,
      AppErrorCode::NetworkError => ErrorCode::NetworkError,
      AppErrorCode::RequestTimeout => ErrorCode::RequestTimeout,
      AppErrorCode::PayloadTooLarge => ErrorCode::PayloadTooLarge,
      AppErrorCode::UserUnAuthorized => ErrorCode::UserUnauthorized,
      AppErrorCode::WorkspaceLimitExceeded => ErrorCode::WorkspaceLimitExceeded,
      AppErrorCode::WorkspaceMemberLimitExceeded => ErrorCode::WorkspaceMemberLimitExceeded,
      AppErrorCode::AIResponseLimitExceeded => ErrorCode::AIResponseLimitExceeded,
      AppErrorCode::AIImageResponseLimitExceeded => ErrorCode::AIImageResponseLimitExceeded,
      AppErrorCode::AIMaxRequired => ErrorCode::AIMaxRequired,
      AppErrorCode::FileStorageLimitExceeded => ErrorCode::FileStorageLimitExceeded,
      AppErrorCode::SingleUploadLimitExceeded => ErrorCode::SingleUploadLimitExceeded,
      AppErrorCode::CustomNamespaceDisabled => ErrorCode::CustomNamespaceRequirePlanUpgrade,
      AppErrorCode::CustomNamespaceDisallowed => ErrorCode::CustomNamespaceNotAllowed,
      AppErrorCode::PublishNamespaceAlreadyTaken => ErrorCode::CustomNamespaceAlreadyTaken,
      AppErrorCode::CustomNamespaceTooShort => ErrorCode::CustomNamespaceTooShort,
      AppErrorCode::CustomNamespaceTooLong => ErrorCode::CustomNamespaceTooLong,
      AppErrorCode::CustomNamespaceReserved => ErrorCode::CustomNamespaceReserved,
      AppErrorCode::PublishNameAlreadyExists => ErrorCode::PublishNameAlreadyExists,
      AppErrorCode::PublishNameInvalidCharacter => ErrorCode::PublishNameInvalidCharacter,
      AppErrorCode::PublishNameTooLong => ErrorCode::PublishNameTooLong,
      AppErrorCode::CustomNamespaceInvalidCharacter => ErrorCode::CustomNamespaceInvalidCharacter,
      AppErrorCode::AIServiceUnavailable => ErrorCode::AIServiceUnavailable,
      AppErrorCode::FreePlanGuestLimitExceeded => ErrorCode::FreePlanGuestLimitExceeded,
      AppErrorCode::InvalidGuest => ErrorCode::InvalidGuest,
      AppErrorCode::PaidPlanGuestLimitExceeded => ErrorCode::PaidPlanGuestLimitExceeded,
      // 处理后端返回的 PlanLimitExceeded (错误码 1072) 和 FileStorageLimitExceeded (错误码 1028)
      // 注意：由于后端的 ErrorCode 反序列化时会默认变成 Internal，
      // 我们需要通过检查错误消息来判断是否是存储限制错误
      _ => {
        // 检查错误消息中是否包含存储限制相关关键词
        let message = error.message.to_lowercase();
        // 单文件大小限制检查（优先检查，因为单文件限制更具体）
        if message.contains("single upload limit") || message.contains("single file size") {
          ErrorCode::SingleUploadLimitExceeded
        } else if message.contains("storage limit exceeded")
          || message.contains("plan limit exceeded")
          || message.contains("storage limit")
          || message.contains("total storage limit")
        {
          ErrorCode::PlanLimitExceeded
        } else {
          ErrorCode::Internal
        }
      },
    };

    FlowyError::new(code, error.message)
  }
}
