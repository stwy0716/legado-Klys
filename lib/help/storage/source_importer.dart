import 'dart:convert';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/data/model/rss_source.dart';

/// 源导入结果（书源 / 订阅源计数）
class SourceImportResult {
  final int bookCount;
  final int rssCount;
  const SourceImportResult(this.bookCount, this.rssCount);
  int get total => bookCount + rssCount;
  bool get isEmpty => total == 0;
  @override
  String toString() {
    if (bookCount > 0 && rssCount > 0) return '导入 $bookCount 个书源、$rssCount 个订阅源';
    if (bookCount > 0) return '导入 $bookCount 个书源';
    if (rssCount > 0) return '导入 $rssCount 个订阅源';
    return '未识别到有效的书源/订阅源';
  }
}

/// 统一的书源 / 订阅源导入器：自动识别 JSON 类型并入库。
class SourceImporter {
  SourceImporter._();

  /// 判断是否为书源（bookSourceUrl 字段是书源硬标识）
  static bool isBookSource(Map m) =>
      (m['bookSourceUrl'] ?? '').toString().trim().isNotEmpty;

  /// 判断是否为订阅源（sourceUrl + 订阅规则特征；且非书源）
  static bool isRssSource(Map m) {
    if (isBookSource(m)) return false;
    final url = (m['sourceUrl'] ?? m['url'] ?? '').toString().trim();
    if (url.isEmpty) return false;
    if (m['ruleArticles'] != null ||
        m['ruleContent'] != null ||
        m['ruleTitle'] != null ||
        m['singleUrl'] != null ||
        m['sortUrl'] != null ||
        m['ruleNextPage'] != null) {
      return true;
    }
    final t = m['type']?.toString().toLowerCase();
    return t == '订阅源' || t == 'rss' || t == '2';
  }

  /// 解包常见包装：{data:[...]} / {bookSources:[...]} / 单对象 / JSONL
  static List<dynamic> unwrap(dynamic data) {
    dynamic d = data;
    if (d is Map &&
        !d.containsKey('bookSourceUrl') &&
        !d.containsKey('sourceUrl')) {
      for (final k in const [
        'data', 'bookSources', 'rssSources', 'sources', 'result', 'list', 'records',
      ]) {
        if (d[k] is List) {
          d = d[k];
          break;
        }
      }
    }
    return d is List ? d : [d];
  }

  /// 从原始文本解析 JSON 为对象/数组（兼容 JSONL 与 BOM）
  static dynamic decode(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return null;
    if (text.startsWith('\uFEFF')) text = text.substring(1);
    try {
      return jsonDecode(text);
    } catch (_) {
      final lines = text
          .split(RegExp(r'[\r\n]+'))
          .where((l) => l.trim().startsWith('{'))
          .toList();
      if (lines.isEmpty) return null;
      final arr = <dynamic>[];
      for (final l in lines) {
        try {
          arr.add(jsonDecode(l));
        } catch (_) {}
      }
      return arr;
    }
  }

  /// 从原始文本导入（自动区分书源 / 订阅源）
  static Future<SourceImportResult> importRaw(String raw) async {
    final decoded = decode(raw);
    if (decoded == null) return const SourceImportResult(0, 0);
    return importData(decoded);
  }

  /// 从已解析 JSON 导入
  static Future<SourceImportResult> importData(dynamic data) async {
    final db = DatabaseService();
    int book = 0, rss = 0;
    for (final item in unwrap(data)) {
      if (item is! Map) continue;
      final m = Map<String, dynamic>.from(item);
      try {
        if (isBookSource(m)) {
          await db.insertSource(BookSource.fromJson(m));
          book++;
        } else if (isRssSource(m)) {
          await db.insertRssSource(RssSource.fromJson(m));
          rss++;
        }
      } catch (_) {}
    }
    return SourceImportResult(book, rss);
  }
}
