import 'dart:developer';
import 'package:airotrack/Configs/RetryInterceptor.dart';
import 'package:dio/dio.dart';

import 'ApiConfigs.dart';

class DioClient {
  static final DioClient _instance = DioClient._internal();
  factory DioClient() => _instance;
  Dio dio = Dio();

  DioClient._internal() {
    dio
      ..options.baseUrl = ApiConfig.baseUrl
      ..options.connectTimeout = const Duration(seconds: 20)
      ..options.receiveTimeout = const Duration(seconds: 20)
      ..options.headers = {
        "Accept": "application/json",
        "Content-Type": "application/json",
        "User-Agent": "Airotrack-Mobile/1.0.0 (Android)",
        "X-Requested-With": "XMLHttpRequest",
      };

    dio.interceptors.add(RetryInterceptor(dio: dio));
    dio.interceptors.add(_loggingInterceptor());
  }

  /// Logger Interceptor
  InterceptorsWrapper _loggingInterceptor() {
    return InterceptorsWrapper(
      onRequest: (options, handler) {
        print("\n========== API REQUEST ==========");
        print("➡️ METHOD: ${options.method}");
        print("➡️ URL: ${options.uri}");
        print("➡️ HEADERS: ${options.headers}");
        if (options.data is FormData) {
          final formData = options.data as FormData;
          print("➡️ DATA [FormData]:");
          for (var field in formData.fields) {
            print("${field.key}: ${field.value}");
          }
          for (var file in formData.files) {
            print("   [File] ${file.key}: ${file.value.filename}");
          }
        } else {
          print("➡️ DATA: ${options.data}");
        }
        print("=================================\n");
        return handler.next(options);
      },
      onResponse: (response, handler) {
        print("\n========== API RESPONSE ==========");
        print("⬅️ URL: ${response.requestOptions.uri}");
        print("⬅️ STATUS: ${response.statusCode}");
        print("⬅️ DATA: ${response.data}");
        print("==================================\n");
        return handler.next(response);
      },
      onError: (DioException error, handler) {
        print("\n========== API ERROR ==========");
        print("❌ URL: ${error.requestOptions.uri}");
        print("❌ ERROR: ${error.error ?? error.message}");
        if (error.response != null) {
          print("❌ STATUS: ${error.response?.statusCode}");
          print("❌ DATA: ${error.response?.data}");
        }
        print("===============================\n");
        return handler.next(error);
      },
    );
  }

  Future<Response> get(
    String path, {
    Map<String, dynamic>? query,
    Options? options,
  }) async {
    try {
      return await dio.get(path, queryParameters: query, options: options);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<Response> post(
    String path, {
    dynamic body,
    Map<String, dynamic>? query,
  }) async {
    try {
      return await dio.post(path, data: body, queryParameters: query);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Add token dynamically
  void updateToken(String token) {
    dio.options.headers["Authorization"] = "Bearer $token";
  }

  // GLOBAL ERROR HANDLING
  String _handleError(DioException e) {
    if (e.response != null) {
      final data = e.response!.data;
      final statusCode = e.response!.statusCode;

      log("Global Error Handler: Status=$statusCode, Data=$data");

      if (statusCode == 422 && data is Map) {
        final msg = data['message'];

        if (msg is Map) {
          final keys = msg.keys.toList();
          if (keys.isNotEmpty) {
            final firstKey = keys[0];
            final firstList = msg[firstKey];
            if (firstList is List && firstList.isNotEmpty) {
              return firstList.first.toString();
            }
          }
        }

        if (msg is String) {
          return msg;
        }

        return "Validation failed";
      } else if (statusCode == 500) {
        // Redirection disabled to avoid jumping to the black placeholder screen.
        // Get.to(() => const ServerDown());
        return "Server error occurred. Please try again later.";
      } else {
        if (data is Map && data['message'] != null) {
          final msg = data['message'];
          if (msg is String) return msg;
          if (msg is Map) {
            final keys = msg.keys.toList();
            if (keys.isNotEmpty) {
              final firstKey = keys[0];
              final firstValue = msg[firstKey];
              if (firstValue is List && firstValue.isNotEmpty) {
                return firstValue.first.toString();
              }
              if (firstValue is String) {
                return firstValue;
              }
            }
          }
        }
        return "Error occurred. Code: $statusCode";
      }
    }

    if (e.type == DioExceptionType.connectionError) {
      return "No Internet Connection";
    }

    if (e.type == DioExceptionType.connectionTimeout) {
      return "Connection Timeout. Try again.";
    }

    if (e.type == DioExceptionType.receiveTimeout) {
      return "Receive Timeout. Try again.";
    }

    if (e.type == DioExceptionType.sendTimeout) {
      return "Send Timeout. Try again.";
    }

    // Log the error type and message for debugging
    log("DioException Type: ${e.type}");
    log("DioException Message: ${e.message}");
    if (e.response != null) {
      log("Response Status: ${e.response!.statusCode}");
      log("Response Data: ${e.response!.data}");
    }

    return "Unexpected error occurred: ${e.message ?? e.type.toString()}";
  }
}
