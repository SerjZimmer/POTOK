import 'package:flutter/material.dart';
import '../data/api_repository.dart';
import '../data/logger.dart';
import 'issue_detail_screen.dart';

class ArchivedIssuesScreen extends StatefulWidget {
  const ArchivedIssuesScreen({super.key});

  @override
  State<ArchivedIssuesScreen> createState() => _ArchivedIssuesScreenState();
}

class _ArchivedIssuesScreenState extends State<ArchivedIssuesScreen> {
  final repo = BoardsApiRepository();
  List<Map<String, dynamic>> _archived = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadArchived();
  }

  Future<void> _loadArchived() async {
    setState(() => _isLoading = true);
    try {
      final items = await repo.listArchivedIssues();
      if (mounted) {
        setState(() {
          _archived = items;
          _isLoading = false;
        });
      }
    } catch (e) {
      BoardsLogger.error('Failed to load archived issues', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки архива: $e'), backgroundColor: Colors.red),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _confirmDelete(String id, String summary) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить задачу?'),
        content: Text('Вы уверены, что хотите навсегда удалить задачу "$summary"? Это действие нельзя отменить.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await repo.deleteArchivedIssue(id);
        BoardsLogger.info('Задача удалена из архива', ctx: {'id': id});
        if (mounted) {
          setState(() {
            _archived.removeWhere((issue) => issue['id'] == id);
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Задача удалена')),
          );
        }
      } catch (e) {
        BoardsLogger.error('Не удалось удалить задачу из архива', error: e, ctx: {'id': id});
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Архив задач'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadArchived,
              child: ListView.builder(
                itemCount: _archived.length,
                itemBuilder: (_, i) {
                  final issue = _archived[i];
                  final summary = issue['summary']?.toString() ?? 'Без названия';
                  final id = issue['id']?.toString() ?? '';
                  return ListTile(
                    title: Text(summary),
                    subtitle: Text('Board: ${issue['board_id']} / Column: ${issue['column_id']}'), // Example subtitle
                    onTap: () {
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => IssueDetailScreen(issueId: id, repo: repo, isArchived: true)));
                    },
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_forever_outlined, color: Colors.redAccent),
                      tooltip: 'Удалить навсегда',
                      onPressed: () => _confirmDelete(id, summary),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
