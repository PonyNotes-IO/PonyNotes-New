part of 'mcp_tools.dart';

extension _McpAccountTools on McpTools {
  List<McpToolSpec> get _accountSpecs => [
        _actionTool(
          'account_authentication',
          '本人资料、登录验证和联系方式绑定。凭据和验证码仅通过用户在system_action中输入得到的credential_ref传入。',
          {
            'name': const JsonString(),
            'avatar_url': const JsonString(),
            'method': const JsonString(
              enumValues: [
                'password',
                'magic_link',
                'passcode',
                'oauth',
                'signup',
              ],
            ),
            'email': const JsonString(),
            'phone': const JsonString(),
            'provider': const JsonString(),
            'credential_ref': const JsonString(),
            'new_credential_ref': const JsonString(),
            'operation': const JsonString(enumValues: ['start', 'complete']),
            'kind': const JsonString(enumValues: ['phone', 'email']),
          },
          [
            'update_user_profile',
            'start_authentication',
            'complete_authentication',
            'switch_account',
            'sign_out',
            'bind_contact',
            'change_account_password',
            'delete_account',
            'manage_login_sessions',
            'unbind_contact',
          ],
          _accountAuthentication,
        ),
        _actionTool(
          'manage_cloud_connection',
          '读取脱敏云连接信息或打开既有自托管设置完成切换。',
          {
            'operation':
                const JsonString(enumValues: ['get', 'update', 'test']),
          },
          [],
          _manageCloudConnection,
          required: const ['workspace_id', 'operation'],
        ),
        _actionTool(
          'billing_records',
          '读取套餐/订阅、用量、充值记录和订单支付状态。',
          {
            'operation': const JsonString(enumValues: ['current', 'plans']),
            'kind':
                const JsonString(enumValues: ['usage', 'bills', 'recharges']),
            'order_id': const JsonString(),
            'page': const JsonInteger(minimum: 1),
            'page_size': const JsonInteger(minimum: 1, maximum: 100),
          },
          ['get_subscription', 'get_billing_records', 'get_billing_order'],
          _billingRecords,
        ),
        _actionTool(
          'billing_actions',
          '创建服务端订阅结账链接、打开计费门户、取消订阅或修改周期。操作须所有者和真人确认，支付仍由用户在支付平台完成。',
          {
            'operation':
                const JsonString(enumValues: ['cancel', 'change_period']),
            'order_id': const JsonString(),
            'plan': JsonString(
              enumValues:
                  SubscriptionPlanPB.values.map((value) => value.name).toList(),
            ),
            'interval': JsonString(
              enumValues: RecurringIntervalPB.values
                  .map((value) => value.name)
                  .toList(),
            ),
            'reason': const JsonString(),
          },
          [
            'create_billing_order',
            'open_billing_portal',
            'update_subscription',
            'billing_human_action',
          ],
          _billingActions,
        ),
      ];

  Future<CallToolResult> _openHumanSettings(
    SettingsPage page,
    String purpose,
  ) async {
    final context = AppGlobals.rootNavKey.currentContext;
    final profile = await _currentProfile();
    if (context == null || !context.mounted || profile == null) {
      return _error('ui_unavailable', '请在已登录客户端中执行此操作。');
    }
    unawaited(showSettingsDialog(context, profile, null, page));
    return _ok({
      'status': 'requires_human',
      'purpose': purpose,
      'settings_page': page.name,
    });
  }

  Future<CallToolResult> _accountAuthentication(
    Map<String, dynamic> args,
  ) async {
    final workspace = _requiredString(args, 'workspace_id');
    final check = await _validateWorkspace(workspace);
    if (check != null) return check;
    final profile = (await _currentProfile())!,
        action = _requiredString(args, 'action');
    if (action == 'manage_login_sessions') {
      return _error(
        'unsupported_capability',
        '当前产品没有其他登录设备/会话列表或撤销接口；get_context仅返回当前账号上下文。',
      );
    }
    if (!await _confirm('account_authentication', args)) {
      return _error('permission_denied', '用户未批准账号操作。');
    }
    if (action == 'update_user_profile') {
      if (args['name'] == null && args['avatar_url'] == null) {
        throw const FormatException('需要name或avatar_url');
      }
      await UserBackendService(userId: profile.id)
          .updateUserProfile(
            name: args['name'] as String?,
            iconUrl: args['avatar_url'] as String?,
          )
          .getOrThrow();
      UserBackendService.clearCurrentUserProfileCache();
      return _getContext();
    }
    if (action == 'sign_out') {
      // The established auth service also revokes MCP credentials on logout.
      unawaited(
        Future<void>.delayed(const Duration(milliseconds: 250), () async {
          await getIt<AuthService>().signOut();
          await runAppFlowy();
        }),
      );
      return _ok(
        {'status': 'sign_out_scheduled', 'reconnect_requires_login': true},
      );
    }
    if (action == 'delete_account' ||
        action == 'switch_account' ||
        action == 'unbind_contact') {
      return _openHumanSettings(
        SettingsPage.accountManagement,
        '请完成${action == 'delete_account' ? '身份验证和注销确认' : action == 'unbind_contact' ? '身份验证和解绑' : '账号切换'}；完成后旧MCP授权可能失效',
      );
    }
    if (action == 'bind_contact') {
      final kind = _requiredString(args, 'kind');
      if (args['operation'] == 'start') {
        if (kind == 'phone') {
          await ContactBindingService.sendPhoneVerificationCode(
            _requiredString(args, 'phone'),
          ).getOrThrow();
        } else {
          await ContactBindingService.sendEmailVerificationCode(
            _requiredString(args, 'email'),
          ).getOrThrow();
        }
        return _ok({
          'challenge_sent': true,
          'next': '通过system_action输入验证码，再使用operation=complete',
        });
      }
      final code = await _resolveGrant(
        _requiredString(args, 'credential_ref'),
        'secret',
      );
      if (kind == 'phone') {
        await ContactBindingService.bindPhoneNumber(
          _requiredString(args, 'phone'),
          code,
        ).getOrThrow();
      } else {
        await ContactBindingService.bindEmail(
          _requiredString(args, 'email'),
          code,
        ).getOrThrow();
      }
      return _ok({'bound': kind});
    }
    if (action == 'change_account_password') {
      final env = getIt<AppFlowyCloudSharedEnv>();
      final account = await AgentCloudAccount.current();
      final service = PasswordHttpService(
        baseUrl: env.appflowyCloudConfig.gotrue_url,
        authToken: account.accessToken,
      );
      try {
        if (args['operation'] == 'start') {
          await service
              .forgotPassword(
                email: args['email'] as String? ?? profile.email,
                phone: args['phone'] as String?,
              )
              .getOrThrow();
          return _ok({
            'challenge_sent': true,
            'status': 'requires_human',
            'message': '请在账号设置完成密码重置验证。',
          });
        }
        await service
            .changePassword(
              currentPassword: await _resolveGrant(
                _requiredString(args, 'credential_ref'),
                'secret',
              ),
              newPassword: await _resolveGrant(
                _requiredString(args, 'new_credential_ref'),
                'secret',
              ),
            )
            .getOrThrow();
        return _ok({'password_changed': true});
      } finally {
        service.client.close();
      }
    }
    final auth = getIt<AuthService>();
    final method = _requiredString(args, 'method');
    if (method == 'magic_link') {
      await auth
          .signInWithMagicLink(email: _requiredString(args, 'email'))
          .getOrThrow();
      return _ok({'status': 'requires_human', 'message': '请在邮件中完成登录验证。'});
    }
    if (method == 'oauth') {
      await auth
          .signUpWithOAuth(platform: _requiredString(args, 'provider'))
          .getOrThrow();
      return _ok({'status': 'requires_human', 'message': '请完成第三方登录流程。'});
    }
    final secret =
        await _resolveGrant(_requiredString(args, 'credential_ref'), 'secret');
    if (method == 'signup') {
      await auth
          .signUp(
              name: _requiredString(args, 'name'),
              email: _requiredString(args, 'email'),
              password: secret,)
          .getOrThrow();
    } else if (method == 'password') {
      await auth
          .signInWithEmailPassword(
            email: _requiredString(args, 'email'),
            password: secret,
          )
          .getOrThrow();
    } else {
      await auth
          .signInWithPasscode(
            email: _requiredString(args, 'email'),
            passcode: secret,
          )
          .getOrThrow();
    }
    return _ok({'authentication_completed': true, 'reconnect_required': true});
  }

  Future<CallToolResult> _manageCloudConnection(
    Map<String, dynamic> args,
  ) async {
    final check =
        await _validateWorkspace(_requiredString(args, 'workspace_id'));
    if (check != null) return check;
    final config = await UserEventGetCloudConfig().send().getOrThrow();
    if (args['operation'] == 'get') {
      return _ok({
        'server_url': config.serverUrl,
        'configured': config.serverUrl.isNotEmpty,
      });
    }
    if (args['operation'] == 'test') {
      final response = await _cloudRequest('GET', '/api/server');
      return _ok({'connected': true, 'server': response});
    }
    if (!await _confirm('manage_cloud_connection', args)) {
      return _error('permission_denied', '用户未批准后端切换。');
    }
    return _openHumanSettings(SettingsPage.cloud, '选择并验证自托管服务，切换后端后重新建立MCP授权');
  }

  Future<CallToolResult> _billingRecords(Map<String, dynamic> args) async {
    final workspace = _requiredString(args, 'workspace_id');
    final check = await _validateWorkspace(workspace);
    if (check != null) return check;
    if (args['action'] == 'get_billing_order') {
      final id = _requiredString(args, 'order_id');
      return _ok({
        'order_id': id,
        'status': await PaymentApi.queryPaymentStatus(id).getOrThrow(),
      });
    }
    if (args['action'] == 'get_subscription') {
      if (args['operation'] == 'plans') {
        return _ok(await _cloudRequest('GET', '/api/subscription/plans'));
      }
      return _message(
        await UserBackendService.getWorkspaceSubscriptionInfo(workspace)
            .getOrThrow(),
      );
    }
    if (args['kind'] == 'usage') {
      return _ok(await _cloudRequest('GET', '/api/subscription/usage'));
    }
    final records = await PaymentApi.getMyPaymentList(
      pageNum: _intArg(args, 'page', 1, 1, 0x7fffffff),
      pageSize: _intArg(args, 'page_size', 20, 1, 100),
    ).getOrThrow();
    return _ok({
      'total': records.total,
      'page': records.pageNum,
      'records': records.list
          .map(
            (r) => {
              'order_id': r.orderNo,
              'product': r.productName,
              'amount': r.amount,
              'payment_time': r.payTime,
              'status': r.status,
            },
          )
          .toList(),
    });
  }

  Future<CallToolResult> _billingActions(Map<String, dynamic> args) async {
    final workspace = _requiredString(args, 'workspace_id');
    final check = await _requireOwner(workspace);
    if (check != null) return check;
    if (!await _confirm('billing_actions', args)) {
      return _error('permission_denied', '用户未批准打开计费操作。');
    }
    if (args['action'] == 'open_billing_portal') {
      final portal = await UserEventGetBillingPortal().send().getOrThrow();
      final uri = Uri.parse(portal.url);
      if (uri.scheme != 'https' || uri.userInfo.isNotEmpty) {
        throw StateError('计费门户返回了无效的HTTPS地址');
      }
      return _ok(
        {'opened': await afLaunchUri(uri), 'status': 'requires_human'},
      );
    }
    if (args['action'] == 'create_billing_order' ||
        args['action'] == 'update_subscription') {
      final planName = _requiredString(args, 'plan');
      final plan = SubscriptionPlanPB.values
          .firstWhere((value) => value.name == planName);
      final service = UserBackendService(userId: (await _currentProfile())!.id);
      if (args['action'] == 'create_billing_order') {
        if (plan == SubscriptionPlanPB.Free) {
          throw const FormatException('免费套餐无需创建支付订单');
        }
        final link =
            await service.createSubscription(workspace, plan).getOrThrow();
        final uri = Uri.parse(link.paymentLink);
        if (uri.scheme != 'https' || uri.userInfo.isNotEmpty) {
          throw StateError('支付平台返回了无效的HTTPS地址');
        }
        return _ok({
          'checkout_url': uri.toString(),
          'status': 'requires_human',
          'message': '请通过system_action打开结账链接并核对金额；本结果不表示已支付。',
        });
      }
      final operation = _requiredString(args, 'operation');
      if (operation == 'cancel') {
        await service
            .cancelSubscription(workspace, plan, args['reason'] as String?)
            .getOrThrow();
      } else {
        final intervalName = _requiredString(args, 'interval');
        final interval = RecurringIntervalPB.values
            .firstWhere((value) => value.name == intervalName);
        await service
            .updateSubscriptionPeriod(workspace, plan, interval)
            .getOrThrow();
      }
      return _message(
        await UserBackendService.getWorkspaceSubscriptionInfo(workspace)
            .getOrThrow(),
      );
    }
    return _openHumanSettings(
      SettingsPage.accountManagement,
      '请在现有购买界面选择套餐和金额并确认支付/订阅变更；工具不会跳过支付平台验证',
    );
  }
}
