import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'flutter_smb_client_method_channel.dart';

abstract class FlutterSmbClientPlatform extends PlatformInterface {
  /// Constructs a FlutterSmbClientPlatform.
  FlutterSmbClientPlatform() : super(token: _token);

  static final Object _token = Object();

  static FlutterSmbClientPlatform _instance = MethodChannelFlutterSmbClient();

  /// The default instance of [FlutterSmbClientPlatform] to use.
  ///
  /// Defaults to [MethodChannelFlutterSmbClient].
  static FlutterSmbClientPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [FlutterSmbClientPlatform] when
  /// they register themselves.
  static set instance(FlutterSmbClientPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
