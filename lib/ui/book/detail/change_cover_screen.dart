import 'package:flutter/material.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/local/app_database.dart';

class ChangeCoverScreen extends StatefulWidget {
  final Book book;
  const ChangeCoverScreen({super.key, required this.book});

  @override
  State<ChangeCoverScreen> createState() => _ChangeCoverScreenState();
}

class _ChangeCoverScreenState extends State<ChangeCoverScreen> {
  final DatabaseService _db = DatabaseService();
  final TextEditingController _urlController = TextEditingController();
  String? _previewUrl;

  @override
  void initState() {
    super.initState();
    _urlController.text = widget.book.coverUrl ?? '';
    _previewUrl = _urlController.text;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('换封面 - ${widget.book.name}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Container(
              width: 150, height: 200,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), color: Colors.grey[200]),
              child: _previewUrl != null && _previewUrl!.isNotEmpty
                  ? ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(_previewUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 48)))
                  : const Icon(Icons.book, size: 48, color: Colors.grey),
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _urlController,
            decoration: const InputDecoration(labelText: '封面URL', border: OutlineInputBorder(), hintText: '输入图片URL'),
            onChanged: (v) => setState(() => _previewUrl = v),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => _urlController.clear(), child: const Text('清除自定义封面'))),
            const SizedBox(width: 16),
            Expanded(child: FilledButton(onPressed: _saveCover, child: const Text('保存'))),
          ]),
          const SizedBox(height: 24),
          const Text('预设封面', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _buildPresetCover('https://picsum.photos/seed/book1/300/400'),
            _buildPresetCover('https://picsum.photos/seed/book2/300/400'),
            _buildPresetCover('https://picsum.photos/seed/book3/300/400'),
            _buildPresetCover('https://picsum.photos/seed/book4/300/400'),
          ]),
        ],
      ),
    );
  }

  Widget _buildPresetCover(String url) {
    return GestureDetector(
      onTap: () {
        _urlController.text = url;
        setState(() => _previewUrl = url);
      },
      child: Container(width: 60, height: 80, decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), border: Border.all(color: _previewUrl == url ? Theme.of(context).colorScheme.primary : Colors.grey)), child: ClipRRect(borderRadius: BorderRadius.circular(4), child: Image.network(url, fit: BoxFit.cover))),
    );
  }

  Future<void> _saveCover() async {
    final updatedBook = Book(
      name: widget.book.name, author: widget.book.author,
      origin: widget.book.origin, originName: widget.book.originName,
      bookUrl: widget.book.bookUrl, coverUrl: _urlController.text.isEmpty ? null : _urlController.text,
      intro: widget.book.intro, kind: widget.book.kind,
      lastChapter: widget.book.lastChapter,
      latestChapterTime: widget.book.latestChapterTime,
      lastCheckTime: widget.book.lastCheckTime,
      order: widget.book.order,
    );
    await _db.updateBook(updatedBook);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('封面已更新')));
      Navigator.pop(context, true);
    }
  }
}
