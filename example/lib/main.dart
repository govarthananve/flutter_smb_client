// In example/lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_smb_client/flutter_smb_client.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _status = 'Not connected';
  List<Map<String, dynamic>> _files = [];

  Future<void> _connect() async {
    final connected = await FlutterSmbClient.connect(
      host: '192.168.1.100',
      username: 'username',
      password: 'password',
    );
    setState(() {
      _status = connected ? 'Connected' : 'Connection failed';
    });
  }

  Future<void> _listFiles() async {
    final files = await FlutterSmbClient.listFiles('/shared/folder');
    setState(() {
      _files = files;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('SMB Client Example')),
        body: Column(
          children: [
            Text('Status: $_status'),
            ElevatedButton(
              onPressed: _connect,
              child: const Text('Connect'),
            ),
            ElevatedButton(
              onPressed: _listFiles,
              child: const Text('List Files'),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: _files.length,
                itemBuilder: (context, index) {
                  final file = _files[index];
                  return ListTile(
                    title: Text(file['name'] ?? ''),
                    subtitle: Text(file['size']?.toString() ?? ''),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
