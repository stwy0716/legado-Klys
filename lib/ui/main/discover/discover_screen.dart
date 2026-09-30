import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/data/model/search_book.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/help/source/source_engine.dart';
import 'package:legado_md3/di/book_provider.dart';
import 'package:legado_md3/ui/book/search/search_screen.dart';
import 'package:legado_md3/ui/book/source/source_manage_screen.dart';
import 'package:legado_md3/ui/book/read/reading_screen.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final DatabaseService _db = DatabaseService();
  final BookSourceEngine _engine = BookSourceEngine();
  List<BookSource> _sourcesWithExplore = [];
  bool _isLoading = true;
  BookSource? _selectedSource;
  List<Map<String, String>> _exploreItems = [];
  List<SearchBook> _exploreBooks = [];
  bool _isLoadingBooks = false;
  String? _currentExploreUrl;
  int _explorePage = 1;
  bool _loadingMore = false;
  bool _hasMore = true;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _scrollController.addListener(_onScroll);
    _loadSources();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 300) {
      _loadMoreExplore();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadSources() async {
    setState(() => _isLoading = true);
    final allSources = await _db.getAllSources(enabled: true);
    _sourcesWithExplore = allSources.where((s) => s.exploreUrl != null && s.exploreUrl!.isNotEmpty).toList();
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadExplore(BookSource source) async {
    setState(() {
      _selectedSource = source;
      _isLoadingBooks = false;
      _exploreBooks = [];
    });
    // 解析发现URL：每行一个分类，格式 "名称:::URL"；一行内多选项用 &&& 连接
    final items = <Map<String, String>>[];
    final raw = source.exploreUrl ?? '';
    for (final line in raw.split(RegExp(r'[\n]'))) {
      if (line.trim().isEmpty) continue;
      for (final opt in line.split('&&&')) {
        final seg = opt.trim();
        if (seg.isEmpty) continue;
        final idx = seg.indexOf(':::');
        if (idx >= 0) {
          items.add({'name': seg.substring(0, idx).trim(), 'url': seg.substring(idx + 3).trim()});
        } else {
          // 没有名称时整段作为URL，名称取默认
          items.add({'name': '推荐', 'url': seg});
        }
      }
    }
    setState(() => _exploreItems = items);
    // 只有一个分类时直接加载
    if (items.length == 1) _loadExploreBooks(items.first['url']!);
  }

  /// 将发现 URL 中的 {{page}} / {{page-1}} 替换为实际页码
  String _applyPage(String url, int page) {
    var u = url.replaceAll('{{page-1}}', '${page - 1}');
    u = u.replaceAll('{{ page - 1 }}', '${page - 1}');
    u = u.replaceAll('{{page}}', '$page');
    u = u.replaceAll('{{ page }}', '$page');
    return u;
  }

  Future<void> _loadExploreBooks(String url) async {
    if (_selectedSource == null) return;
    _currentExploreUrl = url;
    _explorePage = 1;
    _hasMore = true;
    setState(() { _isLoadingBooks = true; _exploreBooks = []; });
    await _fetchExplore(append: false);
  }

  Future<void> _loadMoreExplore() async {
    if (_loadingMore || _isLoadingBooks || !_hasMore || _currentExploreUrl == null) return;
    final url = _currentExploreUrl!;
    // URL 不含分页占位符时无法继续翻页
    if (!url.contains('{{page') && !url.contains('{{ page')) { _hasMore = false; return; }
    _explorePage++;
    await _fetchExplore(append: true);
  }

  Future<void> _fetchExplore({required bool append}) async {
    if (_selectedSource == null || _currentExploreUrl == null) return;
    if (append) setState(() => _loadingMore = true);
    try {
      final reqUrl = _applyPage(_currentExploreUrl!, _explorePage);
      final response = await _engine.exploreByUrl(_selectedSource!, reqUrl);
      if (!mounted) return;
      setState(() {
        if (append) {
          _exploreBooks.addAll(response);
          if (response.isEmpty) { _hasMore = false; _explorePage--; }
        } else {
          _exploreBooks = response;
        }
        _isLoadingBooks = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (mounted) setState(() { _isLoadingBooks = false; _loadingMore = false; if (append) { _hasMore = false; _explorePage--; } });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('发现'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '发现'),
            Tab(text: '书源'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SearchScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadSources,
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'switch_source': _showSourceSwitcher(); break;
                case 'category': _showCategoryManager(); break;
                case 'filter': _showFilterDialog(); break;
                case 'sort': _showSortDialog(); break;
                case 'refresh': _loadSources(); break;
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'switch_source', child: ListTile(leading: Icon(Icons.swap_horiz), title: Text('切换书源'))),
              PopupMenuItem(value: 'category', child: ListTile(leading: Icon(Icons.category), title: Text('分类管理'))),
              PopupMenuItem(value: 'filter', child: ListTile(leading: Icon(Icons.filter_list), title: Text('筛选'))),
              PopupMenuItem(value: 'sort', child: ListTile(leading: Icon(Icons.sort), title: Text('排序'))),
              PopupMenuItem(value: 'refresh', child: ListTile(leading: Icon(Icons.refresh), title: Text('刷新'))),
            ],
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildDiscoverTab(),
          SourceManageScreen(),
        ],
      ),
    );
  }

  Widget _buildDiscoverTab() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_sourcesWithExplore.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.explore_outlined, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text('暂无发现内容', style: TextStyle(fontSize: 18, color: Colors.grey[600])),
            const SizedBox(height: 8),
            Text('请先在"书源"中添加并启用带发现功能的书源', style: TextStyle(color: Colors.grey[500])),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => _tabController.animateTo(1),
              icon: const Icon(Icons.add),
              label: const Text('添加书源'),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        // 书源选择器
        SizedBox(
          height: 50,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _sourcesWithExplore.length,
            itemBuilder: (context, index) {
              final source = _sourcesWithExplore[index];
              final isSelected = _selectedSource?.bookSourceUrl == source.bookSourceUrl;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(source.bookSourceName),
                  selected: isSelected,
                  onSelected: (_) => _loadExplore(source),
                ),
              );
            },
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _isLoadingBooks
              ? const Center(child: CircularProgressIndicator())
              : _selectedSource == null
                  ? Center(child: Text('选择一个书源查看发现内容', style: TextStyle(color: Colors.grey[600])))
                  : _exploreItems.isEmpty && _exploreBooks.isEmpty
                      ? Center(child: Text('暂无内容', style: TextStyle(color: Colors.grey[600])))
                      : _exploreItems.isNotEmpty
                          ? _buildExploreList()
                          : _buildBooksList(),
        ),
      ],
    );
  }

  Widget _buildExploreList() {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _exploreItems.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = _exploreItems[index];
        return Card(
          child: ListTile(
            leading: const Icon(Icons.category),
            title: Text(item['name'] ?? ''),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _loadExploreBooks(item['url'] ?? ''),
          ),
        );
      },
    );
  }

  Widget _buildBooksList() {
    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _exploreBooks.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        if (index == _exploreBooks.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: _loadingMore
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(!_hasMore && _exploreBooks.isNotEmpty ? '没有更多了' : '', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ),
          );
        }
        final book = _exploreBooks[index];
        return Card(
          child: ListTile(
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: book.coverUrl != null && book.coverUrl!.isNotEmpty
                  ? Image.network(book.coverUrl!, width: 48, height: 64, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(width: 48, height: 64, color: Colors.grey[300], child: Icon(Icons.book, color: Colors.grey[500])))
                  : Container(width: 48, height: 64, color: Colors.grey[300], child: Icon(Icons.book, color: Colors.grey[500])),
            ),
            title: Text(book.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(book.author, style: const TextStyle(fontSize: 12)),
            trailing: FilledButton.tonal(
              onPressed: () async {
                final provider = context.read<BookProvider>();
                await provider.addBook(book.toBook());
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已添加《${book.name}》')));
                }
              },
              child: const Text('加入'),
            ),
            onTap: () async {
              final provider = context.read<BookProvider>();
              await provider.addBook(book.toBook());
              if (mounted) {
                Navigator.push(context, MaterialPageRoute(builder: (_) => ReadingScreen(book: book.toBook())));
              }
            },
          ),
        );
      },
    );
  }

  void _showSourceSwitcher() {
    showModalBottomSheet(context: context, builder: (context) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Padding(padding: EdgeInsets.all(16), child: Text('选择发现书源', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
      ..._sourcesWithExplore.where((s) => s.enabledExplore == true).map((s) => ListTile(
        leading: const Icon(Icons.menu_book),
        title: Text(s.bookSourceName),
        subtitle: Text(s.bookSourceUrl, maxLines: 1, overflow: TextOverflow.ellipsis),
        onTap: () { setState(() => _selectedSource = s); Navigator.pop(context); _loadExplore(s); },
      )),
    ])));
  }

  void _showCategoryManager() {
    showDialog(context: context, builder: (context) => AlertDialog(
      title: const Text('分类管理'),
      content: const Text('管理发现页面的分类显示顺序和可见性'),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭'))],
    ));
  }

  void _showFilterDialog() {
    showDialog(context: context, builder: (context) => AlertDialog(
      title: const Text('筛选'),
      content: const Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(title: Text('书名')),
        ListTile(title: Text('作者')),
        ListTile(title: Text('简介')),
        ListTile(title: Text('分类')),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭'))],
    ));
  }

  void _showSortDialog() {
    showDialog(context: context, builder: (context) => SimpleDialog(
      title: const Text('排序方式'),
      children: const [
        SimpleDialogOption(child: Text('默认排序')),
        SimpleDialogOption(child: Text('名称')),
        SimpleDialogOption(child: Text('作者')),
        SimpleDialogOption(child: Text('更新时间')),
        SimpleDialogOption(child: Text('最新章节')),
      ],
    ));
  }
}
