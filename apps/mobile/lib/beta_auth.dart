import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class BetaConfig {
  const BetaConfig._();

  static const apiBaseUrl = String.fromEnvironment('PT_API_BASE_URL');
  static const environment = String.fromEnvironment(
    'PT_ENVIRONMENT',
    defaultValue: 'local',
  );
  static bool get configured => apiBaseUrl.trim().isNotEmpty;
  static const registrationConsentVersion = '2026-08-06-v1';
  static const registrationConsentLocale = 'ru-RU';
}

class ApiFailure implements Exception {
  const ApiFailure(this.code, {this.requestId, this.statusCode});
  final String code;
  final String? requestId;
  final int? statusCode;

  String get userMessage => switch (code) {
        'unauthorized' ||
        'invalid_credentials' =>
          'Не удалось подтвердить вход.',
        'tenant_access_denied' ||
        'forbidden' =>
          'Нет доступа к этому пространству.',
        'knowledge_conflict' => 'Документ был изменён в другом сеансе.',
        'ai_user_budget_exceeded' => 'На сегодня исчерпан лимит AI-запросов.',
        'network_timeout' => 'Сервер не ответил вовремя. Попробуйте ещё раз.',
        'network_unavailable' =>
          'Не удалось подключиться к production API. Проверьте интернет и попробуйте ещё раз.',
        'api_not_configured' => 'Для beta не настроен адрес API.',
        'email_already_registered' =>
          'Этот email уже зарегистрирован. Войдите или восстановите пароль.',
        'registration_disabled' =>
          'Регистрация временно отключена на сервере.',
        'invalid_request' =>
          'Проверьте имя, email и пароль. Пароль должен содержать минимум 12 символов, буквы и цифры.',
        'api_disabled' => 'Production API временно отключён.',
        'request_failed' =>
          'Production API отклонил запрос. Попробуйте ещё раз позже.',
        'email_verification_required' =>
          'Регистрация создана. Подтвердите email по ссылке или кодом из письма.',
        'consent_version_invalid' =>
          'Версия документов регистрации устарела. Обновите приложение.',
        'consent_required' =>
          'Для регистрации нужно принять оферту и предупреждение об AI.',
        _ => 'Не удалось выполнить действие. Попробуйте ещё раз.',
      };
}

class BetaTokens {
  const BetaTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.tenantId,
  });
  final String accessToken;
  final String refreshToken;
  final String tenantId;
}

abstract class TokenStorage {
  Future<BetaTokens?> read();
  Future<void> write(BetaTokens tokens);
  Future<void> clear();
}

class SecureTokenStorage implements TokenStorage {
  const SecureTokenStorage([this._storage = const FlutterSecureStorage()]);
  final FlutterSecureStorage _storage;
  static const _accessKey = 'pt.beta.access';
  static const _refreshKey = 'pt.beta.refresh';
  static const _tenantKey = 'pt.beta.tenant';

  @override
  Future<BetaTokens?> read() async {
    final values = await _storage.readAll();
    final access = values[_accessKey];
    final refresh = values[_refreshKey];
    final tenant = values[_tenantKey];
    if (access == null || refresh == null || tenant == null) return null;
    return BetaTokens(
        accessToken: access, refreshToken: refresh, tenantId: tenant);
  }

  @override
  Future<void> write(BetaTokens tokens) => Future.wait([
        _storage.write(key: _accessKey, value: tokens.accessToken),
        _storage.write(key: _refreshKey, value: tokens.refreshToken),
        _storage.write(key: _tenantKey, value: tokens.tenantId),
      ]);

  @override
  Future<void> clear() => _storage.deleteAll();
}

class MemoryTokenStorage implements TokenStorage {
  BetaTokens? value;
  @override
  Future<void> clear() async => value = null;
  @override
  Future<BetaTokens?> read() async => value;
  @override
  Future<void> write(BetaTokens tokens) async => value = tokens;
}

class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    required this.displayName,
    required this.status,
    this.emailVerifiedAt,
  });
  final String id;
  final String email;
  final String displayName;
  final String status;
  final String? emailVerifiedAt;

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        id: json['id'] as String,
        email: json['email'] as String,
        displayName: json['displayName'] as String,
        status: json['status'] as String,
        emailVerifiedAt: json['emailVerifiedAt'] as String?,
      );
}

class TenantInfo {
  const TenantInfo({required this.id, required this.name, required this.type});
  final String id;
  final String name;
  final String type;

  factory TenantInfo.fromMembership(Map<String, dynamic> json) {
    final tenant = json['tenant'] as Map<String, dynamic>;
    return TenantInfo(
      id: tenant['id'] as String,
      name: tenant['name'] as String,
      type: tenant['type'] as String,
    );
  }
}

class BetaSession {
  const BetaSession({
    required this.tokens,
    required this.user,
    required this.tenants,
  });
  final BetaTokens tokens;
  final AuthUser user;
  final List<TenantInfo> tenants;

  TenantInfo? get activeTenant =>
      tenants.where((item) => item.id == tokens.tenantId).firstOrNull;
}

class AuthApiClient {
  AuthApiClient({required this.baseUrl, http.Client? client})
      : _client = client ?? http.Client();
  final String baseUrl;
  final http.Client _client;

  Uri _uri(String path) =>
      Uri.parse('${baseUrl.replaceFirst(RegExp(r'/*$'), '')}$path');

  Future<dynamic> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? accessToken,
  }) async {
    if (baseUrl.isEmpty) throw const ApiFailure('api_not_configured');
    final requestId =
        '${DateTime.now().microsecondsSinceEpoch}-${identityHashCode(this)}';
    try {
      final request = http.Request(method, _uri(path))
        ..headers.addAll({
          'accept': 'application/json',
          'x-request-id': requestId,
          if (body != null) 'content-type': 'application/json',
          if (accessToken != null) 'authorization': 'Bearer $accessToken',
        });
      if (body != null) request.body = jsonEncode(body);
      final streamed =
          await _client.send(request).timeout(const Duration(seconds: 20));
      final response = await http.Response.fromStream(streamed);
      final decoded = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final error =
            decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
        throw ApiFailure(
          (error['error'] as String?) ?? 'request_failed',
          statusCode: response.statusCode,
          requestId: (error['requestId'] as String?) ??
              response.headers['x-request-id'],
        );
      }
      return decoded;
    } on TimeoutException {
      throw const ApiFailure('network_timeout');
    } on ApiFailure {
      rethrow;
    } catch (_) {
      throw const ApiFailure('network_unavailable');
    }
  }

  Future<dynamic> requestBytes(
    String path,
    List<int> bytes, {
    required String accessToken,
  }) async {
    if (baseUrl.isEmpty) throw const ApiFailure('api_not_configured');
    final requestId =
        '${DateTime.now().microsecondsSinceEpoch}-${identityHashCode(this)}';
    try {
      final request = http.Request('POST', _uri(path))
        ..headers.addAll({
          'accept': 'application/json',
          'content-type': 'application/zip',
          'authorization': 'Bearer $accessToken',
          'x-request-id': requestId,
        })
        ..bodyBytes = bytes;
      final streamed =
          await _client.send(request).timeout(const Duration(seconds: 45));
      final response = await http.Response.fromStream(streamed);
      final decoded = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final error =
            decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
        throw ApiFailure((error['error'] as String?) ?? 'request_failed',
            statusCode: response.statusCode,
            requestId: (error['requestId'] as String?) ??
                response.headers['x-request-id']);
      }
      return decoded;
    } on TimeoutException {
      throw const ApiFailure('network_timeout');
    } on ApiFailure {
      rethrow;
    } catch (_) {
      throw const ApiFailure('network_unavailable');
    }
  }

  Future<BetaTokens> login(String email, String password) async {
    final json = await request('POST', '/api/auth/login', body: {
      'email': email,
      'password': password,
    }) as Map<String, dynamic>;
    return BetaTokens(
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String,
      tenantId: json['tenantId'] as String,
    );
  }

  Future<BetaTokens> register(
      String displayName, String email, String password) async {
    final registered = await request('POST', '/api/auth/register', body: {
      'displayName': displayName,
      'email': email,
      'password': password,
      'consent': {
        'accepted': true,
        'documentVersion': BetaConfig.registrationConsentVersion,
        'locale': BetaConfig.registrationConsentLocale,
      },
    }) as Map<String, dynamic>;
    if (registered['verificationRequired'] == true) {
      throw const ApiFailure('email_verification_required');
    }
    // Registration deliberately does not mint a refresh token on the current
    // backend contract; login immediately obtains a tracked session.
    return login(email, password);
  }

  Future<BetaTokens> refresh(BetaTokens tokens) async {
    final json = await request('POST', '/api/auth/refresh', body: {
      'refreshToken': tokens.refreshToken,
    }) as Map<String, dynamic>;
    return BetaTokens(
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String,
      tenantId: json['tenantId'] as String,
    );
  }
}

class SessionManager extends ChangeNotifier {
  SessionManager({required AuthApiClient api, required TokenStorage storage})
      : _api = api,
        _storage = storage;
  final AuthApiClient _api;
  final TokenStorage _storage;
  BetaSession? session;
  bool restoring = true;
  ApiFailure? lastFailure;
  Future<BetaTokens?>? _refreshFlight;

  Future<void> restore() async {
    if (!restoring) return;
    final tokens = await _storage.read();
    if (tokens == null) return _finishRestore();
    try {
      await _establish(tokens, allowRefresh: true);
    } on ApiFailure {
      await _storage.clear();
      session = null;
    } finally {
      _finishRestore();
    }
  }

  void _finishRestore() {
    restoring = false;
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    lastFailure = null;
    try {
      await _establish(await _api.login(email.trim(), password),
          allowRefresh: false);
    } on ApiFailure catch (error) {
      lastFailure = error;
      rethrow;
    }
  }

  Future<void> register(
      String displayName, String email, String password) async {
    lastFailure = null;
    try {
      await _establish(
          await _api.register(displayName.trim(), email.trim(), password),
          allowRefresh: false);
    } on ApiFailure catch (error) {
      lastFailure = error;
      rethrow;
    }
  }

  Future<void> _establish(BetaTokens tokens,
      {required bool allowRefresh}) async {
    try {
      final me = await _api.request('GET', '/api/auth/me',
          accessToken: tokens.accessToken) as Map<String, dynamic>;
      final tenants = await _loadTenants(tokens.accessToken);
      final activeTenant = me['activeTenantId'] as String;
      if (!tenants.any((tenant) => tenant.id == activeTenant)) {
        throw const ApiFailure('tenant_access_denied');
      }
      final secured = BetaTokens(
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
        tenantId: activeTenant,
      );
      session = BetaSession(
        tokens: secured,
        user: AuthUser.fromJson(me['user'] as Map<String, dynamic>),
        tenants: tenants,
      );
      await _storage.write(secured);
      notifyListeners();
    } on ApiFailure catch (error) {
      if (allowRefresh && error.statusCode == 401) {
        final refreshed = await _refresh(tokens);
        if (refreshed == null) rethrow;
        return _establish(refreshed, allowRefresh: false);
      }
      rethrow;
    }
  }

  Future<List<TenantInfo>> _loadTenants(String accessToken) async {
    final response =
        await _api.request('GET', '/api/tenants', accessToken: accessToken);
    final values = response is Map<String, dynamic>
        ? response['items'] ?? response['data'] ?? response
        : response;
    final list = values is List ? values : <dynamic>[];
    return list
        .cast<Map<String, dynamic>>()
        .map(TenantInfo.fromMembership)
        .toList(growable: false);
  }

  Future<BetaTokens?> _refresh(BetaTokens tokens) {
    final current = _refreshFlight;
    if (current != null) return current;
    final flight = () async {
      try {
        final value = await _api.refresh(tokens);
        await _storage.write(value);
        return value;
      } catch (_) {
        await _storage.clear();
        session = null;
        notifyListeners();
        return null;
      }
    }();
    _refreshFlight = flight;
    flight.whenComplete(() => _refreshFlight = null);
    return flight;
  }

  Future<dynamic> authenticatedRequest(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool retryOnUnauthorized = true,
  }) async {
    final current = session;
    if (current == null) throw const ApiFailure('unauthorized');
    try {
      return await _api.request(method, path,
          body: body, accessToken: current.tokens.accessToken);
    } on ApiFailure catch (error) {
      if (!retryOnUnauthorized || error.statusCode != 401) rethrow;
      final refreshed = await _refresh(current.tokens);
      if (refreshed == null) throw const ApiFailure('unauthorized');
      await _establish(refreshed, allowRefresh: false);
      return authenticatedRequest(method, path,
          body: body, retryOnUnauthorized: false);
    }
  }

  Future<void> switchTenant(String tenantId) async {
    final response = await authenticatedRequest('POST', '/api/tenants/switch',
        body: {'tenantId': tenantId}) as Map<String, dynamic>;
    final current = session;
    if (current == null) return;
    final tokens = BetaTokens(
      accessToken: response['accessToken'] as String,
      refreshToken: current.tokens.refreshToken,
      tenantId: response['tenantId'] as String,
    );
    await _establish(tokens, allowRefresh: false);
  }

  Future<void> acceptInvitation(String token) async {
    final response = await authenticatedRequest(
            'POST', '/api/invitations/accept', body: {'token': token})
        as Map<String, dynamic>;
    final current = session;
    if (current == null) return;
    final tokens = BetaTokens(
      accessToken: response['accessToken'] as String,
      refreshToken: current.tokens.refreshToken,
      tenantId: response['tenantId'] as String,
    );
    await _establish(tokens, allowRefresh: false);
  }

  Future<void> requestPasswordReset(String email) async {
    await _api.request('POST', '/api/auth/forgot-password',
        body: {'email': email.trim()});
  }

  Future<void> resetPassword(String token, String password) async {
    await _api.request('POST', '/api/auth/reset-password',
        body: {'token': token.trim(), 'password': password});
  }

  Future<void> verifyEmail(String token) async {
    await _api.request('POST', '/api/auth/verify-email',
        body: {'token': token.trim()});
  }

  Future<void> resendVerification(String email) async {
    await _api.request('POST', '/api/auth/resend-verification',
        body: {'email': email.trim()});
  }

  Future<dynamic> uploadVaultDryRun(List<int> archive) async {
    final current = session;
    if (current == null) throw const ApiFailure('unauthorized');
    try {
      return await _api.requestBytes(
          '/api/knowledge/vault/import/dry-run', archive,
          accessToken: current.tokens.accessToken);
    } on ApiFailure catch (error) {
      if (error.statusCode != 401) rethrow;
      final refreshed = await _refresh(current.tokens);
      if (refreshed == null) throw const ApiFailure('unauthorized');
      await _establish(refreshed, allowRefresh: false);
      return uploadVaultDryRun(archive);
    }
  }

  Future<void> logout({bool allDevices = false}) async {
    final current = session;
    try {
      if (current != null) {
        await authenticatedRequest(
          'POST',
          allDevices ? '/api/auth/logout-all' : '/api/auth/logout',
          body:
              allDevices ? null : {'refreshToken': current.tokens.refreshToken},
          retryOnUnauthorized: false,
        );
      }
    } finally {
      await _storage.clear();
      session = null;
      notifyListeners();
    }
  }
}

typedef AuthenticatedBuilder = Widget Function(
    BuildContext context, BetaSession session);

class BetaSessionGate extends StatefulWidget {
  const BetaSessionGate(
      {super.key, required this.manager, required this.builder});
  final SessionManager manager;
  final AuthenticatedBuilder builder;

  @override
  State<BetaSessionGate> createState() => _BetaSessionGateState();
}

class _BetaSessionGateState extends State<BetaSessionGate> {
  @override
  void initState() {
    super.initState();
    widget.manager.addListener(_changed);
    unawaited(widget.manager.restore());
  }

  @override
  void dispose() {
    widget.manager.removeListener(_changed);
    super.dispose();
  }

  void _changed() => mounted ? setState(() {}) : null;

  @override
  Widget build(BuildContext context) {
    if (!BetaConfig.configured)
      return widget.builder(context, const _OfflineSession());
    if (widget.manager.restoring) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final session = widget.manager.session;
    return session == null
        ? LoginScreen(manager: widget.manager)
        : widget.builder(context, session);
  }
}

class _OfflineSession extends BetaSession {
  const _OfflineSession()
      : super(
          tokens: const BetaTokens(
              accessToken: '', refreshToken: '', tenantId: 'offline'),
          user: const AuthUser(
              id: 'offline',
              email: 'offline',
              displayName: 'Offline',
              status: 'ACTIVE'),
          tenants: const [
            TenantInfo(
                id: 'offline', name: 'Offline workspace', type: 'PERSONAL')
          ],
        );
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.manager});
  final SessionManager manager;
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool register = false;
  bool consentAccepted = false;
  bool busy = false;
  String? message;
  final name = TextEditingController();

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    name.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (register && !consentAccepted) {
      setState(() => message =
          'Для регистрации нужно принять оферту и предупреждение об AI.');
      return;
    }
    setState(() {
      busy = true;
      message = null;
    });
    try {
      if (register) {
        await widget.manager.register(name.text, email.text, password.text);
      } else {
        await widget.manager.login(email.text, password.text);
      }
    } on ApiFailure catch (error) {
      if (mounted) {
        setState(() => message = error.userMessage);
        if (error.code == 'email_verification_required') {
          await showDialog<void>(
            context: context,
            builder: (_) => _EmailVerificationDialog(
              manager: widget.manager,
              email: email.text.trim(),
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> forgotPassword() async {
    final controller = TextEditingController(text: email.text.trim());
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Восстановить пароль'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Email'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Отправить')),
        ],
      ),
    );
    if (accepted != true) return;
    try {
      await widget.manager.requestPasswordReset(controller.text);
      if (mounted)
        setState(() => message =
            'Если аккаунт существует, инструкция по восстановлению отправлена на почту.');
    } on ApiFailure catch (error) {
      if (mounted) setState(() => message = error.userMessage);
    } finally {
      controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                        register
                            ? 'Создать личное пространство'
                            : 'Войти в Personal Tracker',
                        style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 20),
                    if (register)
                      TextField(
                          controller: name,
                          decoration: const InputDecoration(labelText: 'Имя')),
                    if (register) const SizedBox(height: 12),
                    if (register)
                      CheckboxListTile(
                        value: consentAccepted,
                        onChanged: busy
                            ? null
                            : (value) => setState(
                                () => consentAccepted = value ?? false),
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: const Text(
                            'Принимаю оферту и понимаю, что советы AI могут быть ошибочными, не являются медицинской рекомендацией и не заменяют специалиста.'),
                      ),
                    if (register) const SizedBox(height: 4),
                    TextField(
                        controller: email,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(labelText: 'Email')),
                    const SizedBox(height: 12),
                    TextField(
                        controller: password,
                        obscureText: true,
                        decoration: const InputDecoration(
                            labelText:
                                'Пароль (минимум 12 символов, буква и цифра)')),
                    if (message != null)
                      Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(message!,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error))),
                    const SizedBox(height: 18),
                    FilledButton(
                        onPressed: busy ? null : submit,
                        child: busy
                            ? const CircularProgressIndicator()
                            : Text(register ? 'Зарегистрироваться' : 'Войти')),
                    TextButton(
                        onPressed: busy
                            ? null
                            : () => setState(() => register = !register),
                        child: Text(register
                            ? 'Уже есть аккаунт? Войти'
                            : 'Нет аккаунта? Создать')),
                    if (!register)
                      TextButton(
                          onPressed: busy ? null : forgotPassword,
                          child: const Text('Не помню пароль')),
                    if (!register)
                      TextButton(
                          onPressed: busy
                              ? null
                              : () => showDialog<void>(
                                  context: context,
                                  builder: (_) => _ManualResetDialog(
                                      manager: widget.manager)),
                          child: const Text('Ввести код из письма')),
                    const Text(
                        'После регистрации подтвердите email. Если ссылка не открылась, используйте код из письма вручную.',
                        textAlign: TextAlign.center),
                  ]),
            ),
          ),
        ),
      );
}

class _EmailVerificationDialog extends StatefulWidget {
  const _EmailVerificationDialog({required this.manager, required this.email});
  final SessionManager manager;
  final String email;

  @override
  State<_EmailVerificationDialog> createState() =>
      _EmailVerificationDialogState();
}

class _EmailVerificationDialogState extends State<_EmailVerificationDialog> {
  final token = TextEditingController();
  String? error;
  bool busy = false;

  @override
  void dispose() {
    token.dispose();
    super.dispose();
  }

  Future<void> verify() async {
    if (token.text.trim().isEmpty) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.manager.verifyEmail(token.text);
      if (mounted) Navigator.pop(context);
    } on ApiFailure catch (value) {
      if (mounted) setState(() => error = value.userMessage);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> resend() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.manager.resendVerification(widget.email);
      if (mounted) {
        setState(() => error =
            'Новое письмо отправлено, если аккаунт ожидает подтверждения.');
      }
    } on ApiFailure catch (value) {
      if (mounted) setState(() => error = value.userMessage);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Подтвердите email'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Откройте письмо и вставьте код из ссылки подтверждения.'),
          const SizedBox(height: 12),
          TextField(
            controller: token,
            enabled: !busy,
            decoration: const InputDecoration(labelText: 'Код из письма'),
          ),
          if (error != null) ...[
            const SizedBox(height: 10),
            Text(error!, style: TextStyle(color: Colors.orange)),
          ],
        ]),
        actions: [
          TextButton(
              onPressed: busy ? null : resend,
              child: const Text('Отправить ещё раз')),
          TextButton(
              onPressed: busy ? null : () => Navigator.pop(context),
              child: const Text('Закрыть')),
          FilledButton(
              onPressed: busy ? null : verify,
              child: const Text('Подтвердить')),
        ],
      );
}

class _ManualResetDialog extends StatefulWidget {
  const _ManualResetDialog({required this.manager});
  final SessionManager manager;
  @override
  State<_ManualResetDialog> createState() => _ManualResetDialogState();
}

class _ManualResetDialogState extends State<_ManualResetDialog> {
  final token = TextEditingController();
  final password = TextEditingController();
  String? error;
  bool busy = false;
  @override
  void dispose() {
    token.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.manager.resetPassword(token.text, password.text);
      if (mounted) Navigator.pop(context);
    } on ApiFailure catch (value) {
      if (mounted) setState(() => error = value.userMessage);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Новый пароль'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: token,
              decoration:
                  const InputDecoration(labelText: 'Код или token из письма')),
          TextField(
              controller: password,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: 'Новый пароль (12+ символов, буква и цифра)')),
          if (error != null)
            Text(error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: busy ? null : submit,
              child: const Text('Сохранить пароль')),
        ],
      );
}
