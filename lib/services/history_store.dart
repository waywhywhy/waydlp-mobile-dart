import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

enum EntryStatus { inProgress, completed, failed, cancelled }

class HistoryEntry {
  HistoryEntry({
    required this.id,
    required this.title,
    required this.url,
    required this.site,
    required this.createdAt,
    required this.format,
    required this.optionsJson,
    required this.isPlaylist,
    required this.files,
    required this.status,
    this.size,
    this.thumbnail,
    this.error,
    this.mime,
  });

  final int id;
  final String title, url, site, format, optionsJson;
  final DateTime createdAt;
  final bool isPlaylist;
  final List<String> files; // content:// URIs
  final EntryStatus status;
  final int? size;
  final String? thumbnail, error, mime;

  static HistoryEntry fromRow(Map<String, Object?> r) => HistoryEntry(
    id: r['id'] as int,
    title: r['title'] as String,
    url: r['url'] as String,
    site: r['site'] as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
    format: r['format'] as String,
    optionsJson: r['options_json'] as String,
    isPlaylist: (r['is_playlist'] as int) != 0,
    files: ((r['files'] as String?) ?? '').split('\n').where((s) => s.isNotEmpty).toList(),
    status: EntryStatus.values.firstWhere((s) => s.name == r['status'], orElse: () => EntryStatus.cancelled),
    size: r['size'] as int?,
    thumbnail: r['thumbnail'] as String?,
    error: r['error'] as String?,
    mime: r['mime'] as String?,
  );
}

/// Download history in SQLite. Removing an entry never deletes files.
class HistoryStore {
  HistoryStore._(this._db);
  final Database _db;

  static Future<HistoryStore> open({String? path, DatabaseFactory? factory}) async {
    final f = factory ?? databaseFactory;
    final dbPath = path ?? p.join(await f.getDatabasesPath(), 'history.db');
    final db = await f.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, v) async {
          await db.execute('''
            CREATE TABLE downloads(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              title TEXT NOT NULL, url TEXT NOT NULL, site TEXT NOT NULL,
              created_at INTEGER NOT NULL, finished_at INTEGER,
              format TEXT NOT NULL, options_json TEXT NOT NULL,
              is_playlist INTEGER NOT NULL DEFAULT 0,
              files TEXT NOT NULL DEFAULT '', status TEXT NOT NULL,
              size INTEGER, thumbnail TEXT, error TEXT, mime TEXT)''');
          await db.execute('CREATE INDEX idx_created ON downloads(created_at DESC)');
        },
      ),
    );
    return HistoryStore._(db);
  }

  Future<int> insert({
    required String title,
    required String url,
    required String site,
    required String format,
    required String optionsJson,
    required bool isPlaylist,
    String? thumbnail,
  }) => _db.insert('downloads', {
    'title': title,
    'url': url,
    'site': site,
    'created_at': DateTime.now().millisecondsSinceEpoch,
    'format': format,
    'options_json': optionsJson,
    'is_playlist': isPlaylist ? 1 : 0,
    'status': EntryStatus.inProgress.name,
    'thumbnail': thumbnail,
  });

  Future<void> finish(
    int id,
    EntryStatus status, {
    List<String> files = const [],
    int? size,
    String? error,
    String? mime,
    String? title,
  }) async {
    await _db.update(
      'downloads',
      {
        'status': status.name,
        'files': files.join('\n'),
        'size': size,
        'error': error,
        'mime': mime,
        'finished_at': DateTime.now().millisecondsSinceEpoch,
        'title': ?title,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<HistoryEntry>> list({String search = '', EntryStatus? status, int limit = 1000}) async {
    final where = <String>[];
    final args = <Object?>[];
    if (search.trim().isNotEmpty) {
      final q = '%${search.trim().replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_')}%';
      where.add(r"(title LIKE ? ESCAPE '\' OR url LIKE ? ESCAPE '\' OR site LIKE ? ESCAPE '\')");
      args.addAll([q, q, q]);
    }
    if (status != null) {
      where.add('status = ?');
      args.add(status.name);
    }
    final rows = await _db.query(
      'downloads',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'created_at DESC, id DESC',
      limit: limit,
    );
    return rows.map(HistoryEntry.fromRow).toList();
  }

  Future<HistoryEntry?> get(int id) async {
    final rows = await _db.query('downloads', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : HistoryEntry.fromRow(rows.first);
  }

  Future<void> remove(int id) => _db.delete('downloads', where: 'id = ?', whereArgs: [id]);

  Future<int> clear() => _db.delete('downloads', where: 'status != ?', whereArgs: [EntryStatus.inProgress.name]);

  /// Mark unfinished entries as interrupted, except those in [stillRunning]
  /// (jobs the background service is still working on).
  Future<int> markInterrupted({Set<int> stillRunning = const {}}) => _db.update(
    'downloads',
    {'status': EntryStatus.cancelled.name, 'error': 'Interrupted: the app was closed before the download finished.'},
    where: stillRunning.isEmpty
        ? 'status = ?'
        : 'status = ? AND id NOT IN (${List.filled(stillRunning.length, '?').join(',')})',
    whereArgs: [EntryStatus.inProgress.name, ...stillRunning],
  );

  Future<int> pruneOlderThan(int days) async {
    if (days <= 0) return 0;
    final cutoff = DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch;
    return _db.delete(
      'downloads',
      where: 'created_at < ? AND status != ?',
      whereArgs: [cutoff, EntryStatus.inProgress.name],
    );
  }
}
