import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'flutter_smb_client_platform_interface.dart';

/// An implementation of [FlutterSmbClientPlatform] that uses method channels.
class MethodChannelFlutterSmbClient extends FlutterSmbClientPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('flutter_smb_client');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
