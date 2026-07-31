import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobilling_api/mobilling_api.dart';

DioException _responseError(int status, dynamic body) {
  final request = RequestOptions(path: '/auth/login');
  return DioException.badResponse(
    statusCode: status,
    requestOptions: request,
    response: Response(
      requestOptions: request,
      statusCode: status,
      data: body,
    ),
  );
}

void main() {
  group('ApiException.fromDio status mapping', () {
    test('449 is the OTP handshake, and keeps its payload', () {
      // LoginController::sendPortalOtp returns this non-standard status to mean
      // "known client, no portal account yet — we emailed a code".
      final e = ApiException.fromDio(_responseError(449, {
        'requires_otp': true,
        'message': 'Verification code sent to your email.',
        'client_name': 'Acme Ltd',
      }));

      expect(e.kind, ApiErrorKind.otpRequired);
      expect(e.message, 'Verification code sent to your email.');
      expect((e.body as Map)['client_name'], 'Acme Ltd');
    });

    test('422 exposes Laravel field errors', () {
      final e = ApiException.fromDio(_responseError(422, {
        'message': 'The given data was invalid.',
        'errors': {
          'identifier': ['The provided credentials are incorrect.'],
          'password': ['Too short.', 'Too simple.'],
        },
      }));

      expect(e.kind, ApiErrorKind.validation);
      expect(e.errorFor('identifier'),
          'The provided credentials are incorrect.');
      expect(e.fieldErrors['password'], hasLength(2));
      expect(e.errorFor('missing_field'), isNull);
      expect(e.isRetryable, isFalse);
    });

    test('401 maps to unauthenticated', () {
      final e = ApiException.fromDio(_responseError(401, {
        'message': 'Unauthenticated.',
      }));
      expect(e.kind, ApiErrorKind.unauthenticated);
    });

    test('403 carries the portal middleware message verbatim', () {
      final e = ApiException.fromDio(_responseError(403, {
        'message': 'Unauthorized. Client portal access required.',
      }));
      expect(e.kind, ApiErrorKind.forbidden);
      expect(e.message, 'Unauthorized. Client portal access required.');
    });

    test('402 is the tenant subscription gate', () {
      final e = ApiException.fromDio(_responseError(402, null));
      expect(e.kind, ApiErrorKind.subscriptionExpired);
    });

    test('5xx is retryable and never leaks the server message', () {
      final e = ApiException.fromDio(_responseError(500, null));
      expect(e.kind, ApiErrorKind.server);
      expect(e.message, 'Something went wrong on our end.');
      expect(e.isRetryable, isTrue);
    });
  });

  group('ApiException.fromDio transport mapping', () {
    test('connection failure is a retryable network error', () {
      final e = ApiException.fromDio(DioException(
        requestOptions: RequestOptions(path: '/portal/dashboard'),
        type: DioExceptionType.connectionError,
      ));

      expect(e.kind, ApiErrorKind.network);
      expect(e.isRetryable, isTrue);
    });

    test('timeout is distinguished from an outright network failure', () {
      final e = ApiException.fromDio(DioException(
        requestOptions: RequestOptions(path: '/portal/dashboard'),
        type: DioExceptionType.receiveTimeout,
      ));

      expect(e.kind, ApiErrorKind.timeout);
      expect(e.isRetryable, isTrue);
    });

    test('a non-JSON error body does not crash the parser', () {
      final e = ApiException.fromDio(_responseError(500, '<html>502</html>'));
      expect(e.kind, ApiErrorKind.server);
      expect(e.fieldErrors, isEmpty);
    });
  });
}
