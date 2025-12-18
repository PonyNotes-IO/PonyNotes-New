import 'dart:convert';

import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-error/code.pbenum.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:http/http.dart' as http;

enum PasswordEndpoint {
  changePassword,
  forgotPassword,
  otp,
  setupPassword,
  checkHasPassword,
  verifyResetPasswordToken,
  checkPasswordStatus;

  String get path {
    switch (this) {
      case PasswordEndpoint.changePassword:
        return '/user/change-password';
      case PasswordEndpoint.forgotPassword:
        return '/recover';
      case PasswordEndpoint.otp:
        return '/otp';
      case PasswordEndpoint.setupPassword:
        return '/user';
      case PasswordEndpoint.checkHasPassword:
        return '/user/auth-info';
      case PasswordEndpoint.verifyResetPasswordToken:
        return '/verify';
      case PasswordEndpoint.checkPasswordStatus:
        return '/user/password/status';
    }
  }

  String get method {
    switch (this) {
      case PasswordEndpoint.changePassword:
      case PasswordEndpoint.forgotPassword:
      case PasswordEndpoint.otp:
      case PasswordEndpoint.verifyResetPasswordToken:
        return 'POST';
      case PasswordEndpoint.setupPassword:
        return 'PUT';
      case PasswordEndpoint.checkHasPassword:
      case PasswordEndpoint.checkPasswordStatus:
        return 'GET';
    }
  }

  Uri uri(String baseUrl, {Map<String, String>? queryParameters}) {
    final uri = Uri.parse('$baseUrl$path');
    if (queryParameters != null && queryParameters.isNotEmpty) {
      return uri.replace(queryParameters: queryParameters);
    }
    return uri;
  }
}

class PasswordHttpService {
  PasswordHttpService({
    required this.baseUrl,
    required this.authToken,
  });

  final String baseUrl;

  String authToken;

  final http.Client client = http.Client();

  Map<String, String> get headers => {
        'Content-Type': 'application/json',
        if (authToken.isNotEmpty) 'Authorization': 'Bearer $authToken',
      };

  /// Changes the user's password
  ///
  /// [currentPassword] - The user's current password
  /// [newPassword] - The new password to set
  Future<FlowyResult<bool, FlowyError>> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final result = await _makeRequest(
      endpoint: PasswordEndpoint.changePassword,
      body: {
        'current_password': currentPassword,
        'password': newPassword,
      },
      errorMessage: 'Failed to change password',
    );

    return result.fold(
      (data) => FlowyResult.success(true),
      (error) => FlowyResult.failure(error),
    );
  }

  /// Sends a password reset email or SMS to the user
  ///
  /// [email] - The email address or phone number of the user
  /// [phone] - Optional phone number (if provided, will be used instead of email)
  Future<FlowyResult<bool, FlowyError>> forgotPassword({
    required String email,
    String? phone,
  }) async {
    // 如果提供了 phone，使用 /otp 接口（支持手机号）
    // 否则使用 /recover 接口（只支持邮箱）
    if (phone != null && phone.isNotEmpty) {
      final body = <String, dynamic>{
        'phone': phone,
        'create_user': false, // 密码重置时，用户应该已存在
      };
      
      final result = await _makeRequest(
        endpoint: PasswordEndpoint.otp,
        body: body,
        errorMessage: 'Failed to send password reset SMS',
      );

      return result.fold(
        (data) => FlowyResult.success(true),
        (error) => FlowyResult.failure(error),
      );
    } else {
      // 使用 /recover 接口（只支持邮箱）
      final body = <String, dynamic>{
        'email': email,
      };
      
      final result = await _makeRequest(
        endpoint: PasswordEndpoint.forgotPassword,
        body: body,
        errorMessage: 'Failed to send password reset email',
      );

      return result.fold(
        (data) => FlowyResult.success(true),
        (error) => FlowyResult.failure(error),
      );
    }
  }

  /// Sets up a password for a user that doesn't have one
  ///
  /// [newPassword] - The new password to set
  Future<FlowyResult<bool, FlowyError>> setupPassword({
    required String newPassword,
  }) async {
    final result = await _makeRequest(
      endpoint: PasswordEndpoint.setupPassword,
      body: {'password': newPassword},
      errorMessage: 'Failed to setup password',
    );

    return result.fold(
      (data) => FlowyResult.success(true),
      (error) => FlowyResult.failure(error),
    );
  }

  /// Checks if the user has a password set
  Future<FlowyResult<bool, FlowyError>> checkHasPassword() async {
    final result = await _makeRequest(
      endpoint: PasswordEndpoint.checkHasPassword,
      errorMessage: 'Failed to check password status',
    );

    try {
      return result.fold(
        (data) => FlowyResult.success(data['has_password'] ?? false),
        (error) => FlowyResult.failure(error),
      );
    } catch (e) {
      return FlowyResult.failure(
        FlowyError(msg: 'Failed to check password status: $e'),
      );
    }
  }

  /// Checks if a user has set a password (public endpoint, no auth required)
  ///
  /// [email] - The email address of the user (optional)
  /// [phone] - The phone number of the user (optional)
  /// Note: Either email or phone must be provided, but not both
  Future<FlowyResult<bool, FlowyError>> checkPasswordStatus({
    String? email,
    String? phone,
  }) async {
    if (email == null && phone == null) {
      return FlowyResult.failure(
        FlowyError(msg: 'Either email or phone must be provided'),
      );
    }
    if (email != null && phone != null) {
      return FlowyResult.failure(
        FlowyError(msg: 'Only provide either email or phone, not both'),
      );
    }

    final queryParameters = <String, String>{};
    if (email != null) {
      queryParameters['email'] = email;
    }
    if (phone != null) {
      queryParameters['phone'] = phone;
    }

    final result = await _makeRequest(
      endpoint: PasswordEndpoint.checkPasswordStatus,
      queryParameters: queryParameters,
      errorMessage: 'Failed to check password status',
    );

    try {
      return result.fold(
        (data) => FlowyResult.success(data['password_is_set'] ?? false),
        (error) => FlowyResult.failure(error),
      );
    } catch (e) {
      return FlowyResult.failure(
        FlowyError(msg: 'Failed to check password status: $e'),
      );
    }
  }

  // Verify the reset password token
  // Supports both email and phone number (GoTrue will auto-detect phone in email field)
  Future<FlowyResult<String, FlowyError>> verifyResetPasswordToken({
    required String email,
    required String token,
    String? phone,
  }) async {
    final body = <String, dynamic>{
      'type': 'recovery',
      'token': token,
    };
    
    // 如果提供了 phone，使用 phone；否则使用 email（GoTrue 会自动检测手机号）
    if (phone != null && phone.isNotEmpty) {
      body['phone'] = phone;
    } else {
      body['email'] = email;
    }
    
    final result = await _makeRequest(
      endpoint: PasswordEndpoint.verifyResetPasswordToken,
      body: body,
      errorMessage: 'Failed to verify reset password token',
    );

    try {
      return result.fold(
        (data) {
          final authToken = data['access_token'];
          return FlowyResult.success(authToken);
        },
        (error) => FlowyResult.failure(error),
      );
    } catch (e) {
      return FlowyResult.failure(
        FlowyError(msg: 'Failed to verify reset password token: $e'),
      );
    }
  }

  /// Makes a request to the specified endpoint with the given body
  Future<FlowyResult<dynamic, FlowyError>> _makeRequest({
    required PasswordEndpoint endpoint,
    Map<String, dynamic>? body,
    Map<String, String>? queryParameters,
    String errorMessage = 'Request failed',
  }) async {
    try {
      final uri = endpoint.uri(baseUrl, queryParameters: queryParameters);
      Log.info(
        '🦋[PasswordHttpService] Making ${endpoint.method} request to: $uri',
      );
      Log.info(
        '🦋[PasswordHttpService] baseUrl: $baseUrl, endpoint path: ${endpoint.path}',
      );
      http.Response response;

      if (endpoint.method == 'POST') {
        response = await client.post(
          uri,
          headers: headers,
          body: body != null ? jsonEncode(body) : null,
        );
      } else if (endpoint.method == 'PUT') {
        response = await client.put(
          uri,
          headers: headers,
          body: body != null ? jsonEncode(body) : null,
        );
      } else if (endpoint.method == 'GET') {
        response = await client.get(
          uri,
          headers: headers,
        );
      } else {
        return FlowyResult.failure(
          FlowyError(msg: 'Invalid request method: ${endpoint.method}'),
        );
      }

      Log.info(
        '🦋[PasswordHttpService] Response status: ${response.statusCode}, body length: ${response.body.length}',
      );
      
      if (response.statusCode == 200) {
        if (response.body.isNotEmpty) {
          try {
            final decodedBody = jsonDecode(response.body);
            Log.info(
              '🦋[PasswordHttpService] Response decoded successfully: $decodedBody',
            );
            return FlowyResult.success(decodedBody);
          } catch (e) {
            Log.error(
              '🦋[PasswordHttpService] Failed to decode response body: $e, body: ${response.body}',
            );
            return FlowyResult.failure(
              FlowyError(msg: 'Failed to decode response: $e'),
            );
          }
        }
        return FlowyResult.success(true);
      } else {
        Log.error(
          '🦋[PasswordHttpService] Request failed with status ${response.statusCode}, body: ${response.body}',
        );
        
        // 尝试解析错误响应体
        Map<String, dynamic> errorBody = {};
        if (response.body.isNotEmpty) {
          try {
            errorBody = jsonDecode(response.body) as Map<String, dynamic>;
          } catch (e) {
            // 如果响应不是 JSON（例如 HTML 404 页面），记录错误但继续处理
            Log.error(
              '🦋[PasswordHttpService] Failed to parse error response as JSON: $e, body preview: ${response.body.substring(0, response.body.length > 200 ? 200 : response.body.length)}',
            );
            // 对于非 JSON 响应，使用默认错误消息
            errorBody = {};
          }
        }

        final errorCodeFromServer =
            (errorBody['error_code'] ?? '') as String? ?? '';

        // 首次设置密码时，服务器可能因为重复提交返回 same_password，这里直接视为成功避免卡住用户
        if (endpoint == PasswordEndpoint.setupPassword &&
            errorCodeFromServer == 'same_password') {
          Log.info(
            '🦋[PasswordHttpService] setupPassword received same_password, treat as success because password is already up-to-date.',
          );
          return FlowyResult.success(true);
        }

        // the checkHasPassword endpoint will return 403, which is not an error
        if (endpoint != PasswordEndpoint.checkHasPassword) {
          Log.info(
            '${endpoint.name} request failed: ${response.statusCode}, $errorBody ',
          );
        }

        ErrorCode errorCode = ErrorCode.Internal;

        if (response.statusCode == 422) {
          errorCode = ErrorCode.NewPasswordTooWeak;
        } else if (response.statusCode == 404) {
          // 404 通常表示用户不存在，这是一个正常情况，不应该作为错误处理
          // 但为了保持一致性，我们仍然返回错误，由调用方决定如何处理
          errorCode = ErrorCode.RecordNotFound;
        }

        return FlowyResult.failure(
          FlowyError(
            code: errorCode,
            msg: errorBody['msg'] ?? errorMessage,
          ),
        );
      }
    } catch (e) {
      Log.error('${endpoint.name} request failed: error: $e');

      return FlowyResult.failure(
        FlowyError(msg: 'Network error: ${e.toString()}'),
      );
    }
  }

  /// Signs in with password using GoTrue API
  /// Supports both email and phone number login
  ///
  /// [email] - The email address (optional if phone is provided)
  /// [phone] - The phone number (optional if email is provided)
  /// [password] - The user's password
  ///
  /// Returns GotrueTokenResponse with access_token and refresh_token
  Future<FlowyResult<Map<String, dynamic>, FlowyError>> signInWithPassword({
    String? email,
    String? phone,
    required String password,
  }) async {
    if (email == null && phone == null) {
      return FlowyResult.failure(
        FlowyError(msg: 'Either email or phone must be provided'),
      );
    }

    if (email != null && phone != null) {
      return FlowyResult.failure(
        FlowyError(msg: 'Only provide either email or phone, not both'),
      );
    }

    try {
      final uri = Uri.parse('$baseUrl/token?grant_type=password');
      Log.info(
        '🦋[PasswordHttpService] Making password login request to: $uri',
      );
      Log.info(
        '🦋[PasswordHttpService] email: ${email ?? "null"}, phone: ${phone ?? "null"}',
      );

      final body = <String, dynamic>{
        'password': password,
      };

      if (email != null) {
        body['email'] = email;
      } else {
        body['phone'] = phone;
      }

      final response = await client.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );

      Log.info(
        '🦋[PasswordHttpService] Password login response status: ${response.statusCode}, body length: ${response.body.length}',
      );

      if (response.statusCode == 200) {
        try {
          final decodedBody = jsonDecode(response.body) as Map<String, dynamic>;
          Log.info(
            '🦋[PasswordHttpService] Password login successful',
          );
          return FlowyResult.success(decodedBody);
        } catch (e) {
          Log.error(
            '🦋[PasswordHttpService] Failed to decode password login response: $e, body: ${response.body}',
          );
          return FlowyResult.failure(
            FlowyError(msg: 'Failed to decode response: $e'),
          );
        }
      } else {
        Log.error(
          '🦋[PasswordHttpService] Password login failed with status ${response.statusCode}, body: ${response.body}',
        );

        Map<String, dynamic> errorBody = {};
        if (response.body.isNotEmpty) {
          try {
            errorBody = jsonDecode(response.body) as Map<String, dynamic>;
          } catch (e) {
            Log.error(
              '🦋[PasswordHttpService] Failed to parse error response as JSON: $e',
            );
            errorBody = {};
          }
        }

        ErrorCode errorCode = ErrorCode.Internal;

        if (response.statusCode == 400) {
          // Invalid credentials
          errorCode = ErrorCode.UserUnauthorized;
        } else if (response.statusCode == 422) {
          errorCode = ErrorCode.NewPasswordTooWeak;
        }

        return FlowyResult.failure(
          FlowyError(
            code: errorCode,
            msg: errorBody['msg'] ?? 'Password login failed',
          ),
        );
      }
    } catch (e) {
      Log.error('🦋[PasswordHttpService] Password login request failed: error: $e');

      return FlowyResult.failure(
        FlowyError(msg: 'Network error: ${e.toString()}'),
      );
    }
  }

  /// Signs in with third party provider (e.g., WeChat, DouYin)
  /// Uses GoTrue API with grant_type=third_party
  ///
  /// [platform] - The platform name (e.g., "weixin", "douyin")
  /// [code] - The authorization code from the third party SDK
  ///
  /// Returns GotrueTokenResponse with access_token and refresh_token
  Future<FlowyResult<Map<String, dynamic>, FlowyError>> signInWithThirdParty({
    required String platform,
    required String code,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/token?grant_type=third_party');
      Log.info(
        '🦋[PasswordHttpService] Making third party login request to: $uri',
      );
      Log.info(
        '🦋[PasswordHttpService] platform: $platform',
      );

      final body = <String, dynamic>{
        'platform': platform,
        'code': code,
      };

      final response = await client.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );

      Log.info(
        '🦋[PasswordHttpService] Third party login response status: ${response.statusCode}, body length: ${response.body.length}',
      );

      if (response.statusCode == 200) {
        try {
          final decodedBody = jsonDecode(response.body) as Map<String, dynamic>;
          Log.info(
            '🦋[PasswordHttpService] Third party login successful',
          );
          return FlowyResult.success(decodedBody);
        } catch (e) {
          Log.error(
            '🦋[PasswordHttpService] Failed to decode third party login response: $e, body: ${response.body}',
          );
          return FlowyResult.failure(
            FlowyError(msg: 'Failed to decode response: $e'),
          );
        }
      } else {
        Log.error(
          '🦋[PasswordHttpService] Third party login failed with status ${response.statusCode}, body: ${response.body}',
        );

        Map<String, dynamic> errorBody = {};
        if (response.body.isNotEmpty) {
          try {
            errorBody = jsonDecode(response.body) as Map<String, dynamic>;
          } catch (e) {
            Log.error(
              '🦋[PasswordHttpService] Failed to parse error response as JSON: $e',
            );
            errorBody = {};
          }
        }

        ErrorCode errorCode = ErrorCode.Internal;

        if (response.statusCode == 400) {
          // Invalid credentials or code
          errorCode = ErrorCode.UserUnauthorized;
        } else if (response.statusCode == 422) {
          errorCode = ErrorCode.InvalidParams;
        }

        return FlowyResult.failure(
          FlowyError(
            code: errorCode,
            msg: errorBody['msg'] ?? errorBody['error_description'] ?? 'Third party login failed',
          ),
        );
      }
    } catch (e) {
      Log.error('🦋[PasswordHttpService] Third party login request failed: error: $e');

      return FlowyResult.failure(
        FlowyError(msg: 'Network error: ${e.toString()}'),
      );
    }
  }
}
