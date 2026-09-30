import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:legado_md3/constant/app_constants.dart';
import 'package:legado_md3/help/storage/crash_log_helper.dart';

/// 软件信息页（对齐原版 MiuixAboutScreen：Logo + 版本 + 卡片分组）
class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  bool _checking = false;

  Future<void> _checkUpdate() async {
    if (_checking) return;
    setState(() => _checking = true);
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('正在检查更新...')));
    try {
      final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 10), receiveTimeout: const Duration(seconds: 15)));
      final resp = await dio.get('https://api.github.com/repos/stwy0716/legado-Klys/releases/latest');
      final tag = (resp.data['tag_name'] ?? '').toString();
      final body = (resp.data['body'] ?? '').toString();
      final htmlUrl = (resp.data['html_url'] ?? 'https://github.com/stwy0716/legado-Klys/releases').toString();
      final latest = tag.replaceAll(RegExp(r'[^0-9.]'), '').split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final cur = AppConstants.appVersion.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      bool hasNew = false;
      for (var i = 0; i < 3; i++) {
        final l = i < latest.length ? latest[i] : 0;
        final c = i < cur.length ? cur[i] : 0;
        if (l > c) { hasNew = true; break; }
        if (l < c) break;
      }
      if (!mounted) return;
      if (hasNew) {
        showDialog(context: context, builder: (d) => AlertDialog(
          title: Text('发现新版本 $tag'),
          content: Text(body.isEmpty ? '是否前往下载最新版本？' : body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: const Text('稍后')),
            FilledButton(onPressed: () { Navigator.pop(d); launchUrl(Uri.parse(htmlUrl), mode: LaunchMode.externalApplication); }, child: const Text('前往下载')),
          ],
        ));
      } else {
        messenger.showSnackBar(const SnackBar(content: Text('当前已是最新版本')));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('检查更新失败: $e')));
    }
    if (mounted) setState(() => _checking = false);
  }

  Future<void> _showCrashLog() async {
    final logs = await CrashLogHelper.instance.readLogs();
    if (!mounted) return;
    showDialog(context: context, builder: (c) => AlertDialog(
      title: const Text('崩溃日志'),
      content: SizedBox(
        width: double.maxFinite,
        child: logs.trim().isEmpty
            ? const Text('暂无崩溃日志', style: TextStyle(color: Colors.grey))
            : SingleChildScrollView(child: SelectableText(logs, style: const TextStyle(fontSize: 11, fontFamily: 'monospace'))),
      ),
      actions: [
        if (logs.trim().isNotEmpty) TextButton(onPressed: () async { await CrashLogHelper.instance.clear(); if (mounted) { Navigator.pop(c); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已清空崩溃日志'))); } }, child: const Text('清空')),
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('关闭')),
      ],
    ));
  }

  void _showInfoDialog(String title, String content) {
    showDialog(context: context, builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(content),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('关闭'))],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('软件信息')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // 顶部 Logo + 应用名 + 版本
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
            child: Column(children: [
              Container(
                width: 88, height: 88,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Icon(Icons.menu_book, size: 48, color: theme.colorScheme.primary),
              ),
              const SizedBox(height: 16),
              const Text('legado', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text('版本 ${AppConstants.appVersion}（${AppConstants.appVersionCode}）',
                  style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 8),
              Text('Material You 风格开源阅读器，支持书源/书架/订阅/朗读',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: theme.colorScheme.outline)),
            ]),
          ),

          // 更新
          _buildGroupCard('更新', [
            _buildItem(Icons.update, '检查更新', '检查 GitHub 最新版本', () => _checkUpdate()),
          ]),

          // 项目
          _buildGroupCard('项目', [
            _buildItem(Icons.download, '下载正式版', 'GitHub Releases 安装包', () => launchUrl(Uri.parse('https://github.com/stwy0716/legado-Klys/releases/latest'), mode: LaunchMode.externalApplication)),
            _buildItem(Icons.code, 'GitHub 项目', 'legado-Klys 源码仓库', () => launchUrl(Uri.parse('https://github.com/stwy0716/legado-Klys'), mode: LaunchMode.externalApplication)),
            _buildItem(Icons.gavel, '开源协议', 'GNU General Public License v3.0', () => _showInfoDialog('开源协议', 'GNU General Public License v3.0\n\n本应用基于开源项目 Legado 重构，遵循 GPLv3 协议开放源代码。')),
            _buildItem(Icons.people_outline, '贡献者', 'Legado 开源社区', () => _showInfoDialog('贡献者', 'Legado 开源社区\n\n感谢所有贡献者的支持。')),
          ]),

          // 信息
          _buildGroupCard('信息', [
            _buildItem(Icons.privacy_tip_outlined, '隐私政策', '所有数据仅存储于本地设备', () => _showInfoDialog('隐私政策', '本应用不会收集任何个人信息，所有数据均存储在本地设备上。')),
            _buildItem(Icons.warning_amber_outlined, '免责声明', '仅供学习交流使用', () => _showInfoDialog('免责声明', '本应用仅供学习交流使用，不提供任何书籍内容，所有书源均由用户自行添加。')),
            _buildItem(Icons.bug_report, '崩溃日志', '查看或清空本地日志', () => _showCrashLog()),
          ]),

          const SizedBox(height: 24),
          Center(child: Text('Copyright © 2026 Legado MD3',
              style: TextStyle(fontSize: 11, color: theme.colorScheme.outline))),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildGroupCard(String title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Text(title,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.primary)),
        ),
        Card(
          margin: EdgeInsets.zero,
          elevation: 0,
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) Divider(height: 1, indent: 56, color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.3)),
              children[i],
            ],
          ]),
        ),
      ]),
    );
  }

  Widget _buildItem(IconData icon, String title, String subtitle, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, size: 22),
      title: Text(title, style: const TextStyle(fontSize: 15)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: onTap,
    );
  }
}
