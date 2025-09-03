import 'package:flutter/material.dart';
import '../domain/entities.dart';
import 'accounts_view.dart';
import 'inbox_view.dart';

/// Основной экран модуля "Почта" с вкладками и навигацией
class MailScreen extends StatefulWidget {
  const MailScreen({super.key});

  @override
  State<MailScreen> createState() => _MailScreenState();
}

class _MailScreenState extends State<MailScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  MailAccount? _selectedAccount;
  List<MailAccount> _accounts = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _loadAccounts();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAccounts() async {
    // TODO: Load accounts from repository
    setState(() {
      _accounts = [
        // Placeholder data
        MailAccount(
          uid: 'acc_1',
          provider: 'gmail',
          email: 'user@gmail.com',
          displayName: 'Личная почта',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ];
      if (_accounts.isNotEmpty) {
        _selectedAccount = _accounts.first;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Почта'),
        backgroundColor: Colors.grey[800],
        foregroundColor: Colors.white,
        actions: [
          // Account selector
          if (_accounts.isNotEmpty)
            PopupMenuButton<MailAccount>(
              icon: Icon(
                Icons.account_circle_outlined,
                color: Colors.amber,
              ),
              tooltip: 'Выбрать аккаунт',
              onSelected: (account) {
                setState(() {
                  _selectedAccount = account;
                });
              },
              itemBuilder: (context) => _accounts.map((account) {
                return PopupMenuItem(
                  value: account,
                  child: Row(
                    children: [
                      Icon(
                        _getProviderIcon(account.provider),
                        color: Colors.amber,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              account.displayName ?? account.email,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              account.email,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (account.isDefault)
                        Icon(
                          Icons.star,
                          color: Colors.amber,
                          size: 16,
                        ),
                    ],
                  ),
                );
              }).toList(),
            ),
          // Add account button
          IconButton(
            icon: const Icon(Icons.add_circle_outline, color: Colors.amber),
            tooltip: 'Добавить аккаунт',
            onPressed: () async {
              await _showAddAccountDialog();
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.amber,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.grey[400],
          tabs: const [
            Tab(text: 'Входящие', icon: Icon(Icons.inbox_outlined)),
            Tab(text: 'Отправленные', icon: Icon(Icons.send_outlined)),
            Tab(text: 'Черновики', icon: Icon(Icons.drafts_outlined)),
            Tab(text: 'Архив', icon: Icon(Icons.archive_outlined)),
            Tab(text: 'Спам', icon: Icon(Icons.report_outlined)),
            Tab(text: 'Корзина', icon: Icon(Icons.delete_outline)),
          ],
        ),
      ),
      body: _selectedAccount == null
          ? _buildNoAccountsView()
          : TabBarView(
              controller: _tabController,
              children: [
                InboxView(account: _selectedAccount!),
                _buildPlaceholderView('Отправленные'),
                _buildPlaceholderView('Черновики'),
                _buildPlaceholderView('Архив'),
                _buildPlaceholderView('Спам'),
                _buildPlaceholderView('Корзина'),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _selectedAccount == null ? null : _composeMessage,
        backgroundColor: Colors.amber,
        foregroundColor: Colors.black,
        child: const Icon(Icons.edit),
      ),
    );
  }

  Widget _buildNoAccountsView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.mail_outlined,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'Нет подключенных аккаунтов',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[400],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Добавьте почтовый аккаунт для начала работы',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
                      ElevatedButton.icon(
              onPressed: _showAddAccountDialog,
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('Добавить аккаунт'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber,
              foregroundColor: Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholderView(String title) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.folder_outlined,
            size: 48,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[400],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Функция в разработке',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  IconData _getProviderIcon(String provider) {
    switch (provider.toLowerCase()) {
      case 'gmail':
        return Icons.mail_outline;
      case 'outlook':
        return Icons.business_outlined;
      case 'yandex':
        return Icons.language_outlined;
      case 'mailru':
        return Icons.web_outlined;
      case 'imap':
        return Icons.dns_outlined;
      default:
        return Icons.mail_outline;
    }
  }

  Future<void> _showAddAccountDialog() async {
    await showDialog(
      context: context,
      builder: (context) => const AddAccountDialog(),
    );
    _loadAccounts(); // Reload accounts after dialog
  }

  void _composeMessage() {
    // TODO: Navigate to compose screen
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Функция создания письма в разработке'),
        backgroundColor: Colors.amber,
      ),
    );
  }
}

/// Диалог добавления аккаунта
class AddAccountDialog extends StatefulWidget {
  const AddAccountDialog({super.key});

  @override
  State<AddAccountDialog> createState() => _AddAccountDialogState();
}

class _AddAccountDialogState extends State<AddAccountDialog> {
  String _selectedProvider = 'gmail';
  final _emailController = TextEditingController();
  final _displayNameController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Добавить аккаунт'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Provider selection
            DropdownButtonFormField<String>(
              value: _selectedProvider,
              decoration: const InputDecoration(
                labelText: 'Провайдер',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'gmail', child: Text('Gmail')),
                DropdownMenuItem(value: 'outlook', child: Text('Outlook/Office 365')),
                DropdownMenuItem(value: 'yandex', child: Text('Яндекс.Почта')),
                DropdownMenuItem(value: 'mailru', child: Text('Mail.ru')),
                DropdownMenuItem(value: 'imap', child: Text('IMAP/SMTP')),
              ],
              onChanged: (value) {
                setState(() {
                  _selectedProvider = value!;
                });
              },
            ),
            const SizedBox(height: 16),
            // Email field
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            // Display name field
            TextField(
              controller: _displayNameController,
              decoration: const InputDecoration(
                labelText: 'Отображаемое имя (необязательно)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
                    ElevatedButton.icon(
              onPressed: _addAccount,
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('Добавить'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
                foregroundColor: Colors.black,
              ),
            ),
      ],
    );
  }

  void _addAccount() {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Введите email'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // TODO: Implement account addition
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Добавление аккаунта $email в разработке'),
        backgroundColor: Colors.amber,
      ),
    );
  }
}
