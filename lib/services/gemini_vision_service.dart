import 'device_check_service.dart';
import 'dart:async';
import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../core/json/json_map.dart';
import '../core/security/app_secrets.dart';
import '../models/satiety_matrix.dart';
import 'supabase_service.dart';

/// Authoritative scan entitlement as reported by the backend.
class ScanQuota {
  final bool isPro;
  final int freeScansRemaining;
  final int photoPurchased;
  final int textRemaining;
  final int textPurchased;

  const ScanQuota({
    required this.isPro,
    required this.freeScansRemaining,
    this.photoPurchased = 0,
    this.textRemaining = 0,
    this.textPurchased = 0,
  });

  int get photoLeft => freeScansRemaining + photoPurchased;
  int get textLeft => textRemaining + textPurchased;

  static ScanQuota? tryParse(Object? raw) {
    final map = asStringKeyedMap(raw);
    if (map == null) return null;
    final remaining = map['freeScansRemaining'];
    final photoPurchased = map['photoPurchased'];
    final textRemaining = map['textRemaining'];
    final textPurchased = map['textPurchased'];
    return ScanQuota(
      isPro: map['isPro'] == true,
      freeScansRemaining: remaining is num ? remaining.toInt() : 0,
      photoPurchased: photoPurchased is num ? photoPurchased.toInt() : 0,
      textRemaining: textRemaining is num ? textRemaining.toInt() : 0,
      textPurchased: textPurchased is num ? textPurchased.toInt() : 0,
    );
  }
}

/// A completed analysis plus the entitlement state the server applied for it.
class PlateAnalysis {
  final SatietyResult result;
  final ScanQuota? quota;
  final List<String> rejected;
  final String? diaryId;

  const PlateAnalysis({
    required this.result,
    this.quota,
    this.rejected = const [],
    this.diaryId,
  });
}

/// Raised when the backend refuses the scan because the free quota is spent.
class ScanQuotaExceededException implements Exception {
  final ScanQuota? quota;

  const ScanQuotaExceededException([this.quota]);

  @override
  String toString() => 'Scan quota exceeded';
}

/// Raised when the backend rejects or fails the analysis request.
enum PlateAnalysisFailureKind { timeout, network, http, unreadable }

class PlateAnalysisException implements Exception {
  final String message;
  final PlateAnalysisFailureKind kind;
  final int? statusCode;
  final String? code;
  final ScanQuota? quota;

  const PlateAnalysisException(
    this.message, {
    this.kind = PlateAnalysisFailureKind.http,
    this.statusCode,
    this.code,
    this.quota,
  });

  String get telemetryName {
    switch (code) {
      case 'GEMINI_BUSY':
        return 'scan.busy';
      case 'GEMINI_UNPAID':
        return 'scan.busy';
      case 'GEMINI_TIMEOUT':
        return 'scan.timeout';
      case 'GEMINI_EMPTY':
        return 'scan.empty';
      case 'GEMINI_UNKNOWN':
        return 'scan.unknown';
      case 'GEMINI_MALFORMED':
        return 'scan.unreadable';
      case 'GEMINI_TRANSIENT':
      case 'SERVICE_UNCONFIGURED':
      case 'INTERNAL':
      case 'QUOTA_CHECK_FAILED':
      case 'MEAL_INSERT_FAILED':
        return 'scan.http_5xx';
      case 'GEMINI_INVALID_IMAGE':
        return 'scan.unreadable';
      case 'GEMINI_BLOCKED':
        return 'scan.not_food';
      case 'FOODS_RATE_LIMITED':
        return 'scan.busy';
      case 'FOODS_QUOTA_EXCEEDED':
        return 'scan.quota';
      case 'AUTH':
        return 'scan.unauthorized';
      case 'IMAGE_TOO_LARGE':
      case 'UNSUPPORTED_TYPE':
      case 'BAD_REQUEST':
        return 'scan.http_4xx';
    }
    switch (kind) {
      case PlateAnalysisFailureKind.timeout:
        return 'scan.timeout';
      case PlateAnalysisFailureKind.network:
        return 'scan.network';
      case PlateAnalysisFailureKind.unreadable:
        return 'scan.unreadable';
      case PlateAnalysisFailureKind.http:
        if ((statusCode ?? 0) >= 500) return 'scan.http_5xx';
        return 'scan.http_4xx';
    }
  }

  /// Same failure, typed-foods feature name so Sentry does not mix with scans.
  String telemetryNameFor(String feature) {
    final name = telemetryName;
    const prefix = 'scan.';
    if (name.startsWith(prefix)) {
      return '$feature.${name.substring(prefix.length)}';
    }
    return '$feature.$name';
  }

  bool get alert {
    if (code == 'FOODS_RATE_LIMITED') return false;
    switch (telemetryName) {
      case 'scan.not_food':
      case 'scan.http_4xx':
      case 'scan.quota':
        return false;
      case 'scan.unreadable':
        return code != 'GEMINI_INVALID_IMAGE';
      default:
        return true;
    }
  }

  @override
  String toString() => message;
}

String sniffImageMimeType(Uint8List bytes, [String fallback = 'image/jpeg']) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF) {
    return 'image/jpeg';
  }
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return 'image/png';
  }
  if (bytes.length >= 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return 'image/webp';
  }
  return fallback;
}

/// Gemini Vision AI Service for Satiety Matrix & Plate Evaluation.
/// All analysis runs through the authenticated backend so the vision key and
/// the scan quota stay server side.
class GeminiVisionService {
  // Must stay above the backend's own 45s vision timeout. If the client gave up
  // first, a slow scan would still be charged and stored server side while the
  // user saw only a timeout, losing both the credit and the analysis.
  static const Duration requestTimeout = Duration(seconds: 60);
  // Allow the bounded server request to finish before the client times out.
  static const Duration foodsTimeout = Duration(seconds: 55);

  final SupabaseService? _supabaseService;
  final http.Client _httpClient;

  GeminiVisionService([this._supabaseService, http.Client? httpClient])
    : _httpClient = httpClient ?? http.Client();

  static const devUnlimitedHeader = 'x-evenplate-dev-unlimited';

  String _functionUrl(String name) {
    return AppSecrets.backendEndpointUrl.isNotEmpty
        ? '${AppSecrets.backendEndpointUrl}/$name'
        : '${AppSecrets.supabaseUrl}/functions/v1/$name';
  }

  Map<String, String> _headers({bool devUnlimited = false}) {
    final token = _supabaseService?.currentAccessToken;
    return {
      'Content-Type': 'application/json',
      'apikey': AppSecrets.supabaseAnonKey,
      if (token != null) 'Authorization': 'Bearer $token',
      if (kDebugMode && devUnlimited) devUnlimitedHeader: '1',
    };
  }

  List<String> _rejectedFrom(Map<String, dynamic>? decoded) {
    final raw = decoded?['rejected'];
    if (raw is! List) return const [];
    return raw
        .map((entry) => entry.toString().trim())
        .where((entry) => entry.isNotEmpty)
        .toList();
  }

  Future<http.Response> _postJson(
    String functionName,
    Map<String, dynamic> body, {
    required Duration timeout,
    bool devUnlimited = false,
  }) async {
    if (_supabaseService != null && !_supabaseService.hasAnalysisConsent) {
      throw const PlateAnalysisException(
        'Allow meal analysis in Settings to use remote scoring.',
        code: 'CONSENT_REQUIRED',
      );
    }
    body['analysisConsent'] = true;
    final owner = _supabaseService?.telemetryUserId;
    body['dietaryPreference'] =
        _supabaseService?.dietaryPreference ?? 'Omnivore / Balanced';
    try {
      await _supabaseService?.ensureDeviceAccess(
        functionName == 'analyze-plate' ? 'photo' : 'text',
      );
      if (owner != _supabaseService?.telemetryUserId) {
        throw const PlateAnalysisException(
          'Account changed. Please try again.',
          code: 'ACCOUNT_CHANGED',
        );
      }
      final response = await _httpClient
          .post(
            Uri.parse(_functionUrl(functionName)),
            headers: _headers(devUnlimited: devUnlimited),
            body: jsonEncode(body),
          )
          .timeout(timeout);
      if (owner != _supabaseService?.telemetryUserId) {
        throw const PlateAnalysisException(
          'Account changed. Please try again.',
          code: 'ACCOUNT_CHANGED',
        );
      }
      return response;
    } on DeviceCheckUnavailable catch (error) {
      final message = switch (error.code) {
        'DEVICE_LIMIT' =>
          'This iPhone has already qualified two free accounts. Paid access is still available. Contact evenplatesupport@gmail.com if you need help.',
        'DEVICE_SUPPORT' =>
          'Contact evenplatesupport@gmail.com to recover free access.',
        'unsupported' =>
          'Free access needs verification on a supported iPhone. Paid access is still available.',
        'account_changed' => 'Account changed. Please try again.',
        _ =>
          'Device verification is temporarily unavailable. Please retry. No assessment credit was used.',
      };
      throw PlateAnalysisException(message, code: error.code);
    } on TimeoutException {
      throw const PlateAnalysisException(
        'Analysis timed out. Please try again.',
        kind: PlateAnalysisFailureKind.timeout,
      );
    } on PlateAnalysisException {
      rethrow;
    } catch (e) {
      debugPrint('Error invoking $functionName: $e');
      throw const PlateAnalysisException(
        'Analysis request failed. Please check your network and try again.',
        kind: PlateAnalysisFailureKind.network,
      );
    }
  }

  PlateAnalysis _analysisFromOk(Map<String, dynamic>? decoded) {
    if (decoded == null) {
      throw const PlateAnalysisException(
        'Analysis returned an unreadable response.',
        kind: PlateAnalysisFailureKind.unreadable,
      );
    }
    final diaryId = decoded['diaryId']?.toString();
    final parsed = SatietyResult.fromJson(decoded).rebalanced();
    return PlateAnalysis(
      result: parsed.copyWith(
        hybridUpgrade: parsed.hybridUpgrade.forDietaryPreference(
          _supabaseService?.dietaryPreference ?? 'Omnivore / Balanced',
        ),
      ),
      quota: ScanQuota.tryParse(decoded['quota']),
      rejected: _rejectedFrom(decoded),
      diaryId: diaryId != null && diaryId.isNotEmpty ? diaryId : null,
    );
  }

  Never _throwFromError(
    http.Response response,
    Map<String, dynamic>? decoded,
    String functionName,
  ) {
    if (response.statusCode == 403 && decoded?['code'] == 'DEVICE_REQUIRED') {
      _supabaseService?.invalidateDeviceAccess();
    }
    if (response.statusCode == 403 &&
        (decoded?['code'] == 'QUOTA_EXCEEDED' ||
            decoded?['code'] == 'FOODS_QUOTA_EXCEEDED')) {
      throw ScanQuotaExceededException(ScanQuota.tryParse(decoded?['quota']));
    }

    debugPrint(
      '$functionName returned status ${response.statusCode}: ${response.body}',
    );

    final serverMessage = decoded?['error'];
    final serverCode = decoded?['code'];
    throw PlateAnalysisException(
      serverMessage is String
          ? serverMessage
          : 'Analysis failed (status ${response.statusCode}).',
      kind: PlateAnalysisFailureKind.http,
      statusCode: response.statusCode,
      code: serverCode is String ? serverCode : null,
      quota: ScanQuota.tryParse(decoded?['quota']),
    );
  }

  /// Analyzes a meal photo and outputs a structured SatietyResult.
  Future<PlateAnalysis> analyzePlate({
    required Uint8List imageBytes,
    String mimeType = 'image/jpeg',
    bool devUnlimited = false,
    String? requestId,
  }) async {
    final response = await _postJson(
      'analyze-plate',
      {
        'requestId': requestId ?? const Uuid().v4(),
        'imageBase64': base64Encode(imageBytes),
        'mimeType': sniffImageMimeType(imageBytes, mimeType),
      },
      timeout: requestTimeout,
      devUnlimited: devUnlimited,
    );

    Map<String, dynamic>? decoded;
    try {
      decoded = asStringKeyedMap(jsonDecode(response.body));
    } catch (_) {
      decoded = null;
    }

    if (response.statusCode == 200) {
      return _analysisFromOk(decoded);
    }

    _throwFromError(response, decoded, 'analyze-plate');
  }

  /// Scores typed foods. Does not consume a photo-scan credit.
  Future<PlateAnalysis> analyzeFoods({
    required List<String> foods,
    String mealName = 'Plate',
    String? requestId,
    SatietyResult? original,
  }) async {
    final response = await _postJson('analyze-foods', {
      'requestId': requestId ?? const Uuid().v4(),
      'mealName': mealName,
      'foods': foods,
      if (original != null) 'originalAnalysis': original.assessmentContext,
    }, timeout: foodsTimeout);

    Map<String, dynamic>? decoded;
    try {
      decoded = asStringKeyedMap(jsonDecode(response.body));
    } catch (_) {
      decoded = null;
    }

    if (response.statusCode == 200) {
      return _analysisFromOk(decoded);
    }

    _throwFromError(response, decoded, 'analyze-foods');
  }

  /// Parses raw vision model output into a validated SatietyResult model
  static SatietyResult parseVisionResponse(String rawText) {
    String clean = rawText.trim();
    if (clean.startsWith('```json')) {
      clean = clean.substring(7);
    } else if (clean.startsWith('```')) {
      clean = clean.substring(3);
    }
    if (clean.endsWith('```')) {
      clean = clean.substring(0, clean.length - 3);
    }
    clean = clean.trim();

    // Extract first JSON object if surrounded by commentary
    final start = clean.indexOf('{');
    final end = clean.lastIndexOf('}');
    if (start != -1 && end != -1 && end >= start) {
      clean = clean.substring(start, end + 1);
    }

    try {
      final decoded = jsonDecode(clean);
      final map = asStringKeyedMap(decoded);
      if (map == null) {
        throw const FormatException('Vision response was not a JSON object.');
      }
      return SatietyResult.fromJson(map).rebalanced();
    } on FormatException {
      rethrow;
    } catch (error) {
      throw FormatException('Vision response was not valid JSON.', error);
    }
  }
}
