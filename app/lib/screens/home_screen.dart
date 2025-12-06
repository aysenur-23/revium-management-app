/**
 * Ana ekran
 * 3 sekmeli yapı (Ekleme, Eklediklerim, Tüm Eklenenler)
 */

import 'package:flutter/material.dart';
import '../services/local_storage_service.dart';
import '../models/user_profile.dart';
import 'tabs/add_entry_tab.dart';
import 'tabs/my_entries_tab.dart';
import 'tabs/all_entries_tab.dart';

// UserProfile'ı export et (tab'lar için)
export '../models/user_profile.dart';
export '../models/expense_entry.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  UserProfile? _currentUser;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadUser();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadUser() async {
    try {
      final user = await LocalStorageService.getSavedUser();
      setState(() {
        _currentUser = user;
        _isLoading = false;
      });

      if (user == null) {
        // Kullanıcı yoksa login ekranına yönlendir
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/login');
        }
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kullanıcı yükleme hatası: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      );
    }

    if (_currentUser == null) {
      return const Scaffold(
        body: Center(
          child: Text('Kullanıcı bulunamadı'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: LayoutBuilder(
          builder: (context, constraints) {
            final theme = Theme.of(context);
            final showFullTitle = constraints.maxWidth > 400;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Logo - Daha iyi görünüm için container ile
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: theme.colorScheme.primary.withOpacity(0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Image.asset(
                    'assets/logo_header.png',
                    height: 28,
                    width: 28,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return Icon(
                        Icons.receipt_long,
                        size: 28,
                        color: theme.colorScheme.primary,
                      );
                    },
                  ),
                ),
                if (showFullTitle) ...[
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      'Harcama Takibi',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            );
          },
        ),
        elevation: 1,
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart),
            onPressed: () {
              Navigator.of(context).pushNamed('/statistics', arguments: _currentUser);
            },
            tooltip: 'İstatistikler',
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.of(context).pushNamed('/settings');
            },
            tooltip: 'Ayarlar',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelStyle: TextStyle(
            fontSize: MediaQuery.of(context).size.width < 600 ? 10 : 14,
          ),
          tabs: [
            if (MediaQuery.of(context).size.width >= 600)
              const Tab(
                icon: Icon(Icons.add),
                text: 'Ekleme',
              )
            else
              const Tab(
                icon: Icon(Icons.add),
              ),
            if (MediaQuery.of(context).size.width >= 600)
              const Tab(
                icon: Icon(Icons.list),
                text: 'Eklediklerim',
              )
            else
              const Tab(
                icon: Icon(Icons.list),
              ),
            if (MediaQuery.of(context).size.width >= 600)
              const Tab(
                icon: Icon(Icons.all_inclusive),
                text: 'Tüm Eklenenler',
              )
            else
              const Tab(
                icon: Icon(Icons.all_inclusive),
              ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          AddEntryTab(currentUser: _currentUser!),
          MyEntriesTab(currentUser: _currentUser!),
          const AllEntriesTab(),
        ],
      ),
    );
  }
}

