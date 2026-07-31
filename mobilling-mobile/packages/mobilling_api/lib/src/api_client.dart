import 'package:dio/dio.dart';

import 'api_exception.dart';

/// Supplies the current Sanctum bearer token, or null when signed out.
typedef TokenReader = Future<String?> Function();

/// Called when the server rejects our token (401). Implementations decide what
/// that means for the session — see `SessionExpiryPolicy` in `mobilling_auth`.
typedef UnauthenticatedHandler = Future<void> Function(RequestOptions request);

/// The single HTTP entry point for every MoBilling API call.
///
/// Responsibilities kept here on purpose:
///   * attach the bearer token,
///   * normalise failures into [ApiException],
///   * surface 401s to the session layer.
///
/// Endpoint knowledge lives in the per-area services, not here.
class ApiClient {
  ApiClient({
    required String baseUrl,
    required TokenReader tokenReader,
    UnauthenticatedHandler? onUnauthenticated,
    Duration connectTimeout = const Duration(seconds: 15),
    Duration receiveTimeout = const Duration(seconds: 30),
    List<Interceptor> extraInterceptors = const [],
    Dio? dio,
  })  : _tokenReader = tokenReader,
        _onUnauthenticated = onUnauthenticated,
        _dio = dio ?? Dio() {
    _dio.options = _dio.options.copyWith(
      baseUrl: baseUrl,
      connectTimeout: connectTimeout,
      receiveTimeout: receiveTimeout,
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      // Laravel returns JSON error bodies we want to read, so let non-2xx
      // responses through to the interceptor instead of throwing early.
      validateStatus: (status) => status != null && status < 500,
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: _attachToken,
        onResponse: _rejectErrorStatuses,
        onError: _normaliseError,
      ),
    );
    _dio.interceptors.addAll(extraInterceptors);
  }

  final Dio _dio;
  final TokenReader _tokenReader;
  final UnauthenticatedHandler? _onUnauthenticated;

  /// Escape hatch for callers needing raw Dio (multipart uploads, downloads
  /// with progress). Prefer the typed helpers below.
  Dio get raw => _dio;

  Future<void> _attachToken(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // An explicit Authorization header wins — the OTP and login calls are
    // deliberately unauthenticated, and impersonation passes its own token.
    if (!options.headers.containsKey('Authorization')) {
      final token = await _tokenReader();
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    }
    handler.next(options);
  }

  /// `validateStatus` above lets 4xx through so we can read the body; convert
  /// those into errors here so callers only ever see success in `onResponse`.
  void _rejectErrorStatuses(
    Response response,
    ResponseInterceptorHandler handler,
  ) {
    final status = response.statusCode ?? 0;
    if (status >= 200 && status < 300) {
      handler.next(response);
      return;
    }
    handler.reject(
      DioException.badResponse(
        statusCode: status,
        requestOptions: response.requestOptions,
        response: response,
      ),
      true,
    );
  }

  Future<void> _normaliseError(
    DioException e,
    ErrorInterceptorHandler handler,
  ) async {
    final failure = ApiException.fromDio(e);

    if (failure.kind == ApiErrorKind.unauthenticated) {
      await _onUnauthenticated?.call(e.requestOptions);
    }

    handler.reject(
      DioException(
        requestOptions: e.requestOptions,
        response: e.response,
        type: e.type,
        error: failure,
      ),
    );
  }

  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? query,
    CancelToken? cancelToken,
  }) =>
      _send<T>(() => _dio.get<T>(path,
          queryParameters: _clean(query), cancelToken: cancelToken));

  Future<T> post<T>(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    CancelToken? cancelToken,
  }) =>
      _send<T>(() => _dio.post<T>(path,
          data: body,
          queryParameters: _clean(query),
          cancelToken: cancelToken));

  Future<T> put<T>(
    String path, {
    Object? body,
    CancelToken? cancelToken,
  }) =>
      _send<T>(() => _dio.put<T>(path, data: body, cancelToken: cancelToken));

  Future<T> patch<T>(
    String path, {
    Object? body,
    CancelToken? cancelToken,
  }) =>
      _send<T>(() => _dio.patch<T>(path, data: body, cancelToken: cancelToken));

  Future<T> delete<T>(
    String path, {
    Object? body,
    CancelToken? cancelToken,
  }) =>
      _send<T>(
          () => _dio.delete<T>(path, data: body, cancelToken: cancelToken));

  /// Unwrap the Dio response and re-throw failures as [ApiException], so no
  /// caller anywhere needs to import Dio to handle an error.
  Future<T> _send<T>(Future<Response<T>> Function() request) async {
    try {
      final response = await request();
      return response.data as T;
    } on DioException catch (e) {
      final error = e.error;
      throw error is ApiException ? error : ApiException.fromDio(e);
    }
  }

  /// Drop null query values — Dio would otherwise serialise them as empty
  /// strings, and Laravel's `filled()` checks treat those as present.
  Map<String, dynamic>? _clean(Map<String, dynamic>? query) {
    if (query == null) return null;
    final cleaned = <String, dynamic>{};
    query.forEach((key, value) {
      if (value != null) cleaned[key] = value;
    });
    return cleaned.isEmpty ? null : cleaned;
  }
}
