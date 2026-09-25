import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'local_store.dart';

/// JSON files in the app support directory. A fresh read always sees the
/// other isolate's last write, which shared_preferences caches do not.
class FileStore implements KeyValueStore {
  FileStore(this.directory);

  final Directory directory;

  static Future<FileStore> open() async {
    final root = await getApplicationSupportDirectory();
    final folder = Directory('${root.path}/tr_daily');
    if (!folder.existsSync()) {
      folder.createSync(recursive: true);
    }
    return FileStore(folder);
  }

  File _file(String key) =>
      File('${directory.path}/${key.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}.json');

  @override
  Future<String?> read(String key) async {
    final file = _file(key);
    if (!file.existsSync()) return null;
    return file.readAsString();
  }

  @override
  Future<void> write(String key, String value) async {
    final file = _file(key);
    await file.writeAsString(value, flush: true);
  }

  @override
  Future<void> delete(String key) async {
    final file = _file(key);
    if (file.existsSync()) await file.delete();
  }
}

Future<KeyValueStore> openPersistentStore() => FileStore.open();
