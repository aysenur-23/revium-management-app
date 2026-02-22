/// Ana ekran
/// 4 sekmeli yapı (Ekleme, Eklediklerim, Tüm Eklenenler, Sabit Giderler)
library;

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../main.dart';
import '../config/app_config.dart';
import '../services/local_storage_service.dart';
import '../services/firestore_service.dart';
import '../models/user_profile.dart';
import 'tabs/add_entry_tab.dart';
import 'tabs/my_entries_tab.dart';
import 'tabs/all_entries_tab.dart';
import 'tabs/fixed_expenses_tab.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/upload_service.dart';
import '../utils/app_logger.dart';

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
  final Map<String, String> _sheetUrls = {}; // URL'leri cache'le (anlık açılış için)

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {}); // Tab değiştiğinde UI'ı (AppBar butonunu) güncelle
      }
    });
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

          // Arka planda Sheets dosyalarını tam senkronize et (Her açılışta güncel olsun)
          _syncAllSheetsInBackground(fullName);
          
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

  /// Tüm Excel dosyalarını arka planda günceller (Initial Sync)
  Future<void> _syncAllSheetsInBackground(String currentUserName) async {
    try {
      AppLogger.info('🚀 Full Excel Sync Başlatılıyor (Sıralı)...');
      
      // 1. Verileri Çek
      final allEntries = await FirestoreService.getAllEntries();
      final allEntriesMap = allEntries.map((e) => e.toMap()).toList();

      final allFixed = await FirestoreService.getAllFixedExpenses(); // Sabit giderler
      final allFixedMap = allFixed.map((e) => e.toJson()).toList();
      AppLogger.info('📊 Firestore\'dan ${allEntries.length} kayıt ve ${allFixed.length} sabit gider çekildi.');

      // API Rate Limit (Kota) sorununu önlemek için İŞLEMLERİ SIRAYLA ve BEKLEYEREK yap
      // Her işlem arasına küçük bir gecikme ekle

      // 2. "Tum Eklenenler" güncelle
      if (allEntriesMap.isNotEmpty) {
        try {
          final result = await UploadService.createAllEntriesExcel(allEntriesMap);
          if (result != null && result['url'] != null) {
            if (mounted) {
              setState(() {
                _sheetUrls['all_entries'] = result['url'].toString();
              });
            }
          }
        } catch (e) {
           AppLogger.error('Sync Error (Tum Eklenenler)', e);
        }
        await Future.delayed(const Duration(milliseconds: 500)); // Rate limit koruması
      } else {
        AppLogger.warning('⚠️ Tum Eklenenler sync geçildi (Veri yok)');
      }
      
      // Sabit giderler ID'si zaten biliniyor
      if (mounted) {
        setState(() {
          _sheetUrls['fixed_expenses'] = 'https://docs.google.com/spreadsheets/d/${AppConfig.googleSheetsFixedExpensesId}/edit';
        });
      }

      // 3. "Sabit Giderler" güncelle
      final fixedExpensesOnly = allFixedMap.where((e) => !(e['category']?.toString().toLowerCase().contains('gelir') ?? false)).toList();
      if (fixedExpensesOnly.isNotEmpty) {
        try {
          final result = await UploadService.initializeGoogleSheetsWithFixedExpenses(fixedExpensesOnly);
          if (result != null && result['url'] != null) {
            if (mounted) {
              setState(() {
                 _sheetUrls['fixed_expenses'] = result['url'].toString();
              });
            }
          }
        } catch (e) {
           AppLogger.error('Sync Error (Sabit Giderler)', e);
        }
        await Future.delayed(const Duration(milliseconds: 500));
      } else {
        AppLogger.warning('⚠️ Sabit Giderler sync geçildi (Veri yok)');
      }

      // 3.5 "Sabit Gelirler" güncelle (Yeni)
      final fixedIncomesOnly = allFixedMap.where((e) => (e['category']?.toString().toLowerCase().contains('gelir') ?? false)).toList();
      if (fixedIncomesOnly.isNotEmpty) {
        try {
          final result = await UploadService.initializeGoogleSheetsWithAllData(
            entries: [], 
            fixedExpenses: fixedIncomesOnly, 
            sheetName: 'Sabit Gelirler'
          );
          if (result != null && result['url'] != null) {
            if (mounted) {
              setState(() {
                _sheetUrls['fixed_incomes'] = result['url'].toString();
              });
            }
          }
        } catch (e) {
           AppLogger.error('Sync Error (Sabit Gelirler)', e);
        }
        await Future.delayed(const Duration(milliseconds: 500));
      }

      // 4. "Ortak Gelirleri" güncelle
      final incomeEntries = allEntriesMap.where((e) => e['entryType'] == 'income').toList();
      if (incomeEntries.isNotEmpty) {
        try {
          final result = await UploadService.createIncomeEntriesExcel(incomeEntries);
          if (result != null && result['url'] != null) {
            if (mounted) {
               setState(() {
                 _sheetUrls['partner_incomes'] = result['url'].toString();
               });
            }
          }
        } catch (e) {
           AppLogger.error('Sync Error (Ortak Gelirleri)', e);
        }
        await Future.delayed(const Duration(milliseconds: 500));
      }

      // 4.5 "Vergiden Düşülecekler" güncelle (ortak gelirden ayrı)
      final taxDeductibleEntries = allEntriesMap.where((e) => e['entryType'] == 'tax_deductible').toList();
      if (taxDeductibleEntries.isNotEmpty) {
        try {
          final result = await UploadService.createTaxDeductibleEntriesExcel(taxDeductibleEntries);
          if (result != null && result['url'] != null) {
            if (mounted) {
              setState(() {
                _sheetUrls['tax_deductible'] = result['url'].toString();
              });
            }
          }
        } catch (e) {
          AppLogger.error('Sync Error (Vergiden Düşülecekler)', e);
        }
        await Future.delayed(const Duration(milliseconds: 500));
      }

      // 5. Kişi Bazlı Dosyalar ("Ali Eklediklerim" vb.) — her kişi sadece kendi tablosunu görsün
      final ownerNames = allEntries.map((e) => e.ownerName).toSet();
      ownerNames.add(currentUserName); // Mevcut kullanıcıyı kesin ekle

      final currentUserId = _currentUser?.userId ?? '';
      for (final name in ownerNames) {
        if (name.trim().isEmpty) continue;
        final userEntries = allEntriesMap.where((e) {
          final owner = (e['ownerName'] as String? ?? '').trim();
          return owner == name.trim();
        }).toList();
        
        if (userEntries.isNotEmpty) {
          try {
            final result = await UploadService.createMyEntriesExcel(userEntries, name.trim());
            if (result != null && result['url'] != null && name.trim() == currentUserName.trim() && mounted) {
              setState(() {
                _sheetUrls['my_entries_$currentUserId'] = result['url'].toString();
              });
            }
          } catch (e) {
             AppLogger.error('Sync Error ($name)', e);
          }
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
      
      AppLogger.success('✅ Full Excel Sync Tamamlandı (Sıralı)');
    } catch (e) {
      AppLogger.error('❌ Full Excel Sync Genel Hatası', e);
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
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
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
            if (_currentUser != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'Giriş: ${_currentUser!.fullName}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.7),
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ),
        titleSpacing: 16,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(
              Icons.table_chart_outlined, 
              size: 20,
              color: _currentUser == null ? null : theme.colorScheme.primary,
            ),
            onPressed: _currentUser != null ? () {
              switch (_tabController.index) {
                case 0:
                  _showExportMenu(context);
                  break;
                case 1:
                  _handleExportAction(context, 'my_entries');
                  break;
                case 2:
                  _showExportMenu(context);
                  break;
                case 3:
                  _handleExportAction(context, 'fixed_expenses');
                  break;
              }
            } : null,
            onLongPress: _currentUser != null ? () => _showExportMenu(context) : null,
            tooltip: 'Excel Dışa Aktar',
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            padding: const EdgeInsets.all(6),
          ),
          IconButton(
            icon: const Icon(Icons.calculate_rounded, size: 20),
            onPressed: _currentUser != null ? () {
              Navigator.of(context).pushNamed(
                '/calculations',
                arguments: _currentUser,
              );
            } : null,
            tooltip: 'Hesaplamalar',
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            padding: const EdgeInsets.all(6),
          ),
          IconButton(
            icon: const Icon(Icons.event_rounded, size: 20),
            onPressed: () => Navigator.of(context).pushNamed('/fuarlar'),
            tooltip: 'Fuarlar',
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            padding: const EdgeInsets.all(6),
          ),
          IconButton(
            icon: const Icon(Icons.settings_rounded, size: 20),
            onPressed: () => Navigator.of(context).pushNamed('/settings'),
            tooltip: 'Ayarlar',
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            padding: const EdgeInsets.all(6),
          ),
          const SizedBox(width: 4),
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

  /// Excel export menüsünü gösterir
  void _showExportMenu(BuildContext context) {
    final theme = Theme.of(context);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outline.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'Google Sheets Dosyaları',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'Dosyalar Google Sheets üzerinde oluşturulur ve açılır.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
            const SizedBox(height: 24),
            _buildExportOption(
              context,
              title: 'Tabloyu Aç (Benim)',
              subtitle: 'Sadece sizin eklediğiniz tüm kayıtlar',
              icon: Icons.person_outline_rounded,
              color: theme.colorScheme.primary,
              onTap: () => _handleExportAction(context, 'my_entries'),
            ),
            _buildExportOption(
              context,
              title: 'Tabloyu Aç (Tüm Eklenenler)',
              subtitle: 'Tüm kullanıcıların eklediği tüm kayıtlar',
              icon: Icons.list_alt_rounded,
              color: Colors.blue,
              onTap: () => _handleExportAction(context, 'all_entries'),
            ),
            _buildExportOption(
              context,
              title: 'Tabloyu Aç (Harcamalar)',
              subtitle: 'Sadece gider/harcama kayıtları',
              icon: Icons.shopping_cart_outlined,
              color: Colors.deepPurple,
              onTap: () => _handleExportAction(context, 'expenses'),
            ),
            _buildExportOption(
              context,
              title: 'Tabloyu Aç (Ortak Gelir)',
              subtitle: 'İş ortaklarından gelen hakediş tablosu',
              icon: Icons.account_balance_wallet_outlined,
              color: Colors.green,
              onTap: () => _handleExportAction(context, 'partner_incomes'),
            ),
            _buildExportOption(
              context,
              title: 'Tabloyu Aç (Vergi)',
              subtitle: 'Vergi beyanında gösterilecek kayıtlar tablosu',
              icon: Icons.receipt_long_outlined,
              color: Colors.orange,
              onTap: () => _handleExportAction(context, 'tax_deductible'),
            ),
            _buildExportOption(
              context,
              title: 'Tabloyu Aç (Sabit Gider)',
              subtitle: 'Aylık tekrarlayan giderler tablosu',
              icon: Icons.receipt_long_rounded,
              color: Colors.redAccent,
              onTap: () => _handleExportAction(context, 'fixed_expenses'),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildExportOption(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color, size: 24),
      ),
      title: Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
        ),
      ),
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
    );
  }
  Future<void> _handleExportAction(BuildContext context, String type) async {
    try {
      if (_currentUser == null) {
        throw Exception('Kullanıcı bilgileri yüklenemedi. Lütfen tekrar deneyin.');
      }

      // Her Excel açılışında eksiksiz içerik garantisi: cache kullanmıyoruz, her seferinde
      // Firestore'dan güncel veriyi çekip backend'e yazdırıyoruz, sonra açıyoruz.
      final cacheKey = type == 'my_entries' ? 'my_entries_${_currentUser!.userId}' : type;

      // Loading dialog göster
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Google Sheets hazırlanıyor...'),
                ],
              ),
            ),
          ),
        ),
      );

      Map<String, dynamic>? result;

      switch (type) {
        case 'my_entries':
          final entries = await FirestoreService.getMyEntries(_currentUser!.userId);
          // if (entries.isEmpty) throw Exception('Henüz kayıt bulunmuyor.'); // Boş olsa da açsın
          
          final ownerName = _currentUser!.fullName;
          AppLogger.info('Excel oluşturuluyor - Owner: $ownerName, Kayıt sayısı: ${entries.length}');
          
          result = await UploadService.createMyEntriesExcel(
            entries.map((e) => e.toMap()).toList(),
            ownerName,
          );
          if (result != null && result['url'] != null) {
            _sheetUrls[cacheKey] = result['url'].toString();
          }
          break;
        
        case 'all_entries':
          final entries = await FirestoreService.getAllEntries();
          result = await UploadService.createAllEntriesExcel(
            entries.map((e) => e.toMap()).toList(),
          );
          if (result != null && result['url'] != null) {
            _sheetUrls[type] = result['url'].toString();
          }
          break;

        case 'expenses':
          final allEntriesExp = await FirestoreService.getAllEntries();
          final expenseEntries = allEntriesExp.where((e) => e.entryType == 'expense').toList();
          result = await UploadService.createExpenseEntriesExcel(
            expenseEntries.map((e) => e.toMap()).toList(),
          );
          if (result != null && result['url'] != null) {
            _sheetUrls[type] = result['url'].toString();
          }
          break;

        case 'partner_incomes':
          final allEntries = await FirestoreService.getAllEntries();
          final incomeEntries = allEntries.where((e) => e.entryType == 'income').toList();
          result = await UploadService.createIncomeEntriesExcel(
            incomeEntries.map((e) => e.toMap()).toList(),
          );
          if (result != null && result['url'] != null) {
            _sheetUrls[type] = result['url'].toString();
          }
          break;

        case 'tax_deductible':
          final allEntriesTax = await FirestoreService.getAllEntries();
          final taxDeductibleEntries = allEntriesTax.where((e) => e.entryType == 'tax_deductible').toList();
          result = await UploadService.createTaxDeductibleEntriesExcel(
            taxDeductibleEntries.map((e) => e.toMap()).toList(),
          );
          if (result != null && result['url'] != null) {
            _sheetUrls[type] = result['url'].toString();
          }
          break;

        case 'fixed_expenses':
          // Sabit giderler için direkt kaynak dosyayı aç (tek kaynak, sync ayrı yapılıyor)
          const sheetId = AppConfig.googleSheetsFixedExpensesId;
          const url = 'https://docs.google.com/spreadsheets/d/$sheetId/edit';
          result = {'url': url};
          _sheetUrls[type] = url;
          break;

        case 'fixed_incomes':
          // Sabit gelirler: Firestore'dan eksiksiz al, sync et, sonra aç
          final allFixed = await FirestoreService.getAllFixedExpenses();
          final fixedIncomesOnly = allFixed.where((e) => (e.category?.toLowerCase().contains('gelir') ?? false)).map((e) => e.toJson()).toList();
          if (fixedIncomesOnly.isNotEmpty) {
            result = await UploadService.initializeGoogleSheetsWithAllData(
              entries: [],
              fixedExpenses: fixedIncomesOnly,
              sheetName: 'Sabit Gelirler',
            );
            if (result != null && result['url'] != null) {
              _sheetUrls['fixed_incomes'] = result['url'].toString();
            }
          } else {
            result = null;
          }
          break;
      }

      // Loading dialog'u kapat (context geçersiz olabileceği için kök navigator ile kapat)
      try {
        if (MyApp.navigatorKey.currentState?.canPop() == true) {
          MyApp.navigatorKey.currentState!.pop();
        }
      } catch (_) {
        // Dialog zaten kapanmış, sessizce geç
      }

      if (result != null && result['url'] != null && mounted) {
        final String url = result['url'].toString();
        AppLogger.info('Excel hazır, açılıyor: $url');
        final uri = Uri.parse(url);
        
        // Otomatik açmayı dene
        await launchUrl(uri, mode: LaunchMode.externalApplication);

        // await sonrası widget context'i geçersiz olabilir; kök navigator context kullan
        final dialogContext = MyApp.navigatorKey.currentContext;
        if (dialogContext == null) return;

        // Her durumda kullanıcıya manuel açma seçeneği sun (Popup blocker için garanti çözüm)
        showDialog(
            context: dialogContext,
            builder: (context) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green),
                  SizedBox(width: 8),
                  Text('Dosya Hazır'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Excel dosyanız başarıyla oluşturuldu.'),
                  const SizedBox(height: 8),
                  const Text('Eğer otomatik açılmadıysa aşağıdaki butona tıklayın:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 8),
                  SelectableText(url, style: const TextStyle(fontSize: 10, color: Colors.blue)), // URL'i kopyalanabilir yap
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Kapat'),
                ),
                FilledButton.icon(
                  onPressed: () {
                    launchUrl(uri, mode: LaunchMode.externalApplication);
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('DOSYAYI AÇ'),
                ),
              ],
            ),
          );
      } else {
        if (type == 'fixed_incomes') {
          MyApp.messengerKey.currentState?.showSnackBar(
            const SnackBar(
              content: Text('Henüz sabit gelir kaydı bulunmuyor.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 3),
            ),
          );
        } else {
          throw Exception('Google Sheets URL\'si alınamadı');
        }
      }

    } catch (e, stack) {
      AppLogger.error('Excel export hatası: $type', e, stack);
      
      // Dialog açıksa kapat (navigatorKey ile güvenli)
      MyApp.navigatorKey.currentState?.maybePop();
      
      // Hata mesajını messengerKey ile göster (context'ten bağımsız)
      MyApp.messengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text('Hata: ${e.toString().replaceAll('Exception: ', '')}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }
}

