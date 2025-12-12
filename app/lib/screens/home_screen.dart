/**
 * Ana ekran
 * 4 sekmeli yapı (Ekleme, Eklediklerim, Tüm Eklenenler, Sabit Giderler)
 */

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/local_storage_service.dart';
import '../services/firestore_service.dart';
import '../models/user_profile.dart';
import 'tabs/add_entry_tab.dart';
import 'tabs/my_entries_tab.dart';
import 'tabs/all_entries_tab.dart';
import 'tabs/fixed_expenses_tab.dart';

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
    _tabController = TabController(length: 4, vsync: this);
    _loadUser();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadUser() async {
    try {
      // Önce lokal kullanıcıyı hızlıca yükle (UI'ı hemen göster)
      final user = await LocalStorageService.getSavedUser();
      
      // UI'ı hemen göster (kullanıcı varsa)
      if (user != null) {
        setState(() {
          _currentUser = user;
          _isLoading = false;
        });
        // Firestore'dan güncel bilgileri arka planda yükle (non-blocking)
        _refreshUserInBackground();
        return;
      }
      
      // Eğer lokal kullanıcı yoksa, Firebase Auth'tan kontrol et
      try {
        final firebaseAuth = FirebaseAuth.instance;
        final currentUser = firebaseAuth.currentUser;
        
        if (currentUser != null) {
          // Önce UI'ı göster (displayName ile)
          setState(() {
            _currentUser = UserProfile(
              userId: currentUser.uid,
              fullName: currentUser.displayName ?? 'Kullanıcı',
            );
            _isLoading = false;
          });
          
          // Firestore'dan tam bilgileri arka planda yükle (non-blocking)
          _refreshUserInBackground();
          return;
        }
      } catch (e) {
        // Firebase kontrolü başarısız, devam et
      }
      
      setState(() {
        _currentUser = user;
        _isLoading = false;
      });

      // Kullanıcı hala null ise login ekranına yönlendir (delay kaldırıldı - performans için)
      if (user == null && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            try {
              final navigator = Navigator.of(context, rootNavigator: true);
              final currentRoute = ModalRoute.of(context)?.settings.name;
              if (currentRoute != '/login') {
                navigator.pushNamedAndRemoveUntil('/login', (route) => false);
              }
            } catch (e) {
              // Hata durumunda sessizce devam et
            }
          }
        });
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
        // Hata durumunda da login'e yönlendir (delay kaldırıldı - performans için)
        if (mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              try {
                Navigator.of(context, rootNavigator: true)
                    .pushNamedAndRemoveUntil('/login', (route) => false);
              } catch (e2) {
                // Hata durumunda sessizce devam et
              }
            }
          });
        }
      }
    }
  }

  /// Kullanıcı bilgilerini arka planda Firestore'dan yeniler (non-blocking)
  Future<void> _refreshUserInBackground() async {
    try {
      final firebaseAuth = FirebaseAuth.instance;
      final currentUser = firebaseAuth.currentUser;
      
      if (currentUser != null && mounted) {
        // Firestore'dan bilgileri al (timeout ile)
        Map<String, dynamic>? userDoc;
        try {
          userDoc = await FirestoreService.getUser(currentUser.uid)
              .timeout(const Duration(seconds: 5));
        } catch (e) {
          // Timeout veya hata durumunda null döndür
          userDoc = null;
        }
        
        if (userDoc != null && mounted) {
          final fullName = userDoc['fullName'] as String? ?? currentUser.displayName ?? 'Kullanıcı';
          
          // Lokal olarak kaydet
          await LocalStorageService.saveUser(currentUser.uid, fullName);
          
          // UI'ı güncelle
          if (mounted) {
            setState(() {
              _currentUser = UserProfile(userId: currentUser.uid, fullName: fullName);
            });
          }
        }
      }
    } catch (e) {
      // Arka plan güncellemesi hatası önemli değil, sessizce devam et
      // Kullanıcı zaten UI'ı görebiliyor
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
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.person_off_rounded,
                size: 64,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                'Kullanıcı bulunamadı',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Lütfen giriş yapın',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context, rootNavigator: true)
                      .pushNamedAndRemoveUntil('/login', (route) => false);
                },
                icon: const Icon(Icons.login_rounded),
                label: const Text('Giriş Yap'),
              ),
            ],
          ),
        ),
      );
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      extendBodyBehindAppBar: false,
      appBar: AppBar(
        toolbarHeight: 110,
        systemOverlayStyle: null,
        centerTitle: false,
        title: Image.asset(
          'assets/logo_header.png',
          height: 85,
          width: 85,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return Icon(
              Icons.receipt_long_rounded,
              size: 64,
              color: theme.colorScheme.primary,
            );
          },
        ),
        titleSpacing: 16,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart_rounded, size: 22),
            onPressed: _currentUser != null ? () async {
              try {
                final result = await Navigator.of(context).pushNamed(
                  '/statistics',
                  arguments: _currentUser,
                );
                if (result != null && mounted) {
                  _tabController.animateTo(2);
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('İstatistikler açılamadı: ${e.toString()}'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            } : null,
            tooltip: 'İstatistikler',
          ),
          IconButton(
            icon: const Icon(Icons.settings_rounded, size: 22),
            onPressed: () => Navigator.of(context).pushNamed('/settings'),
            tooltip: 'Ayarlar',
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              border: Border(
                bottom: BorderSide(
                  color: theme.colorScheme.outline.withValues(alpha: 0.08),
                  width: 1,
                ),
              ),
            ),
            child: TabBar(
              controller: _tabController,
              labelStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              labelPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
              ),
              indicatorPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              labelColor: theme.colorScheme.primary,
              unselectedLabelColor: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              tabs: const [
                Tab(
                  icon: Icon(Icons.add_circle_outline_rounded, size: 20),
                  text: 'Ekleme',
                ),
                Tab(
                  icon: Icon(Icons.list_alt_rounded, size: 20),
                  text: 'Eklediklerim',
                ),
                Tab(
                  icon: Icon(Icons.dashboard_rounded, size: 20),
                  text: 'Tümü',
                ),
                Tab(
                  icon: Icon(Icons.receipt_long_rounded, size: 20),
                  text: 'Sabit',
                ),
              ],
            ),
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        bottom: true,
        child: TabBarView(
          controller: _tabController,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            AddEntryTab(currentUser: _currentUser!),
            MyEntriesTab(currentUser: _currentUser!),
            AllEntriesTab(currentUser: _currentUser),
            FixedExpensesTab(currentUser: _currentUser),
          ],
        ),
      ),
    );
  }
}

