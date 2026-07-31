import 'package:dio/dio.dart';

/// Why a request failed, in terms the UI can actually branch on.
///
/// Dio reports transport-level detail; screens care about intent. Mapping once
/// here keeps `catch (e) { if (e.response?.statusCode == 422) ... }` out of
/// every widget.
enum ApiErrorKind {
  /// No usable connection — airplane mode, no signal, DNS failure.
  network,

  /// The request reached the server but took too long.
  timeout,

  /// 401 — the token is missing, expired or revoked.
  unauthenticated,

  /// 403 — authenticated, but not allowed. For portal routes this usually
  /// means a staff token hit a client route (or the account was deactivated).
  forbidden,

  /// 404 — the record is gone or was never visible to this client.
  notFound,

  /// 422 — Laravel validation failure; see [fieldErrors].
  validation,

  /// 402 — the tenant's own subscription has lapsed. Only reachable from the
  /// staff app; the client portal is not gated on it.
  subscriptionExpired,

  /// 429 — rate limited. The OTP endpoints throttle deliberately.
  rateLimited,

  /// 449 — not an error. The backend uses this non-standard status to signal
  /// "this identifier belongs to a client with no portal account yet; we have
  /// emailed them a code, now collect it". See `LoginController::sendPortalOtp`.
  /// Callers should route to the OTP screen rather than showing a failure.
  otpRequired,

  /// 5xx.
  server,

  /// Anything we did not anticipate, including JSON that failed to parse.
  unknown,
}

/// A failed API call, normalised away from Dio's transport vocabulary.
class ApiException implements Exception {
  ApiException({
    required this.kind,
    required this.message,
    this.statusCode,
    this.fieldErrors = const {},
    this.body,
    this.cause,
  });

  final ApiErrorKind kind;

  /// Safe to show to a user. Prefers the server's own `message` when there is
  /// one, because Laravel's messages are already human-readable and localised
  /// to the tenant's context.
  final String message;

  final int? statusCode;

  /// Laravel's `errors` bag: field name -> list of messages. Empty unless
  /// [kind] is [ApiErrorKind.validation].
  final Map<String, List<String>> fieldErrors;

  /// The decoded response body, when there was one. Needed for statuses that
  /// carry usable payload rather than just a message — notably the 449
  /// OTP handshake, which returns `client_name`.
  final dynamic body;

  final Object? cause;

  /// The first validation message for [field], if any — the common case when
  /// binding a 422 back onto a form.
  String? errorFor(String field) => fieldErrors[field]?.firstOrNull;

  /// True when retrying the identical request could plausibly succeed.
  bool get isRetryable =>
      kind == ApiErrorKind.network ||
      kind == ApiErrorKind.timeout ||
      kind == ApiErrorKind.server;

  /// Translate a [DioException] into the domain vocabulary above.
  factory ApiException.fromDio(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return ApiException(
          kind: ApiErrorKind.timeout,
          message: 'The server took too long to respond. Please try again.',
          cause: e,
        );
      case DioExceptionType.connectionError:
        return ApiException(
          kind: ApiErrorKind.network,
          message: 'No internet connection.',
          cause: e,
        );
      case DioExceptionType.cancel:
        return ApiException(
          kind: ApiErrorKind.unknown,
          message: 'Request cancelled.',
          cause: e,
        );
      case DioExceptionType.badCertificate:
        return ApiException(
          kind: ApiErrorKind.network,
          message: 'Could not establish a secure connection.',
          cause: e,
        );
      case DioExceptionType.badResponse:
      case DioExceptionType.unknown:
        break;
    }

    final response = e.response;
    if (response == null) {
      return ApiException(
        kind: ApiErrorKind.network,
        message: 'Could not reach the server.',
        cause: e,
      );
    }

    final body = response.data;
    final serverMessage = body is Map && body['message'] is String
        ? body['message'] as String
        : null;
    final status = response.statusCode;

    ApiException build(ApiErrorKind kind, String fallback) => ApiException(
          kind: kind,
          message: serverMessage ?? fallback,
          statusCode: status,
          fieldErrors: _parseFieldErrors(body),
          body: body,
          cause: e,
        );

    return switch (status) {
      401 => build(ApiErrorKind.unauthenticated, 'Your session has expired.'),
      402 => build(ApiErrorKind.subscriptionExpired,
          'This subscription is no longer active.'),
      403 => build(ApiErrorKind.forbidden, 'You do not have access to this.'),
      404 => build(ApiErrorKind.notFound, 'Not found.'),
      422 => build(ApiErrorKind.validation, 'Please check the details below.'),
      429 => build(ApiErrorKind.rateLimited,
          'Too many attempts. Please wait and try again.'),
      449 => build(ApiErrorKind.otpRequired, 'Verification required.'),
      _ when status != null && status >= 500 =>
        build(ApiErrorKind.server, 'Something went wrong on our end.'),
      _ => build(ApiErrorKind.unknown, 'Something went wrong.'),
    };
  }

  /// Laravel returns `{"errors": {"email": ["msg", ...]}}` on a 422.
  static Map<String, List<String>> _parseFieldErrors(dynamic body) {
    if (body is! Map) return const {};
    final errors = body['errors'];
    if (errors is! Map) return const {};

    return errors.map(
      (key, value) => MapEntry(
        key.toString(),
        value is List
            ? value.map((m) => m.toString()).toList()
            : <String>[value.toString()],
      ),
    );
  }

  @override
  String toString() => 'ApiException($kind, $statusCode): $message';
}

extension _FirstOrNull<E> on List<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
