import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'package:share_plus/share_plus.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/di/book_provider.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/help/source/source_engine.dart';
import 'package:legado_md3/ui/book/detail/book_detail_screen.dart';
import 'package:legado_md3/ui/book/read/reading_screen.dart';
import 'package:legado_md3/ui/book/local_import_screen.dart';
import 'package:legado_md3/ui/book/search/search_screen.dart';
import 'package:legado_md3/ui/book/detail/change_source_screen.dart';
import 'package:legado_md3/ui/book/detail/change_cover_screen.dart';
import 'package:legado_md3/ui/bookmark/book_marking_screen.dart';
import 'package:legado_md3/ui/main/bookshelf/group_manage_screen.dart';
import 'package:legado_md3/ui/main/bookshelf/bookshelf_config_screen.dart';
import 'package:legado_md3/ui/main/home/home_screen.dart';
import 'package:legado_md3/ui/book/source/source_manage_screen.dart';
import 'package:legado_md3/ui/stats/read_record_screen.dart';
import 'package:legado_md3/ui/config/settings_screen.dart';

class BookshelfScreen extends StatefulWidget {
  const BookshelfScreen({super.key});

  @override
  State<BookshelfScreen> createState() => _BookshelfScreenState();
}

class _BookshelfScreenState extends State<BookshelfScreen> {
  final DatabaseService _db = DatabaseService();
  final BookSourceEngine _engine = BookSourceEngine();
  bool _selectMode = false;
  final Set<Book> _selectedBooks = {};
  bool _isUpdating = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  static const List<String> _sortOptions = ['智能排序', '书名', '作者', '最近阅读', '添加时间', '字数'];
  int _sortBy = 0;
  bool _sortAsc = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<BookProvider>(context, listen: false).loadBooks();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Book> get _filteredBooks {
    final provider = Provider.of<BookProvider>(context, listen: false);
    var books = provider.filteredBooks;
    if (_searchQuery.isNotEmpty) {
      books = books.where((b) =>
          b.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          b.author.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
    }
    books = List.from(books);
    switch (_sortBy) {
      case 1: books.sort((a, b) => _sortAsc ? a.name.compareTo(b.name) : b.name.compareTo(a.name)); break;
      case 2: books.sort((a, b) => _sortAsc ? a.author.compareTo(b.author) : b.author.compareTo(a.author)); break;
      case 3: books.sort((a, b) => _sortAsc ? a.durChapterTime.compareTo(b.durChapterTime) : b.durChapterTime.compareTo(a.durChapterTime)); break;
      case 4: books.sort((a, b) => _sortAsc ? (a.lastCheckTime ?? 0).compareTo(b.lastCheckTime ?? 0) : (b.lastCheckTime ?? 0).compareTo(a.lastCheckTime ?? 0)); break;
      case 5: books.sort((a, b) => _sortAsc ? (a.wordCount ?? 0).compareTo(b.wordCount ?? 0) : (b.wordCount ?? 0).compareTo(a.wordCount ?? 0)); break;
    }
    return books;
  }

  Future<void> _updateAllBooks() async {
    setState(() => _isUpdating = true);
    final provider = Provider.of<BookProvider>(context, listen: false);
    final books = provider.books.where((b) => !b.local && b.origin != null && b.noteUrl != null).toList();
    final sources = await _db.getAllSources(enabled: true);
    final sourceMap = {for (var s in sources) s.bookSourceUrl: s};
    int updated = 0;
    for (final book in books) {
      final source = sourceMap[book.origin];
      if (source == null) continue;
      try {
        final newChapters = await _engine.getToc(source, book.noteUrl!);
        final oldChapters = await _db.getChapters(book.name, book.author);
        if (newChapters.length > oldChapters.length) {
          await _db.saveChapters(book.name, book.author, newChapters);
          book.lastChapter = newChapters.last.title;
          book.lastChapterIndex = newChapters.length - 1;
          book.latestChapterTime = DateTime.now().millisecondsSinceEpoch;
          await _db.updateBook(book);
          updated++;
        }
      } catch (_) {}
    }
    await provider.loadBooks();
    setState(() => _isUpdating = false);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('更新完成，$updated 本有新章节')));
  }

  void _showSortDialog() {
    showDialog(context: context, builder: (context) => AlertDialog(
      title: const Text('排序方式'),
      content: Column(mainAxisSize: MainAxisSize.min, children: List.generate(_sortOptions.length, (index) => ListTile(
        title: Text(_sortOptions[index]),
        trailing: _sortBy == index ? Icon(_sortAsc ? Icons.arrow_upward : Icons.arrow_downward, color: Colors.green) : null,
        onTap: () { if (_sortBy == index) { setState(() => _sortAsc = !_sortAsc); } else { setState(() => _sortBy = index); } Navigator.pop(context); },
      ))),
    ));
  }

  void _showMoreMenu() {
    showModalBottomSheet(context: context, builder: (context) => SafeArea(child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(leading: const Icon(Icons.dashboard_outlined), title: const Text('首页模块视图'), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const HomeScreen())); }),
      ListTile(leading: const Icon(Icons.search), title: const Text('搜索书籍'), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen())); }),
      ListTile(leading: const Icon(Icons.refresh), title: const Text('一键更新'), onTap: () { Navigator.pop(context); _updateAllBooks(); }),
      const Divider(),
      ListTile(leading: const Icon(Icons.folder_open), title: const Text('本地导入'), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const LocalImportScreen())); }),
      ListTile(leading: const Icon(Icons.cloud_download), title: const Text('书源管理/网络导入'), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const SourceManageScreen())); }),
      const Divider(),
      ListTile(leading: const Icon(Icons.view_module), title: const Text('布局设置'), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const BookshelfConfigScreen())); }),
      ListTile(leading: const Icon(Icons.sort), title: const Text('排序设置'), onTap: () { Navigator.pop(context); _showSortDialog(); }),
      ListTile(leading: const Icon(Icons.folder_special), title: const Text('分组管理'), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const GroupManageScreen())); }),
      ListTile(leading: const Icon(Icons.select_all), title: const Text('多选模式'), onTap: () { Navigator.pop(context); setState(() => _selectMode = true); }),
      const Divider(),
      ListTile(leading: const Icon(Icons.menu_book_outlined), title: const Text('书源管理'), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const SourceManageScreen())); }),
      ListTile(leading: const Icon(Icons.bar_chart_outlined), title: const Text('阅读记录'), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const ReadRecordScreen())); }),
      ListTile(leading: const Icon(Icons.settings), title: const Text('设置'), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())); }),
      const Divider(),
      ListTile(leading: const Icon(Icons.delete_sweep, color: Colors.red), title: const Text('清空书架', style: TextStyle(color: Colors.red)), onTap: () async {
        Navigator.pop(context);
        final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: const Text('清空书架'), content: const Text('确定要清空所有书籍吗？'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')), FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(context, true), child: const Text('清空'))]));
        if (confirmed == true) { final provider = Provider.of<BookProvider>(context, listen: false); for (final book in provider.books) { await _db.deleteBook(book.name, book.author); } await provider.loadBooks(); }
      }),
    ]))));
  }

  void _showBookMenu(Book book) {
    showModalBottomSheet(context: context, builder: (context) => SafeArea(child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(leading: const Icon(Icons.play_arrow), title: const Text('开始阅读'), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => ReadingScreen(book: book))); }),
      ListTile(leading: const Icon(Icons.info_outline), title: const Text('书籍详情'), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => BookDetailScreen(book: book))); }),
      const Divider(),
      ListTile(leading: const Icon(Icons.refresh), title: const Text('更新目录'), onTap: () async {
        Navigator.pop(context);
        if (book.local || book.origin == null || book.noteUrl == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('本地书籍无需更新'))); return; }
        final sources = await _db.getAllSources(enabled: true);
        final source = sources.where((s) => s.bookSourceUrl == book.origin).firstOrNull;
        if (source == null) return;
        try { final chapters = await _engine.getToc(source, book.noteUrl!); await _db.saveChapters(book.name, book.author, chapters); book.lastChapter = chapters.last.title; book.lastChapterIndex = chapters.length - 1; await _db.updateBook(book); if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('更新完成，共${chapters.length}章'))); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('更新失败: $e'))); }
      }),
      ListTile(leading: const Icon(Icons.swap_horiz), title: const Text('换源'), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => ChangeSourceScreen(book: book))); }),
      ListTile(leading: const Icon(Icons.image_outlined), title: const Text('换封面'), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => ChangeCoverScreen(book: book))); }),
      ListTile(leading: const Icon(Icons.download), title: const Text('缓存全部'), onTap: () { Navigator.pop(context); _cacheOneBook(book); }),
      ListTile(leading: const Icon(Icons.flag_outlined), title: const Text('书籍标记'), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => BookMarkingScreen(bookName: book.name, author: book.author))); }),
      ListTile(leading: const Icon(Icons.bookmark_border), title: const Text('添加书签'), onTap: () async {
        Navigator.pop(context);
        final bookmark = await _db.getBookmarks(book.name, book.author);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('当前共${bookmark.length}个书签')));
      }),
      const Divider(),
      ListTile(leading: const Icon(Icons.move_down), title: const Text('移动到分组'), onTap: () { Navigator.pop(context); _showMoveGroupDialog(book); }),
      ListTile(leading: const Icon(Icons.push_pin_outlined), title: Text(book.order != null && book.order! < 0 ? '取消置顶' : '置顶'), onTap: () async {
        Navigator.pop(context);
        book.order = (book.order != null && book.order! < 0) ? 0 : -1;
        await _db.updateBook(book);
        await Provider.of<BookProvider>(context, listen: false).loadBooks();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(book.order != null && book.order! < 0 ? '已置顶' : '已取消置顶')));
      }),
      ListTile(leading: const Icon(Icons.share), title: const Text('分享'), onTap: () async {
        Navigator.pop(context);
        await Share.share('《${book.name}》 - ${book.author}\n${book.intro ?? ''}', subject: book.name);
      }),
      const Divider(),
      ListTile(leading: const Icon(Icons.delete_outline, color: Colors.red), title: const Text('删除', style: TextStyle(color: Colors.red)), onTap: () async {
        Navigator.pop(context);
        final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: Text('删除《${book.name}》'), content: const Text('确定要删除这本书吗？'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')), FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(context, true), child: const Text('删除'))]));
        if (confirmed == true) { await _db.deleteBook(book.name, book.author); await Provider.of<BookProvider>(context, listen: false).loadBooks(); }
      }),
    ]))));
  }

  void _showMoveGroupDialog(Book book) {
    final provider = Provider.of<BookProvider>(context, listen: false);
    final controller = TextEditingController(text: book.group ?? '');
    showDialog(context: context, builder: (context) => AlertDialog(
      title: const Text('移动到分组'),
      content: TextField(controller: controller, decoration: const InputDecoration(hintText: '输入分组名称（留空为默认）')),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')), FilledButton(onPressed: () async { book.group = controller.text.trim().isEmpty ? null : controller.text.trim(); await _db.updateBook(book); await provider.loadBooks(); if (mounted) Navigator.pop(context); }, child: const Text('确定'))],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<BookProvider>(context);
    final books = _filteredBooks;
    final layout = provider.bookshelfLayout;
    return Scaffold(
      appBar: AppBar(
        title: _searchQuery.isEmpty ? const Text('书架') : TextField(controller: _searchController, autofocus: true, decoration: const InputDecoration(hintText: '搜索书籍...', border: InputBorder.none), onChanged: (v) => setState(() => _searchQuery = v)),
        actions: [
          if (_searchQuery.isEmpty) IconButton(icon: const Icon(Icons.search), onPressed: () => setState(() => _searchQuery = ' ')),
          if (_searchQuery.isNotEmpty) IconButton(icon: const Icon(Icons.clear), onPressed: () { _searchController.clear(); setState(() => _searchQuery = ''); }),
          if (_selectMode) ...[
            IconButton(icon: const Icon(Icons.select_all), tooltip: '全选', onPressed: () => setState(() { _selectedBooks
              ..clear()..addAll(books); })),
            IconButton(icon: const Icon(Icons.flip), tooltip: '反选', onPressed: () => setState(() { final all = books.toSet(); final inverted = all.difference(_selectedBooks); _selectedBooks..clear()..addAll(inverted); })),
            IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() { _selectMode = false; _selectedBooks.clear(); })),
          ] else IconButton(icon: const Icon(Icons.more_vert), onPressed: _showMoreMenu),
        ],
        bottom: PreferredSize(preferredSize: const Size.fromHeight(48), child: _buildGroupTabs(provider)),
      ),
      body: _isUpdating ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [CircularProgressIndicator(), SizedBox(height: 16), Text('正在更新...')])) : books.isEmpty ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.menu_book_outlined, size: 64, color: Colors.grey[400]), const SizedBox(height: 16), Text('书架为空', style: TextStyle(color: Colors.grey[600], fontSize: 16)), const SizedBox(height: 8), Text('去搜索或发现页面添加书籍', style: TextStyle(color: Colors.grey[500])), const SizedBox(height: 24), FilledButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen())), icon: const Icon(Icons.search), label: const Text('去搜索'))])) : _buildBookList(books, layout),
      bottomNavigationBar: _selectMode ? SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Divider(height: 1),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _batchBtn(Icons.drive_file_move_outline, '移动分组', _batchMoveGroup),
          _batchBtn(Icons.cloud_download_outlined, '缓存', _batchCache),
          _batchBtn(Icons.file_upload_outlined, '导出', _batchExport),
          _batchBtn(Icons.delete_sweep_outlined, '删除', _batchDelete, danger: true),
        ]),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), child: Align(alignment: Alignment.centerLeft, child: Text('已选 ${_selectedBooks.length} 本', style: const TextStyle(fontSize: 12, color: Colors.grey)))),
      ])) : null,
    );
  }

  Widget _buildGroupTabs(BookProvider provider) => Container(height: 48, padding: const EdgeInsets.symmetric(horizontal: 8), child: ListView(scrollDirection: Axis.horizontal, children: [
    FilterChip(label: const Text('全部'), selected: provider.currentGroup == '全部', onSelected: (_) => provider.setCurrentGroup('全部')),
    const SizedBox(width: 8),
    ...provider.groups.where((g) => g != '全部').map((g) => Padding(padding: const EdgeInsets.only(right: 8), child: FilterChip(label: Text(g), selected: provider.currentGroup == g, onSelected: (_) => provider.setCurrentGroup(g)))),
  ]));

  Widget _buildBookList(List<Book> books, int layout) {
    switch (layout) {
      case 0: return ListView.separated(padding: const EdgeInsets.all(8), itemCount: books.length, separatorBuilder: (_, __) => const Divider(height: 1), itemBuilder: (context, index) => _buildListItem(books[index]));
      case 1: return ListView.separated(padding: const EdgeInsets.all(4), itemCount: books.length, separatorBuilder: (_, __) => const Divider(height: 1, indent: 72), itemBuilder: (context, index) => _buildCompactListItem(books[index]));
      case 2: return GridView.builder(padding: const EdgeInsets.all(8), gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 0.65, crossAxisSpacing: 8, mainAxisSpacing: 8), itemCount: books.length, itemBuilder: (context, index) => _buildGridItem(books[index], compact: false));
      case 3: return GridView.builder(padding: const EdgeInsets.all(4), gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, childAspectRatio: 0.6, crossAxisSpacing: 4, mainAxisSpacing: 4), itemCount: books.length, itemBuilder: (context, index) => _buildGridItem(books[index], compact: true));
      case 4: return GridView.builder(padding: const EdgeInsets.all(8), gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 0.6, crossAxisSpacing: 12, mainAxisSpacing: 12), itemCount: books.length, itemBuilder: (context, index) => _buildCoverItem(books[index]));
      default: return ListView.builder(itemCount: books.length, itemBuilder: (context, index) => _buildListItem(books[index]));
    }
  }

  Widget _buildListItem(Book book) {
    final selected = _selectedBooks.contains(book);
    return ListTile(
      leading: _buildCover(book, width: 50, height: 70),
      title: Text(book.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(book.author, maxLines: 1, style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 2),
        Text(book.lastChapter ?? '暂无章节', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.primary)),
      ]),
      trailing: _selectMode ? Checkbox(value: selected, onChanged: (_) => _toggleSelect(book)) : const Icon(Icons.chevron_right),
      selected: selected,
      onTap: () => _selectMode ? _toggleSelect(book) : Navigator.push(context, MaterialPageRoute(builder: (_) => ReadingScreen(book: book))),
      onLongPress: () => _selectMode ? _toggleSelect(book) : _showBookMenu(book),
    );
  }

  Widget _buildCompactListItem(Book book) {
    final selected = _selectedBooks.contains(book);
    return ListTile(
      dense: true,
      leading: _buildCover(book, width: 36, height: 50),
      title: Text(book.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
      subtitle: Text('${book.author} · ${book.lastChapter ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
      trailing: _selectMode ? Checkbox(value: selected, onChanged: (_) => _toggleSelect(book)) : null,
      selected: selected,
      onTap: () => _selectMode ? _toggleSelect(book) : Navigator.push(context, MaterialPageRoute(builder: (_) => ReadingScreen(book: book))),
      onLongPress: () => _selectMode ? _toggleSelect(book) : _showBookMenu(book),
    );
  }

  Widget _buildGridItem(Book book, {required bool compact}) {
    final selected = _selectedBooks.contains(book);
    return GestureDetector(
      onTap: () => _selectMode ? _toggleSelect(book) : Navigator.push(context, MaterialPageRoute(builder: (_) => ReadingScreen(book: book))),
      onLongPress: () => _selectMode ? _toggleSelect(book) : _showBookMenu(book),
      child: Container(decoration: selected ? BoxDecoration(border: Border.all(color: Theme.of(context).colorScheme.primary, width: 2), borderRadius: BorderRadius.circular(8)) : null, child: Column(children: [
        Expanded(child: _buildCover(book, width: double.infinity, height: double.infinity, radius: 8)),
        Padding(padding: EdgeInsets.all(compact ? 4 : 8), child: Text(book.name, maxLines: compact ? 1 : 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: compact ? 11 : 13))),
      ])),
    );
  }

  Widget _buildCoverItem(Book book) {
    final selected = _selectedBooks.contains(book);
    return GestureDetector(
      onTap: () => _selectMode ? _toggleSelect(book) : Navigator.push(context, MaterialPageRoute(builder: (_) => ReadingScreen(book: book))),
      onLongPress: () => _selectMode ? _toggleSelect(book) : _showBookMenu(book),
      child: Container(decoration: selected ? BoxDecoration(border: Border.all(color: Theme.of(context).colorScheme.primary, width: 3), borderRadius: BorderRadius.circular(12)) : null, child: ClipRRect(borderRadius: BorderRadius.circular(12), child: _buildCover(book, width: double.infinity, height: double.infinity, radius: 0))),
    );
  }

  Widget _buildCover(Book book, {required double width, required double height, double radius = 4}) {
    if (book.coverUrl != null && book.coverUrl!.isNotEmpty) {
      return ClipRRect(borderRadius: BorderRadius.circular(radius), child: Image.network(book.coverUrl!, width: width, height: height, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _buildDefaultCover(book, width, height, radius)));
    }
    return _buildDefaultCover(book, width, height, radius);
  }

  Widget _buildDefaultCover(Book book, double width, double height, double radius) {
    final colors = [Colors.blueGrey, Colors.brown, Colors.teal, Colors.indigo, Colors.deepOrange, Colors.purple];
    final color = colors[book.name.hashCode.abs() % colors.length];
    return Container(width: width, height: height, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(radius)), child: Center(child: Padding(padding: const EdgeInsets.all(4), child: Text(book.name, maxLines: 3, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)))));
  }


  Widget _batchBtn(IconData icon, String label, VoidCallback onTap, {bool danger = false}) {
    final color = danger ? Colors.red : null;
    return TextButton.icon(
      onPressed: _selectedBooks.isEmpty ? null : onTap,
      icon: Icon(icon, size: 20, color: color),
      label: Text(label, style: TextStyle(color: color, fontSize: 13)),
    );
  }

  Future<void> _batchMoveGroup() async {
    final provider = Provider.of<BookProvider>(context, listen: false);
    final groups = provider.groups.where((g) => g != '全部').toList();
    final controller = TextEditingController();
    if (!mounted) return;
    showDialog(context: context, builder: (context) => AlertDialog(
      title: const Text('移动到分组'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Wrap(spacing: 8, children: [
          for (final g in groups) ActionChip(label: Text(g), onPressed: () async {
            for (final b in _selectedBooks) { b.group = g; await _db.updateBook(b); }
            if (mounted) { Navigator.pop(context); await provider.loadBooks(); setState(() { _selectMode = false; _selectedBooks.clear(); }); }
          }),
          ActionChip(label: const Text('未分组'), onPressed: () async {
            for (final b in _selectedBooks) { b.group = null; await _db.updateBook(b); }
            if (mounted) { Navigator.pop(context); await provider.loadBooks(); setState(() { _selectMode = false; _selectedBooks.clear(); }); }
          }),
        ]),
        const SizedBox(height: 12),
        TextField(controller: controller, decoration: const InputDecoration(labelText: '新分组名称')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(onPressed: () async {
          final g = controller.text.trim();
          if (g.isEmpty) return;
          for (final b in _selectedBooks) { b.group = g; await _db.updateBook(b); }
          if (mounted) { Navigator.pop(context); await provider.loadBooks(); setState(() { _selectMode = false; _selectedBooks.clear(); }); }
        }, child: const Text('确定')),
      ],
    ));
  }

  Future<void> _batchCache() async {
    final picked = List.of(_selectedBooks);
    setState(() { _selectMode = false; _selectedBooks.clear(); });
    int totalOk = 0, totalFail = 0, done = 0;
    showDialog(context: context, barrierDismissible: false, builder: (d) => StatefulBuilder(builder: (d, setP) {
      _cacheBooksWithProgress(picked, (ok, fail, d2, t2) { setP(() { totalOk = ok; totalFail = fail; done = d2; }); });
      return AlertDialog(title: const Text('批量缓存'), content: Column(mainAxisSize: MainAxisSize.min, children: [
        LinearProgressIndicator(value: picked.isEmpty ? 0 : done / picked.length),
        const SizedBox(height: 12),
        Text('进度 $done/${picked.length}，成功 $totalOk 章，失败 $totalFail 章'),
      ]));
    }));
  }

  Future<void> _cacheOneBook(Book book) async {
    int ok = 0, fail = 0;
    showDialog(context: context, barrierDismissible: false, builder: (d) => const Center(child: Card(child: Padding(padding: EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(), SizedBox(height: 12), Text('正在缓存章节...')])))));
    final r = await _cacheBook(book);
    ok = r.ok; fail = r.fail;
    if (mounted) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('缓存完成: 成功$ok章${fail > 0 ? ', 失败$fail章' : ''}'))); }
  }

  /// 逐章缓存一本书，返回成功/失败计数
  Future<({int ok, int fail})> _cacheBook(Book book) async {
    int ok = 0, fail = 0;
    if (book.local || book.origin == null || book.noteUrl == null) return (ok: ok, fail: fail);
    final sources = await _db.getAllSources(enabled: true);
    final source = sources.where((s) => s.bookSourceUrl == book.origin).firstOrNull;
    if (source == null) return (ok: ok, fail: fail);
    final chapters = await _db.getChapters(book.name, book.author);
    final engine = BookSourceEngine();
    for (final ch in chapters) {
      if (ch.isVolume || (ch.content ?? '').isNotEmpty) continue;
      try {
        final content = await engine.getContent(source, ch.url);
        if (content != null && content.isNotEmpty) { await _db.updateChapterContent(book.name, book.author, ch.index, content); ok++; }
        else { fail++; }
      } catch (_) { fail++; }
    }
    return (ok: ok, fail: fail);
  }

  Future<void> _cacheBooksWithProgress(List<Book> books, void Function(int ok, int fail, int done, int total) onProgress) async {
    int ok = 0, fail = 0;
    for (var i = 0; i < books.length; i++) {
      final r = await _cacheBook(books[i]);
      ok += r.ok; fail += r.fail;
      onProgress(ok, fail, i + 1, books.length);
    }
    if (mounted) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('批量缓存完成: 成功$ok章${fail > 0 ? ', 失败$fail章' : ''}'))); }
  }

  Future<void> _batchDelete() async {
    final confirmed = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('删除书籍'), content: Text('确定删除选中的 ${_selectedBooks.length} 本书吗？'),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('删除'))],
    ));
    if (confirmed == true) {
      for (final book in _selectedBooks) { await _db.deleteBook(book.name, book.author); }
      if (mounted) { final p = Provider.of<BookProvider>(context, listen: false); await p.loadBooks(); setState(() { _selectMode = false; _selectedBooks.clear(); }); }
    }
  }

  Future<void> _batchExport() async {
    final picked = List.of(_selectedBooks);
    setState(() { _selectMode = false; _selectedBooks.clear(); });
    int ok = 0;
    for (final book in picked) {
      try {
        final chapters = await _db.getChapters(book.name, book.author);
        final buf = StringBuffer()
          ..writeln('《${book.name}》 作者:${book.author}')
          ..writeln(book.intro ?? '')
          ..writeln('\n');
        for (final ch in chapters) {
          buf.writeln(ch.title);
          buf.writeln(ch.content ?? '');
          buf.writeln('');
        }
        final file = File('${Directory.systemTemp.path}/${book.name}.txt');
        await file.writeAsString(buf.toString());
        await Share.shareXFiles([XFile(file.path)], text: '《${book.name}》导出');
        ok++;
      } catch (_) {}
    }
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已导出 $ok 本')));
  }

  void _toggleSelect(Book book) => setState(() => _selectedBooks.contains(book) ? _selectedBooks.remove(book) : _selectedBooks.add(book));
}
