import 'package:flutter/foundation.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/book_chapter.dart';
import 'package:legado_md3/data/model/read_config.dart';
import '../data/local/app_database.dart';

class BookProvider extends ChangeNotifier {
  final DatabaseService _db = DatabaseService();
  List<Book> _books = [];
  bool _isLoading = false;
  int _bookshelfLayout = 0; // 0:列表 1:网格 2:详细网格
  String _currentGroup = '全部';
  List<String> _groups = ['全部'];

  List<Book> get books => _books;
  bool get isLoading => _isLoading;
  int get bookshelfLayout => _bookshelfLayout;
  String get currentGroup => _currentGroup;
  List<String> get groups => _groups;

  List<Book> get filteredBooks {
    if (_currentGroup == '全部') return _books;
    return _books.where((b) => b.group == _currentGroup).toList();
  }

  Future<void> loadBooks() async {
    _isLoading = true;
    notifyListeners();
    _books = await _db.getAllBooks();
    _updateGroups();
    _isLoading = false;
    notifyListeners();
  }

  void _updateGroups() {
    final groupSet = <String>{'全部'};
    for (final b in _books) {
      if (b.group != null && b.group!.isNotEmpty) {
        groupSet.add(b.group!);
      }
    }
    _groups = groupSet.toList();
  }

  Future<void> addBook(Book book) async {
    await _db.insertBook(book);
    await loadBooks();
  }

  Future<void> updateBook(Book book) async {
    await _db.updateBook(book);
    final index = _books.indexWhere((b) => b.name == book.name && b.author == book.author);
    if (index != -1) {
      _books[index] = book;
      notifyListeners();
    }
  }

  Future<void> removeBook(String name, String author) async {
    await _db.deleteBook(name, author);
    await loadBooks();
  }

  void setBookshelfLayout(int layout) {
    _bookshelfLayout = layout;
    notifyListeners();
  }

  void setCurrentGroup(String group) {
    _currentGroup = group;
    notifyListeners();
  }

  Book? findBook(String name, String author) {
    try {
      return _books.firstWhere((b) => b.name == name && b.author == author);
    } catch (_) {
      return null;
    }
  }

  // 章节相关
  Future<List<BookChapter>> getChapters(Book book) async {
    return _db.getChapters(book.name, book.author);
  }

  Future<void> saveChapters(Book book, List<BookChapter> chapters) async {
    await _db.saveChapters(book.name, book.author, chapters);
  }

  Future<void> saveReadingProgress(Book book, int chapterIndex, int pos) async {
    book.durChapterIndex = chapterIndex;
    book.durChapterPos = pos;
    book.durChapterTime = DateTime.now().millisecondsSinceEpoch;
    await updateBook(book);
  }
}

class ReadProvider extends ChangeNotifier {
  ReadConfig _config = ReadConfig();
  bool _showMenu = false;
  double _brightness = 0.5;

  ReadConfig get config => _config;
  bool get showMenu => _showMenu;
  double get brightness => _brightness;

  void setConfig(ReadConfig config) {
    _config = config;
    notifyListeners();
  }

  void updateConfig(void Function(ReadConfig) updater) {
    updater(_config);
    notifyListeners();
  }

  void toggleMenu() {
    _showMenu = !_showMenu;
    notifyListeners();
  }

  void hideMenu() {
    _showMenu = false;
    notifyListeners();
  }

  void setBrightness(double value) {
    _brightness = value;
    notifyListeners();
  }

  void setTextSize(int size) {
    _config.textSize = size;
    notifyListeners();
  }

  void setBgColor(int color) {
    _config.bgColor = color;
    notifyListeners();
  }

  void setTextColor(int color) {
    _config.textColor = color;
    notifyListeners();
  }

  void setPageAnim(int anim) {
    _config.pageAnim = anim;
    notifyListeners();
  }

  void setLineSpacing(int spacing) {
    _config.lineSpacing = spacing;
    notifyListeners();
  }
}
