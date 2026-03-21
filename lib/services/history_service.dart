import 'package:hive_flutter/hive_flutter.dart';
import '../models/history_entry.dart';

class HistoryService {
  static const _boxName = 'history';
  static HistoryService? _instance;
  static HistoryService get instance => _instance ??= HistoryService._();
  HistoryService._();

  Box<HistoryEntry>? _box;

  Future<void> init() async {
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(HistoryEntryAdapter());
    }
    _box = await Hive.openBox<HistoryEntry>(_boxName);
  }

  Future<void> save(HistoryEntry entry) async {
    await _box?.put(entry.id.toString(), entry);
  }

  List<HistoryEntry> getAll() {
    final entries = _box?.values.toList() ?? [];
    entries.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return entries;
  }

  HistoryEntry? getById(int id) {
    return _box?.get(id.toString());
  }

  Future<void> delete(int id) async {
    await _box?.delete(id.toString());
  }

  Future<void> clear() async {
    await _box?.clear();
  }
}
