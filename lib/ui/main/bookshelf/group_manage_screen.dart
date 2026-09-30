import 'package:flutter/material.dart';
import 'package:legado_md3/data/model/book_group.dart';
import 'package:legado_md3/data/local/app_database.dart';

class GroupManageScreen extends StatefulWidget {
  const GroupManageScreen({super.key});

  @override
  State<GroupManageScreen> createState() => _GroupManageScreenState();
}

class _GroupManageScreenState extends State<GroupManageScreen> {
  final DatabaseService _db = DatabaseService();
  List<BookGroup> _groups = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadGroups();
  }

  Future<void> _loadGroups() async {
    final groups = await _db.getBookGroups();
    setState(() {
      _groups = groups;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('分组管理'),
        actions: [IconButton(icon: const Icon(Icons.add), onPressed: _showAddGroup)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _groups.isEmpty
              ? const Center(child: Text('暂无分组，点击右上角添加'))
              : ReorderableListView.builder(
                  itemCount: _groups.length,
                  onReorder: (oldIndex, newIndex) async {
                    if (newIndex > oldIndex) newIndex--;
                    setState(() {
                      final group = _groups.removeAt(oldIndex);
                      _groups.insert(newIndex, group);
                    });
                    for (var i = 0; i < _groups.length; i++) {
                      await _db.insertBookGroup(BookGroup(id: _groups[i].id, name: _groups[i].name, order: i, show: _groups[i].show));
                    }
                  },
                  itemBuilder: (context, index) {
                    final group = _groups[index];
                    return Card(
                      key: ValueKey(group.id),
                      child: ListTile(
                        leading: const Icon(Icons.folder_outlined),
                        title: Text(group.name),
                        subtitle: Text('排序: ${group.order}'),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          Switch(value: group.show == 1, onChanged: (v) => _toggleShow(group, v)),
                          IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => _deleteGroup(group)),
                        ]),
                      ),
                    );
                  },
                ),
    );
  }

  void _showAddGroup() {
    final controller = TextEditingController();
    showDialog(context: context, builder: (context) => AlertDialog(
      title: const Text('新建分组'),
      content: TextField(controller: controller, decoration: const InputDecoration(labelText: '分组名称', border: OutlineInputBorder()), autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(onPressed: () async {
          if (controller.text.isNotEmpty) {
            await _db.insertBookGroup(BookGroup(name: controller.text, order: _groups.length));
            Navigator.pop(context);
            _loadGroups();
          }
        }, child: const Text('创建')),
      ],
    ));
  }

  Future<void> _toggleShow(BookGroup group, bool show) async {
    final updated = BookGroup(id: group.id, name: group.name, order: group.order, show: show ? 1 : 0, cover: group.cover);
    await _db.insertBookGroup(updated);
    _loadGroups();
  }

  Future<void> _deleteGroup(BookGroup group) async {
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('删除分组'),
      content: Text('确定要删除分组「${group.name}」吗？'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除'))],
    ));
    if (confirmed == true && group.id != null) {
      await _db.deleteBookGroup(group.id!);
      _loadGroups();
    }
  }
}
