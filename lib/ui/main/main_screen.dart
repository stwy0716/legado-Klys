import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:legado_md3/help/storage/import_book_service.dart';
import 'package:legado_md3/help/storage/auto_update_service.dart';
import 'package:legado_md3/help/storage/source_importer.dart';
import 'package:provider/provider.dart';
import 'package:legado_md3/di/book_provider.dart';
import 'package:legado_md3/ui/main/bookshelf/bookshelf_screen.dart';
import 'package:legado_md3/ui/main/discover/discover_screen.dart';
import 'package:legado_md3/ui/main/subscribe/subscribe_screen.dart';
import 'package:legado_md3/ui/main/my/profile_screen.dart';
import 'package:legado_md3/ui/book/local_import_screen.dart';
import 'package:legado_md3/ui/backup/backup_screen.dart';
import 'package:legado_md3/ui/cache/cache_manage_screen.dart';
import 'package:legado_md3/ui/bookmark/bookmark_screen.dart';
import 'package:legado_md3/ui/config/replace_rule_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0; // 默认书架
  final PageController _pageController = PageController(initialPage: 0);
  static const _fileChannel = MethodChannel('legado/file_intent');
  final ImportBookService _importService = ImportBookService();

  final List<Widget> _screens = const [
    BookshelfScreen(),
    DiscoverScreen(),
    SubscribeScreen(),
    ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<BookProvider>(context, listen: false).loadBooks();
      _checkOpenedFile();
      AutoUpdateService.instance.start(onUpdated: (n) {
        if (mounted) {
          Provider.of<BookProvider>(context, listen: false).loadBooks();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('自动更新：$n 本有新章节')));
        }
      });
    });
    _fileChannel.setMethodCallHandler((call) async {
      if (call.method == 'onFileOpened' && call.arguments is String) {
        _importOpened(call.arguments as String);
      }
    });
  }

  Future<void> _checkOpenedFile() async {
    try {
      final path = await _fileChannel.invokeMethod<String>('getInitialFile');
      if (path != null && path.isNotEmpty) _importOpened(path);
    } catch (_) {}
  }

  Future<void> _importOpened(String input) async {
    final messenger = ScaffoldMessenger.of(context);
    final s = input.trim();
    if (s.isEmpty) return;

    // 深度链接 / 分享的 URL：legado://import/... 或 http(s)
    if (s.startsWith('legado://') ||
        s.startsWith('http://') ||
        s.startsWith('https://')) {
      await _handleDeepLink(s);
      return;
    }

    // 按扩展名区分文件类型
    final lower = s.toLowerCase();
    final ext = lower.contains('.') ? lower.split('.').last : '';
    if (ext == 'json') {
      await _importSourceFile(s);
      return;
    }
    if (ext == 'pdf') {
      await _openPdf(s);
      return;
    }

    // 其余按本地书籍导入（txt/epub/umd/mobi/azw）
    try {
      final res = await _importService.importPath(s);
      messenger.showSnackBar(SnackBar(content: Text('已导入《${res.book.name}》，共 ${res.chapterCount} 章')));
      if (mounted) Provider.of<BookProvider>(context, listen: false).loadBooks();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('导入失败: $e')));
    }
  }

  /// 处理 legado://import/{bookSource|rssSource}?src=<url> 与 http(s) 链接
  Future<void> _handleDeepLink(String uri) async {
    String? src;
    final u = Uri.tryParse(uri);
    if (u != null && u.scheme == 'legado' && u.host == 'import') {
      src = u.queryParameters['src'] ?? u.queryParameters['url'] ?? '';
    } else {
      src = uri;
    }
    if (src == null || src.isEmpty) return;
    await _importSourceFromUrl(src);
  }

  Future<void> _importSourceFromUrl(String url) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        responseType: ResponseType.plain,
      ));
      final res = await dio.get<String>(url);
      final r = await SourceImporter.importRaw(res.data ?? '');
      messenger.showSnackBar(
        SnackBar(content: Text(r.isEmpty ? '未识别到有效的书源/订阅源' : r.toString())),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('导入失败: $e')));
    }
  }

  Future<void> _importSourceFile(String path) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final content = await File(path).readAsString();
      final r = await SourceImporter.importRaw(content);
      messenger.showSnackBar(
        SnackBar(content: Text(r.isEmpty ? '未识别到有效的书源/订阅源' : r.toString())),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('导入失败: $e')));
    }
  }

  Future<void> _openPdf(String path) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final ok = await launchUrl(Uri.file(path), mode: LaunchMode.externalApplication);
      if (!ok) throw Exception('无法打开');
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('PDF 文件已接收，请在文件管理中用系统阅读器打开')),
      );
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    setState(() => _currentIndex = index);
  }

  void _onItemTapped(int index) {
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
    );
  }

  Route<dynamic>? _onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/local_import':
        return MaterialPageRoute(builder: (_) => const LocalImportScreen());
      case '/backup':
        return MaterialPageRoute(builder: (_) => const BackupScreen());
      case '/cache':
        return MaterialPageRoute(builder: (_) => const CacheManageScreen());
      case '/bookmark':
        return MaterialPageRoute(builder: (_) => const BookmarkScreen());
      case '/replace':
        return MaterialPageRoute(builder: (_) => const ReplaceRuleScreen());
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Navigator(
      onGenerateRoute: (settings) {
        if (settings.name == '/') {
          return MaterialPageRoute(builder: (_) => _buildMainScaffold());
        }
        return _onGenerateRoute(settings);
      },
    );
  }

  Widget _buildMainScaffold() {
    return Scaffold(
      body: PageView(
        controller: _pageController,
        onPageChanged: _onPageChanged,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _onItemTapped,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book),
            label: '书架',
          ),
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore),
            label: '发现',
          ),
          NavigationDestination(
            icon: Icon(Icons.subscriptions_outlined),
            selectedIcon: Icon(Icons.subscriptions),
            label: '订阅',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: '我的',
          ),
        ],
      ),
    );
  }
}
