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
  List<Map<String, dynamic>> _items = [];
  String _currentPath = '';

  Future<void> _connect() async {
    try {
      setState(() {
        _status = 'Connecting...';
      });

      final host = '';

      final connected = await FlutterSmbClient.connect(
          host: host, username: '', password: '', port: 445
          // port is optional, will use default SMB port (445) if not specified
          );

      setState(() {
        print('Connection status: $connected');
        _status = connected ? 'Connected' : 'Connection failed';
      });

      if (connected) {
        await _listDrives();
      }
    } on SMBException catch (e) {
      print('SMB error: ${e.code} - ${e.message}');
      setState(() {
        _status = 'Connection error: ${e.message}';
      });
    } catch (e) {
      print('Unexpected error: $e');
      setState(() {
        _status = 'Unexpected error: $e';
      });
    }
  }

  Future<void> _listDrives() async {
    try {
      setState(() {
        _status = 'Listing drives...';
      });

      final drives = await FlutterSmbClient.listDrives();
      print('Drives response: ${drives.map((d) => d['name']).toList()}');

      setState(() {
        _items = drives;
        _currentPath = '';
        _status = drives.isEmpty ? 'No drives found' : 'Connected';
      });
    } catch (e) {
      print('Error listing drives: $e');
      setState(() {
        _status = 'Error listing drives: $e';
        _items = [];
      });
    }
  }

  Future<void> _listFiles(String path) async {
    final files = await FlutterSmbClient.listFiles(path);
    setState(() {
      _items = files;
      _currentPath = path;
      print("Files in $path: $_items");
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('SMB Client Example'),
          leading: _currentPath.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _listDrives,
                )
              : null,
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text('Status: $_status'),
            ),
            if (_status != 'Connected')
              ElevatedButton(
                onPressed: _connect,
                child: const Text('Connect'),
              ),
            Expanded(
              child: ListView.builder(
                itemCount: _items.length,
                itemBuilder: (context, index) {
                  final item = _items[index];
                  final bool isDirectory = item['isDirectory'] ?? false;
                  final bool isDrive = item['isDrive'] ?? false;

                  return ListTile(
                    leading: Icon(
                      isDrive
                          ? Icons.storage
                          : isDirectory
                              ? Icons.folder
                              : Icons.insert_drive_file,
                      color: isDrive
                          ? Colors.grey
                          : isDirectory
                              ? Colors.orange
                              : Colors.blue,
                    ),
                    title: Text(item['name'] ?? ''),
                    subtitle: !isDirectory && !isDrive
                        ? Text('Size: ${item['size'] ?? 0} bytes')
                        : null,
                    onTap: isDirectory || isDrive
                        ? () => _listFiles(isDrive
                            ? '/${item['name']}'
                            : '$_currentPath/${item['name']}')
                        : null,
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
