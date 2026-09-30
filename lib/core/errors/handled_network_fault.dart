import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// Only callers that already recover from transport failures qualify.
bool isHandledNetworkFault(String feature, Object? error) {
  const recoverableFeatures = {
    'sync.failed',
    'sync.pull_failed',
    'billing.reconcile_failed',
    'offerings.failed',
  };
  if (!recoverableFeatures.contains(feature)) return false;
  return _isTransportFailure(error);
}

bool _isTransportFailure(Object? error) {
  if (error is SocketException) return true;
  if (error is PlatformException) {
    final details = error.details;
    return details is Map &&
        details['readable_error_code'] == 'OFFLINE_CONNECTION_ERROR';
  }
  if (error is FunctionException) {
    return error.status == 0 &&
        (_isTransportFailure(error.details) ||
            _isTransportMessage(error.details.toString()));
  }
  final String message;
  if (error is http.ClientException) {
    message = error.message;
  } else if (error is String) {
    message = error;
  } else {
    return false;
  }
  return _isTransportMessage(message);
}

bool _isTransportMessage(String message) {
  return message.contains('SocketException') ||
      message.contains('Failed host lookup');
}
