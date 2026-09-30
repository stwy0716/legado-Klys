import 'package:flutter/material.dart';
import 'package:legado_md3/data/model/homepage_module.dart';
import 'package:legado_md3/data/local/app_database.dart';

class HomepageManageScreen extends StatefulWidget {
  const HomepageManageScreen({super.key});
  @override
  State<HomepageManageScreen> createState() => _HomepageManageScreenState();
}

class _HomepageManageScreenState extends State<HomepageManageScreen> {
  final DatabaseService _db = DatabaseService();
  List<HomepageModule> _modules = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadModules();
  }

  Future<void> _loadModules() async {
    setState(() => _isLoading = true);
    final modules = await _db.getHomepageModules();
    setState(() { _modules = modules; _isLoading = false; });
  }

  Future<void> _showAddModuleDialog() async {
    final nameController = TextEditingController();
    HomepageModuleType selectedType = HomepageModuleType.banner;
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加模块'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameController, decoration: const InputDecoration(labelText: '模块名称')),
          const SizedBox(height: 16),
          DropdownButtonFormField<HomepageModuleType>(
            value: selectedType,
            decoration: const InputDecoration(labelText: '模块类型'),
            items: HomepageModuleType.values.map((t) => DropdownMenuItem(value: t, child: Text(_getTypeName(t)))).toList(),
            onChanged: (v) => selectedType = v ?? selectedType,
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(onPressed: () async {
            if (nameController.text.isEmpty) return;
            await _db.insertHomepageModule(HomepageModule(name: nameController.text, type: selectedType, customOrder: _modules.length));
            Navigator.pop(context);
            _loadModules();
          }, child: const Text('添加')),
        ],
      ),
    );
  }

  String _getTypeName(HomepageModuleType type) {
    switch (type) {
      case HomepageModuleType.banner: return '横幅';
      case HomepageModuleType.buttonGroup: return '按钮组';
      case HomepageModuleType.card: return '卡片';
      case HomepageModuleType.grid: return '网格';
      case HomepageModuleType.gridRanking: return '网格排行';
      case HomepageModuleType.ranking: return '排行榜';
      case HomepageModuleType.waterfall: return '瀑布流';
      case HomepageModuleType.custom: return '自定义';
    }
  }

  IconData _getTypeIcon(HomepageModuleType type) {
    switch (type) {
      case HomepageModuleType.banner: return Icons.image;
      case HomepageModuleType.buttonGroup: return Icons.smart_button;
      case HomepageModuleType.card: return Icons.credit_card;
      case HomepageModuleType.grid: return Icons.grid_view;
      case HomepageModuleType.gridRanking: return Icons.grid_on;
      case HomepageModuleType.ranking: return Icons.emoji_events;
      case HomepageModuleType.waterfall: return Icons.view_stream;
      case HomepageModuleType.custom: return Icons.settings;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('首页模块管理'), actions: [IconButton(icon: const Icon(Icons.add), onPressed: _showAddModuleDialog)]),
      body: _isLoading ? const Center(child: CircularProgressIndicator()) : _modules.isEmpty
          ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.dashboard_customize, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16), const Text('暂无模块', style: TextStyle(fontSize: 16)),
              const SizedBox(height: 8), const Text('点击右上角添加首页模块', style: TextStyle(color: Colors.grey)),
            ]))
          : ReorderableListView.builder(
              itemCount: _modules.length,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex--;
                  final module = _modules.removeAt(oldIndex);
                  _modules.insert(newIndex, module);
                  for (var i = 0; i < _modules.length; i++) { _modules[i].customOrder = i; _db.updateHomepageModule(_modules[i]); }
                });
              },
              itemBuilder: (context, index) {
                final module = _modules[index];
                return Card(key: ValueKey(module.id ?? index), margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: ListTile(
                    leading: Icon(_getTypeIcon(module.type)),
                    title: Text(module.name),
                    subtitle: Text(_getTypeName(module.type)),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      Switch(value: module.enabled, onChanged: (v) { setState(() => module.enabled = v); _db.updateHomepageModule(module); }),
                      IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () async { if (module.id != null) { await _db.deleteHomepageModule(module.id!); _loadModules(); } }),
                    ]),
                  ),
                );
              },
            ),
    );
  }
}
