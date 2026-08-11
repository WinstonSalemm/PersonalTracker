import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:personal_tracker_assistant/beta_auth.dart';
import 'package:personal_tracker_local_storage/local_storage.dart';

class _FakeClient extends http.BaseClient {
  int refreshes = 0;
  bool rejectLogin = false;
  bool rejectRefresh = false;
  bool rejectAccess = false;
  bool switchedTenant = false;

  http.Response _response(Object body, {int status = 200}) =>
      http.Response(jsonEncode(body), status,
          headers: {'content-type': 'application/json'});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    if (path == '/api/auth/login') {
      return http.StreamedResponse(
        Stream.value(_response(
                rejectLogin
                    ? {'error': 'invalid_credentials'}
                    : {
                        'accessToken': 'access-1',
                        'refreshToken': 'refresh-1',
                        'tenantId': 'tenant-1'
                      },
                status: rejectLogin ? 401 : 200)
            .bodyBytes),
        rejectLogin ? 401 : 200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (path == '/api/auth/refresh') {
      refreshes += 1;
      final response = _response(
          rejectRefresh
              ? {'error': 'invalid_refresh_token'}
              : {
                  'accessToken': 'access-2',
                  'refreshToken': 'refresh-2',
                  'tenantId': 'tenant-1'
                },
          status: rejectRefresh ? 401 : 200);
      return http.StreamedResponse(
          Stream.value(response.bodyBytes), response.statusCode,
          headers: response.headers);
    }
    if (path == '/api/auth/me') {
      final response = _response(
          rejectAccess
              ? {'error': 'unauthorized'}
              : {
                  'user': {
                    'id': 'user-1',
                    'email': 'a@example.com',
                    'displayName': 'A',
                    'status': 'ACTIVE',
                    'emailVerifiedAt': null
                  },
                  'activeTenantId': switchedTenant ? 'tenant-2' : 'tenant-1'
                },
          status: rejectAccess ? 401 : 200);
      return http.StreamedResponse(
          Stream.value(response.bodyBytes), response.statusCode,
          headers: response.headers);
    }
    if (path == '/api/tenants') {
      final response = _response([
        {
          'tenant': {
            'id': 'tenant-1',
            'name': 'A — personal',
            'type': 'PERSONAL'
          }
        },
        {
          'tenant': {'id': 'tenant-2', 'name': 'B', 'type': 'TEAM'}
        }
      ]);
      return http.StreamedResponse(
          Stream.value(response.bodyBytes), response.statusCode,
          headers: response.headers);
    }
    if (path == '/api/tenants/switch') {
      switchedTenant = true;
      final response = _response({
        'accessToken': 'access-tenant-2',
        'tenantId': 'tenant-2',
      });
      return http.StreamedResponse(
          Stream.value(response.bodyBytes), response.statusCode,
          headers: response.headers);
    }
    final response = _response({});
    return http.StreamedResponse(
        Stream.value(response.bodyBytes), response.statusCode,
        headers: response.headers);
  }
}

void main() {
  SessionManager manager(_FakeClient client, MemoryTokenStorage storage) =>
      SessionManager(
        api: AuthApiClient(baseUrl: 'https://beta.example', client: client),
        storage: storage,
      );

  test('successful login stores tokens and resolves a backend tenant',
      () async {
    final storage = MemoryTokenStorage();
    final subject = manager(_FakeClient(), storage);
    await subject.login('a@example.com', 'valid-password-1');
    expect(subject.session?.user.email, 'a@example.com');
    expect((await storage.read())?.tenantId, 'tenant-1');
  });

  test('invalid login maps to a typed failure without storing credentials',
      () async {
    final storage = MemoryTokenStorage();
    final client = _FakeClient()..rejectLogin = true;
    await expectLater(manager(client, storage).login('a@example.com', 'bad'),
        throwsA(isA<ApiFailure>()));
    expect(await storage.read(), isNull);
  });

  test('session restore refreshes an expired access token once', () async {
    final storage = MemoryTokenStorage()
      ..value = const BetaTokens(
          accessToken: 'expired',
          refreshToken: 'refresh-1',
          tenantId: 'tenant-1');
    final client = _FakeClient()..rejectAccess = true;
    final subject = manager(client, storage);
    await subject.restore();
    expect(client.refreshes, 1);
    expect(subject.session,
        isNull); // Fake keeps rejecting the replacement access token.
    expect(await storage.read(), isNull);
  });

  test('invalid refresh clears a restored session', () async {
    final storage = MemoryTokenStorage()
      ..value = const BetaTokens(
          accessToken: 'expired',
          refreshToken: 'refresh-1',
          tenantId: 'tenant-1');
    final client = _FakeClient()
      ..rejectAccess = true
      ..rejectRefresh = true;
    final subject = manager(client, storage);
    await subject.restore();
    expect(client.refreshes, 1);
    expect(await storage.read(), isNull);
  });

  test('logout deletes secure-storage abstraction contents', () async {
    final storage = MemoryTokenStorage();
    final subject = manager(_FakeClient(), storage);
    await subject.login('a@example.com', 'valid-password-1');
    await subject.logout();
    expect(subject.session, isNull);
    expect(await storage.read(), isNull);
  });

  test('only a restored session is eligible to claim legacy local data',
      () async {
    final storage = MemoryTokenStorage()
      ..value = const BetaTokens(
        accessToken: 'access-1',
        refreshToken: 'refresh-1',
        tenantId: 'tenant-1',
      );
    final restored = manager(_FakeClient(), storage);
    await restored.restore();
    expect(restored.session?.user.id, 'user-1');
    expect(restored.restoredExistingSession, isTrue);

    await restored.logout();
    expect(restored.restoredExistingSession, isFalse);

    final fresh = manager(_FakeClient(), MemoryTokenStorage());
    await fresh.login('a@example.com', 'valid-password-1');
    expect(fresh.restoredExistingSession, isFalse);
  });

  testWidgets('unconfigured build does not enter an offline domain session',
      (tester) async {
    var authenticatedBuilderCalled = false;
    final subject = SessionManager(
      api: AuthApiClient(baseUrl: ''),
      storage: MemoryTokenStorage(),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: BetaSessionGate(
          manager: subject,
          builder: (context, session) {
            authenticatedBuilderCalled = true;
            return const Text('authenticated');
          },
        ),
      ),
    );
    await tester.pump();
    expect(authenticatedBuilderCalled, isFalse);
    expect(find.text('Войдите в аккаунт, чтобы открыть локальные данные.'),
        findsOneWidget);
    subject.dispose();
  });

  test('tenant switch keeps personal local scope stable', () async {
    final subject = manager(_FakeClient(), MemoryTokenStorage());
    await subject.login('a@example.com', 'valid-password-1');
    final before = LocalDataScope.personal(subject.session!.user.id);
    await subject.switchTenant('tenant-2');
    final after = LocalDataScope.personal(subject.session!.user.id);
    expect(subject.session!.tokens.tenantId, 'tenant-2');
    expect(after.fingerprint, before.fingerprint);
  });
}
