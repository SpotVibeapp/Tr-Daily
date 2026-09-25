import 'local_store.dart';

/// Web and tests that do not need a disk. Android/iOS/desktop use the
/// `dart.library.io` implementation so a closed app can resume.
Future<KeyValueStore> openPersistentStore() async => MemoryStore();
