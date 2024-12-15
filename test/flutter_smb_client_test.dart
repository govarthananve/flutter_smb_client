import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_smb_client/flutter_smb_client.dart';
import 'package:flutter_smb_client/flutter_smb_client_platform_interface.dart';
import 'package:flutter_smb_client/flutter_smb_client_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockFlutterSmbClientPlatform
    with MockPlatformInterfaceMixin
    implements FlutterSmbClientPlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final FlutterSmbClientPlatform initialPlatform = FlutterSmbClientPlatform.instance;

  test('$MethodChannelFlutterSmbClient is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelFlutterSmbClient>());
  });

  test('getPlatformVersion', () async {
    FlutterSmbClient flutterSmbClientPlugin = FlutterSmbClient();
    MockFlutterSmbClientPlatform fakePlatform = MockFlutterSmbClientPlatform();
    FlutterSmbClientPlatform.instance = fakePlatform;

    expect(await flutterSmbClientPlugin.getPlatformVersion(), '42');
  });
}
