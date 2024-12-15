// In lib/flutter_smb_client.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class FlutterSmbClient {
  static const MethodChannel _channel = MethodChannel('flutter_smb_client');

  // Connection configuration
  static Future<bool> connect({
    required String host,
    required String username,
    required String password,
    String? domain,
    int port = 445,
  }) async {
    try {
      final result = await _channel.invokeMethod('connect', {
        'host': host,
        'username': username,
        'password': password,
        'domain': domain,
        'port': port,
      });
      return result ?? false;
    } catch (e) {
      debugPrint('SMB Connect Error: $e');
      return false;
    }
  }

  // List files in a directory
  static Future<List<Map<String, dynamic>>> listFiles(String path) async {
    try {
      final result = await _channel.invokeMethod('listFiles', {'path': path});
      return List<Map<String, dynamic>>.from(result ?? []);
    } catch (e) {
      debugPrint('SMB List Files Error: $e');
      return [];
    }
  }

  // Download file
  static Future<String?> downloadFile(
      String remotePath, String localPath) async {
    try {
      final result = await _channel.invokeMethod('downloadFile', {
        'remotePath': remotePath,
        'localPath': localPath,
      });
      return result;
    } catch (e) {
      debugPrint('SMB Download Error: $e');
      return null;
    }
  }

  // Upload file
  static Future<bool> uploadFile(String localPath, String remotePath) async {
    try {
      final result = await _channel.invokeMethod('uploadFile', {
        'localPath': localPath,
        'remotePath': remotePath,
      });
      return result ?? false;
    } catch (e) {
      debugPrint('SMB Upload Error: $e');
      return false;
    }
  }

  // Disconnect
  static Future<bool> disconnect() async {
    try {
      final result = await _channel.invokeMethod('disconnect');
      return result ?? false;
    } catch (e) {
      debugPrint('SMB Disconnect Error: $e');
      return false;
    }
  }
}
