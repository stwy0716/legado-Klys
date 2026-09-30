import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/rss_article.dart';

/// RSS文章阅读页面 - 对齐原版RssReadScreen
class RssReadScreen extends StatefulWidget {
  final RssArticle article;
  const RssReadScreen({super.key, required this.article});

  @override
  State<RssReadScreen> createState() => _RssReadScreenState();
}

class _RssReadScreenState extends State<RssReadScreen> {
  final _db = DatabaseService();
  late RssArticle _article;
  bool _isFavorite = false;
  double _fontSize = 18;

  @override
  void initState() {
    super.initState();
    _article = widget.article;
    _isFavorite = _article.favorite == 1;
  }

  Future<void> _toggleFavorite() async {
    setState(() => _isFavorite = !_isFavorite);
    if (_article.id != null) {
      await _db.toggleRssFavorite(_article.id!, _isFavorite ? 1 : 0);
    }
  }

  void _showTextMenu() {
    showModalBottomSheet(context: context, builder: (context) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(
        leading: const Icon(Icons.text_increase), title: const Text('增大字体'),
        onTap: () { setState(() => _fontSize = (_fontSize + 2).clamp(12, 36)); Navigator.pop(context); },
      ),
      ListTile(
        leading: const Icon(Icons.text_decrease), title: const Text('减小字体'),
        onTap: () { setState(() => _fontSize = (_fontSize - 2).clamp(12, 36)); Navigator.pop(context); },
      ),
      ListTile(
        leading: const Icon(Icons.copy), title: const Text('复制全文'),
        onTap: () { Clipboard.setData(ClipboardData(text: '${_article.title}\n\n${_article.description ?? ''}')); Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制'))); },
      ),
      ListTile(
        leading: const Icon(Icons.open_in_browser), title: const Text('浏览器打开'),
        onTap: () { Navigator.pop(context); launchUrl(Uri.parse(_article.link), mode: LaunchMode.externalApplication); },
      ),
    ])));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_article.sourceName ?? '文章', maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: Icon(_isFavorite ? Icons.star : Icons.star_border),
            onPressed: _toggleFavorite,
          ),
          IconButton(icon: const Icon(Icons.text_fields), onPressed: _showTextMenu),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'browser') launchUrl(Uri.parse(_article.link), mode: LaunchMode.externalApplication);
              if (v == 'share') Share.share('${_article.title}\n${_article.link}');
              if (v == 'copy_link') { Clipboard.setData(ClipboardData(text: _article.link)); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('链接已复制'))); }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'browser', child: Text('浏览器打开')),
              PopupMenuItem(value: 'share', child: Text('分享')),
              PopupMenuItem(value: 'copy_link', child: Text('复制链接')),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_article.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, height: 1.4)),
          const SizedBox(height: 12),
          Row(children: [
            if (_article.author != null) ...[
              Icon(Icons.person_outline, size: 14, color: Colors.grey[600]),
              const SizedBox(width: 4),
              Text(_article.author!, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              const SizedBox(width: 12),
            ],
            Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
            const SizedBox(width: 4),
            Text(_article.pubDate != null ? DateTime.fromMillisecondsSinceEpoch(_article.pubDate!).toString().substring(0, 16) : '', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ]),
          const Divider(height: 24),
          if (_article.description != null)
            Text(_article.description!, style: TextStyle(fontSize: _fontSize, height: 1.8)),
          if (_article.content != null && _article.content!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(_article.content!, style: TextStyle(fontSize: _fontSize, height: 1.8)),
          ],
          const SizedBox(height: 24),
          if (_article.link.isNotEmpty)
            Center(child: TextButton.icon(
              onPressed: () => launchUrl(Uri.parse(_article.link), mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.open_in_browser), label: const Text('阅读原文'),
            )),
          const SizedBox(height: 40),
        ]),
      ),
    );
  }
}
