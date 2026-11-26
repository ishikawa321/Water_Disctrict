import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:water_district_connect/billing_records.dart';
import 'package:water_district_connect/main.dart' show billPayments;

void main() {
  test('new future-dated bills appear immediately, use the linked account and include every payment page', () async {
    final requests = <http.Request>[];
    var added = false;
    final tokenPart = base64Url
        .encode(
          utf8.encode(
            jsonEncode({
              'sub': 'client-id',
              'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
            }),
          ),
        )
        .replaceAll('=', '');
    final client = SupabaseClient(
      'https://fixture.test',
      'public-test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        Object result = [];
        if (request.url.path.endsWith('/token')) {
          result = {
            'access_token': 'eyJhbGciOiJIUzI1NiJ9.$tokenPart.test',
            'refresh_token': 'test-refresh',
            'expires_in': 3600,
            'token_type': 'bearer',
            'user': {
              'id': 'client-id',
              'aud': 'authenticated',
              'role': 'authenticated',
              'email': 'client@example.test',
              'created_at': '2026-01-01T00:00:00Z',
              'app_metadata': {},
              'user_metadata': {},
            },
          };
        } else if (request.url.path.endsWith('/account_access')) {
          result = [
            {'account_id': 'linked-account'},
          ];
        } else if (request.url.path.endsWith('/bills')) {
          expect(
            request.url.queryParameters['account_id'],
            'eq.linked-account',
          );
          expect(request.url.queryParameters['due_date'], isNull);
          result = [
            {
              'id': 'old',
              'bill_number': 'OLDER',
              'due_date': '2026-01-01',
              'amount_due': '100.00',
            },
            if (added)
              {
                'id': 'new',
                'bill_number': 'WEB-ISSUED',
                'due_date': '2099-12-31',
                'amount_due': '700.00',
              },
          ];
        } else if (request.url.path.endsWith('/offline_payments') && added) {
          final offset = int.parse(
            request.url.queryParameters['offset'] ?? '0',
          );
          result = [
            for (var i = offset; i < offset + 500 && i < 501; i++)
              {'id': 'payment-$i', 'bill_id': 'new', 'amount_paid': '0.10'},
          ];
        }
        return http.Response(
          jsonEncode(result),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    await client.auth.signInWithPassword(
      email: 'client@example.test',
      password: 'test-password',
    );
    expect((await loadIssuedBills(client, admin: false)).length, 1);
    added = true;
    final updated = await loadIssuedBills(client, admin: false);
    expect(updated.map((r) => r['bill_number']), contains('WEB-ISSUED'));
    expect(billPayments(updated.last), 5010);
    expect(
      requests
          .where((r) => r.url.path.endsWith('/rpc/wd_billing_refresh'))
          .length,
      2,
    );
    expect(
      requests.any(
        (r) =>
            r.url.path.endsWith('/offline_payments') &&
            r.url.queryParameters['offset'] == '500',
      ),
      isTrue,
    );
    await client.dispose();
  });
}
