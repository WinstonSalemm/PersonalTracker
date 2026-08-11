import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:personal_tracker_domain/domain.dart';

class CaptureRollout {
  const CaptureRollout({
    required this.captureCoreV2Shadow,
    required this.captureMoneyV2,
    required this.fetchedAt,
  });

  const CaptureRollout.disabled()
      : captureCoreV2Shadow = false,
        captureMoneyV2 = false,
        fetchedAt = null;

  final bool captureCoreV2Shadow;
  final bool captureMoneyV2;
  final DateTime? fetchedAt;

  factory CaptureRollout.fromJson(Map<String, dynamic> json) {
    final flags = json['flags'];
    final values = flags is Map ? flags : const <String, dynamic>{};
    return CaptureRollout(
      captureCoreV2Shadow: values['captureCoreV2Shadow'] == true,
      captureMoneyV2: values['captureMoneyV2'] == true,
      fetchedAt: DateTime.tryParse(json['fetchedAt']?.toString() ?? ''),
    );
  }
}

class CanonicalCommitException implements Exception {
  const CanonicalCommitException(this.statusCode, this.code);
  final int statusCode;
  final String code;
  bool get retryable =>
      statusCode == 408 || statusCode == 429 || statusCode >= 500;
  @override
  String toString() => 'canonical_commit_failed_$statusCode:$code';
}

class PersonalTrackerApi {
  PersonalTrackerApi({required this.baseUrl, this.accessToken});
  final String baseUrl;
  final String? accessToken;

  Future<CaptureRollout> fetchCaptureRollout() async {
    if (baseUrl.isEmpty) throw StateError('api_not_configured');
    final response = await http.get(
      Uri.parse(
          '${baseUrl.replaceFirst(RegExp(r'/*$'), '')}/api/v2/capture/rollout'),
      headers: {
        if (accessToken?.isNotEmpty == true)
          'authorization': 'Bearer $accessToken',
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CanonicalCommitException(response.statusCode, _errorCode(response));
    }
    return CaptureRollout.fromJson(
      Map<String, dynamic>.from(jsonDecode(response.body) as Map),
    );
  }

  Future<void> reportCaptureRolloutMetric(String event) async {
    if (baseUrl.isEmpty) return;
    final response = await http.post(
      Uri.parse(
          '${baseUrl.replaceFirst(RegExp(r'/*$'), '')}/api/v2/capture/rollout/metrics'),
      headers: {
        'content-type': 'application/json',
        if (accessToken?.isNotEmpty == true)
          'authorization': 'Bearer $accessToken',
      },
      body: jsonEncode({'event': event}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CanonicalCommitException(response.statusCode, _errorCode(response));
    }
  }

  Future<Map<String, dynamic>> commitCanonicalMoney(
      Map<String, dynamic> payload) async {
    if (baseUrl.isEmpty) throw StateError('api_not_configured');
    final response = await http.post(
      Uri.parse(
          '${baseUrl.replaceFirst(RegExp(r'/*$'), '')}/api/v2/capture/commits'),
      headers: {
        'content-type': 'application/json',
        if (accessToken?.isNotEmpty == true)
          'authorization': 'Bearer $accessToken',
      },
      body: jsonEncode(payload),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CanonicalCommitException(response.statusCode, _errorCode(response));
    }
    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }

  Future<int> sync(List<CaptureRecord> records) async {
    if (records.isEmpty) return 0;
    if (baseUrl.isEmpty) throw StateError('api_not_configured');
    final body = <String, dynamic>{
      'transactions': <Map<String, dynamic>>[],
      'leads': <Map<String, dynamic>>[],
      'calls': <Map<String, dynamic>>[],
      'englishProgress': <Map<String, dynamic>>[],
      'workoutSessions': <Map<String, dynamic>>[],
    };
    for (final record in records) {
      final p = record.draft;
      switch (p.type) {
        case CaptureType.expense:
        case CaptureType.income:
          (body['transactions'] as List).add({
            'id': record.id,
            'accountId': 'default-cash',
            'type': p.type.wireName,
            'amount': p.amount,
            'currency': p.currency,
            'date': p.date,
            'categoryId': p.category,
            'paymentMethod': p.paymentMethod,
            'purpose': p.description,
            'status': 'completed',
          });
        case CaptureType.salesCall:
          final leadId = '${record.id}-lead';
          (body['leads'] as List).add({
            'id': leadId,
            'companyName': p.company ?? 'Новая компания',
            'source': 'other',
            'status': 'contacted',
          });
          (body['calls'] as List).add({
            'id': record.id,
            'leadId': leadId,
            'attemptNumber': 1,
            'dateTime': record.createdAt.toUtc().toIso8601String(),
            'result': p.result ?? 'contacted',
            'whatSaid': p.whatSaid,
            'offered': p.offered,
            'nextStep': p.nextStep,
            'nextContactDate': p.followUpDate,
          });
        case CaptureType.english:
          (body['englishProgress'] as List).add({
            'id': record.id,
            'date': p.date,
            'overallProgress': 0,
            'completedDays': 0,
            'activeDay': 0,
            'streak': 0,
            'studyMinutes': p.durationMinutes ?? 0,
            'payload': p.toJson(),
          });
        case CaptureType.sports:
          (body['workoutSessions'] as List).add({
            'id': record.id,
            'date': p.date,
            'workoutType': p.activityType ?? 'general',
            'startedAt': record.createdAt.toUtc().toIso8601String(),
            'durationMinutes': p.durationMinutes,
            'completed': true,
            'notes': p.comment,
          });
      }
    }
    final response = await http.post(
      Uri.parse('${baseUrl.replaceFirst(RegExp(r'/*$'), '')}/api/v1/sync'),
      headers: {
        'content-type': 'application/json',
        if (accessToken?.isNotEmpty == true)
          'authorization': 'Bearer $accessToken',
      },
      body: jsonEncode(body),
    );
    if (response.statusCode < 200 || response.statusCode >= 300)
      throw Exception('sync_failed_${response.statusCode}');
    final result = jsonDecode(response.body) as Map<String, dynamic>;
    return (result['accepted'] as num?)?.toInt() ?? records.length;
  }
}

String _errorCode(http.Response response) {
  String code = 'unknown';
  try {
    code = (jsonDecode(response.body) as Map)['error']?.toString() ?? code;
  } catch (_) {}
  return code;
}
