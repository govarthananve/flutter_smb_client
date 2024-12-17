import 'package:flutter/services.dart';

/// Custom exception for SMB-related errors
class SMBException implements Exception {
  final String code;
  final String message;
  final dynamic details;

  SMBException(this.code, this.message, [this.details]);

  @override
  String toString() =>
      'SMBException($code): $message${details != null ? '\nDetails: $details' : ''}';
}

class FlutterSmbClient {
  static const MethodChannel _channel = MethodChannel('flutter_smb_client');

  /// Connect to SMB server
  static Future<bool> connect({
    required String host,
    required String username,
    required String password,
    String domain = '',
    int? port,
  }) async {
    try {
      print('Connecting to SMB server: $host');
      final Map<String, dynamic> args = {
        'host': host,
        'username': username,
        'password': password,
        'domain': domain,
      };

      // Only include port if specifically provided
      if (port != null) {
        args['port'] = port;
      }

      final result = await _channel.invokeMethod('connect', args);
      print('Connection result: $result');
      return result ?? false;
    } on PlatformException catch (e) {
      print('Platform error connecting to SMB: ${e.code} - ${e.message}');
      throw SMBException(
        e.code,
        e.message ?? 'Unknown error occurred while connecting',
        e.details,
      );
    } catch (e) {
      print('Error connecting to SMB: $e');
      throw SMBException('CONNECT_ERROR', e.toString());
    }
  }

  /// List available drives/shares
  static Future<List<Map<String, dynamic>>> listDrives() async {
    try {
      print('Requesting SMB drives list');
      final result = await _channel.invokeMethod('listDrives');

      if (result == null) {
        print('No drives found (null response)');
        return [];
      }

      final List<Map<String, dynamic>> drives = (result as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();

      print(
          'Found ${drives.length} drives: ${drives.map((d) => d['name']).toList()}');
      return drives;
    } on PlatformException catch (e) {
      print('Platform error listing drives: ${e.code} - ${e.message}');
      throw SMBException(
        e.code,
        e.message ?? 'Unknown error occurred while listing drives',
        e.details,
      );
    } catch (e) {
      print('Error listing drives: $e');
      throw SMBException('LIST_DRIVES_ERROR', e.toString());
    }
  }

  /// List files in a directory
  static Future<List<Map<String, dynamic>>> listFiles(String path) async {
    try {
      print('Listing files for path: $path');
      final result = await _channel.invokeMethod('listFiles', {
        'path': path,
      });

      if (result == null) {
        print('No files found (null response)');
        return [];
      }

      final List<Map<String, dynamic>> files = (result as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();

      print('Found ${files.length} files in $path');
      return files;
    } on PlatformException catch (e) {
      print('Platform error listing files: ${e.code} - ${e.message}');
      throw SMBException(
        e.code,
        e.message ?? 'Unknown error occurred while listing files',
        e.details,
      );
    } catch (e) {
      print('Error listing files: $e');
      throw SMBException('LIST_FILES_ERROR', e.toString());
    }
  }

  /// Download a file from SMB server
  static Future<String?> downloadFile({
    required String remotePath,
    required String localPath,
  }) async {
    try {
      print('Downloading file from $remotePath to $localPath');
      final result = await _channel.invokeMethod('downloadFile', {
        'remotePath': remotePath,
        'localPath': localPath,
      });
      print('Download completed: $result');
      return result?.toString();
    } on PlatformException catch (e) {
      print('Platform error downloading file: ${e.code} - ${e.message}');
      throw SMBException(
        e.code,
        e.message ?? 'Unknown error occurred while downloading file',
        e.details,
      );
    } catch (e) {
      print('Error downloading file: $e');
      throw SMBException('DOWNLOAD_ERROR', e.toString());
    }
  }

  /// Upload a file to SMB server
  static Future<bool> uploadFile({
    required String localPath,
    required String remotePath,
  }) async {
    try {
      print('Uploading file from $localPath to $remotePath');
      final result = await _channel.invokeMethod('uploadFile', {
        'localPath': localPath,
        'remotePath': remotePath,
      });
      print('Upload completed: $result');
      return result ?? false;
    } on PlatformException catch (e) {
      print('Platform error uploading file: ${e.code} - ${e.message}');
      throw SMBException(
        e.code,
        e.message ?? 'Unknown error occurred while uploading file',
        e.details,
      );
    } catch (e) {
      print('Error uploading file: $e');
      throw SMBException('UPLOAD_ERROR', e.toString());
    }
  }

  /// Disconnect from SMB server
  static Future<bool> disconnect() async {
    try {
      print('Disconnecting from SMB server');
      final result = await _channel.invokeMethod('disconnect');
      print('Disconnect result: $result');
      return result ?? false;
    } on PlatformException catch (e) {
      print('Platform error disconnecting: ${e.code} - ${e.message}');
      throw SMBException(
        e.code,
        e.message ?? 'Unknown error occurred while disconnecting',
        e.details,
      );
    } catch (e) {
      print('Error disconnecting: $e');
      throw SMBException('DISCONNECT_ERROR', e.toString());
    }
  }
}
