/**
 * Eklediklerim sekmesi
 * Kullanıcının kendi eklediği kayıtları gösterir
 */

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/firestore_service.dart';
import '../../services/upload_service.dart';
import '../../services/local_excel_service.dart';
import '../../widgets/entry_card.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/error_retry_widget.dart';
import '../../widgets/loading_widget.dart';
import '../../config/app_config.dart';
import 'package:intl/intl.dart';
import '../../utils/app_logger.dart';
import '../home_screen.dart';
import 'dart:async';

enum MySortOption {
  dateDesc,
  dateAsc,
  amountDesc,
  amountAsc,
}

class MyEntriesTab extends StatefulWidget {
  final UserProfile currentUser;

  const MyEntriesTab({
    super.key,
    required this.currentUser,
  });

  @override
  State<MyEntriesTab> createState() => _MyEntriesTabState();
}

class _MyEntriesTabState extends State<MyEntriesTab> with AutomaticKeepAliveClientMixin {
  final TextEditingController _searchController = TextEditingController();
  MySortOption _sortOption = MySortOption.dateDesc;
  bool _hasReceivedData = false; // İlk veri geldi mi kontrolü

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<ExpenseEntry> _filterAndSort(List<ExpenseEntry> entries) {
    var filtered = entries;

    // Arama filtresi
    final searchQuery = _searchController.text.trim().toLowerCase();
    if (searchQuery.isNotEmpty) {
      filtered = filtered.where((entry) {
        return entry.description.toLowerCase().contains(searchQuery) ||
            entry.amount.toString().contains(searchQuery);
      }).toList();
    }

    // Sıralama
    filtered.sort((a, b) {
      switch (_sortOption) {
        case MySortOption.dateDesc:
          if (a.createdAt == null && b.createdAt == null) return 0;
          if (a.createdAt == null) return 1;
          if (b.createdAt == null) return -1;
          return b.createdAt!.compareTo(a.createdAt!);
        case MySortOption.dateAsc:
          if (a.createdAt == null && b.createdAt == null) return 0;
          if (a.createdAt == null) return 1;
          if (b.createdAt == null) return -1;
          return a.createdAt!.compareTo(b.createdAt!);
        case MySortOption.amountDesc:
          return b.amount.compareTo(a.amount);
        case MySortOption.amountAsc:
          return a.amount.compareTo(b.amount);
      }
    });

    return filtered;
  }

  Future<void> _deleteEntry(BuildContext context, ExpenseEntry entry) async {
    // Silme onay dialog'u
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Kayıt Sil'),
        content: Text('Bu kaydı silmek istediğinizden emin misiniz?\n\n${entry.description} - ₺${entry.amount.toStringAsFixed(2)}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('Sil'),
          ),
        ],
      ),
    );

    if (confirmed != true || entry.id == null) {
      return;
    }

    try {
      // Önce Google Drive'dan dosyayı sil (driveFileId varsa)
      if (entry.driveFileId.isNotEmpty) {
        try {
          await UploadService.deleteFile(entry.driveFileId);
        } catch (e) {
          // Dosya silme hatası olsa bile Firestore'dan silmeye devam et
          // Kullanıcıya uyarı göster
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Dosya silinemedi ama kayıt silinecek: ${e.toString()}'),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
      }

      // Firestore'dan sil
      await FirestoreService.deleteEntry(entry.id!, widget.currentUser.userId);

      // Excel dosyalarını güncelle (arka planda)
      _updateExcelFilesInBackground();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Kayıt ve dosya başarıyla silindi'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Silme hatası: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Excel dosyalarını arka planda güncelle (entry silindikten sonra)
  Future<void> _updateExcelFilesInBackground() async {
    try {
      // 1. Tüm entry'leri çek
      final allEntries = await FirestoreService.getAllEntries();
      final formattedAllEntries = allEntries.map((entry) {
        return {
          'createdAt': entry.createdAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
          'notes': entry.notes ?? '',
          'ownerName': entry.ownerName,
          'amount': entry.amount,
          'description': entry.description,
          'fileUrl': entry.fileUrl,
        };
      }).toList();

      // 2. Kullanıcının entry'lerini çek
      final myEntries = await FirestoreService.getMyEntries(widget.currentUser.userId);
      final formattedMyEntries = myEntries.map((entry) {
        return {
          'createdAt': entry.createdAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
          'notes': entry.notes ?? '',
          'ownerName': entry.ownerName,
          'amount': entry.amount,
          'description': entry.description,
          'fileUrl': entry.fileUrl,
        };
      }).toList();

      // 3. Tüm sabit giderleri çek
      final fixedExpenses = await FirestoreService.getAllFixedExpenses();
      final formattedFixedExpenses = fixedExpenses.map((expense) {
        return {
          'createdAt': expense.createdAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
          'startDate': expense.startDate?.toIso8601String(),
          'notes': expense.notes ?? '',
          'ownerName': expense.ownerName,
          'amount': expense.amount,
          'description': expense.description,
          'category': expense.category ?? '',
          'recurrence': expense.recurrence ?? '',
          'isActive': expense.isActive,
        };
      }).toList();

      // 4. Tüm Excel dosyalarını paralel olarak güncelle (hata olsa bile devam et)
      await Future.wait([
        // Tüm entry'ler Excel'i
        UploadService.initializeGoogleSheetsWithEntries(formattedAllEntries).catchError((e) {
          AppLogger.warning('Tüm entry\'ler Excel güncellenirken hata: $e');
          return null;
        }),
        // Kullanıcının entry'leri Excel'i
        UploadService.createMyEntriesExcel(formattedMyEntries, widget.currentUser.fullName).catchError((e) {
          AppLogger.warning('Kullanıcı entry\'leri Excel güncellenirken hata: $e');
          return null;
        }),
        // Sabit giderler Excel'i
        UploadService.initializeGoogleSheetsWithFixedExpenses(formattedFixedExpenses).catchError((e) {
          AppLogger.warning('Sabit giderler Excel güncellenirken hata: $e');
          return null;
        }),
        // Tüm veriler Excel'i (settings)
        UploadService.initializeGoogleSheetsWithAllData(formattedAllEntries, formattedFixedExpenses).catchError((e) {
          AppLogger.warning('Tüm veriler Excel güncellenirken hata: $e');
          return null;
        }),
      ], eagerError: false);

      AppLogger.info('Excel dosyaları güncellendi (${formattedAllEntries.length} entry, ${formattedFixedExpenses.length} sabit gider)');
    } catch (e) {
      // Hata olsa bile sessizce devam et (kullanıcıyı rahatsız etme)
      AppLogger.warning('Excel dosyaları güncellenirken genel hata: $e');
    }
  }

  Future<void> _openExcel(BuildContext context) async {
    try {
      AppLogger.info('📊 Excel açma işlemi başlatıldı (Eklediklerim)');
      
      // Loading dialog göster
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Excel hazırlanıyor...'),
                  ],
                ),
              ),
            ),
          ),
        );
      }

      // Kullanıcının entry'lerini al
      AppLogger.info('Firestore\'dan kullanıcının entry\'leri alınıyor...');
      final myEntries = await FirestoreService.getMyEntries(widget.currentUser.userId);
      AppLogger.info('${myEntries.length} entry bulundu');

      if (!mounted) return;
      Navigator.of(context).pop(); // Loading dialog'u kapat

      if (myEntries.isEmpty) {
        AppLogger.warning('Entry bulunamadı, işlem iptal ediliyor');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Henüz kayıt bulunmuyor.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 4),
            ),
          );
        }
        return;
      }

      // Lokal CSV oluştur ve paylaş (backend'e gerek yok)
      await LocalExcelService.createAndShareCSV(
        entries: myEntries,
        fileName: 'Eklediklerim_${DateTime.now().toString().split(' ')[0]}.csv',
      );
      
      AppLogger.success('✅ Excel başarıyla paylaşıldı');
    } catch (e, stackTrace) {
      AppLogger.error('Excel açma hatası', e, stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Excel açma hatası: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }


  Widget _buildContent(ThemeData theme) {
    return Column(
      children: [
        // Kompakt başlık ve arama barı
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              bottom: BorderSide(
                color: theme.dividerColor.withValues(alpha: 0.5),
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              Text(
                'Eklediklerim',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                ),
              ),
              const Spacer(),
              SizedBox(
                width: 180,
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Ara...',
                    prefixIcon: Icon(
                      Icons.search,
                      size: 20,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              setState(() {
                                _searchController.clear();
                              });
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    isDense: true,
                  ),
                  style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14),
                  onChanged: (value) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        setState(() {});
                      }
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<MySortOption>(
                icon: Icon(
                  Icons.sort_rounded,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
                tooltip: 'Sırala',
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                onSelected: (value) {
                  setState(() {
                    _sortOption = value;
                  });
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: MySortOption.dateDesc,
                    child: Row(
                      children: [
                        Icon(
                          Icons.arrow_downward,
                          size: 18,
                          color: _sortOption == MySortOption.dateDesc
                              ? theme.colorScheme.primary
                              : null,
                        ),
                        const SizedBox(width: 8),
                        const Text('Tarih (Yeni → Eski)'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: MySortOption.dateAsc,
                    child: Row(
                      children: [
                        Icon(
                          Icons.arrow_upward,
                          size: 18,
                          color: _sortOption == MySortOption.dateAsc
                              ? theme.colorScheme.primary
                              : null,
                        ),
                        const SizedBox(width: 8),
                        const Text('Tarih (Eski → Yeni)'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: MySortOption.amountDesc,
                    child: Row(
                      children: [
                        Icon(
                          Icons.arrow_downward,
                          size: 18,
                          color: _sortOption == MySortOption.amountDesc
                              ? theme.colorScheme.primary
                              : null,
                        ),
                        const SizedBox(width: 8),
                        const Text('Miktar (Yüksek → Düşük)'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: MySortOption.amountAsc,
                    child: Row(
                      children: [
                        Icon(
                          Icons.arrow_upward,
                          size: 18,
                          color: _sortOption == MySortOption.amountAsc
                              ? theme.colorScheme.primary
                              : null,
                        ),
                        const SizedBox(width: 8),
                        const Text('Miktar (Düşük → Yüksek)'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        // Liste
        Expanded(
          child: StreamBuilder<List<ExpenseEntry>>(
            stream: FirestoreService.streamMyEntries(widget.currentUser.userId),
            builder: (context, snapshot) {
              // Hata durumu - öncelikli kontrol
              if (snapshot.hasError) {
                final errorMessage = snapshot.error.toString();
                AppLogger.error('MyEntriesTab StreamBuilder hatası', snapshot.error);
                
                // Firestore index hatası kontrolü
                String userMessage = 'Veriler yüklenirken bir hata oluştu';
                if (errorMessage.contains('index') || errorMessage.contains('Index')) {
                  userMessage = 'Firestore index hatası. Lütfen Firebase Console\'da gerekli index\'i oluşturun.';
                } else if (errorMessage.contains('permission') || errorMessage.contains('Permission') || errorMessage.contains('permission-denied')) {
                  userMessage = 'Firestore erişim izni hatası. Lütfen çıkış yapıp tekrar giriş yapın. Sorun devam ederse Firebase Console\'da güvenlik kurallarını kontrol edin.';
                }
                
                return ErrorRetryWidget(
                  message: userMessage,
                  onRetry: () async {
                    // Permission hatası durumunda token'ı yenile
                    if (errorMessage.contains('permission') || errorMessage.contains('Permission') || errorMessage.contains('permission-denied')) {
                      try {
                        final currentUser = FirebaseAuth.instance.currentUser;
                        if (currentUser != null) {
                          await currentUser.getIdToken(true);
                          AppLogger.info('Token yenilendi - StreamBuilder yeniden denenecek');
                        }
                      } catch (e) {
                        AppLogger.error('Token yenileme hatası', e);
                      }
                    }
                    // StreamBuilder otomatik yeniden deneyecek
                  },
                );
              }

              // Veri varsa hemen göster (cache'den veya yeni veri)
              final allEntries = snapshot.data ?? [];
              
              // İlk veri geldiğinde flag'i set et
              if (snapshot.hasData && !_hasReceivedData) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    setState(() {
                      _hasReceivedData = true;
                    });
                  }
                });
              }
              
              // Sadece ilk yüklemede ve hiç veri gelmemişse loading göster
              // Eğer daha önce veri geldiyse (hasReceivedData true ise) boş liste göster
              if (snapshot.connectionState == ConnectionState.waiting && 
                  !_hasReceivedData && 
                  !snapshot.hasData) {
                return const LoadingWidget(message: 'Kayıtlar yükleniyor...');
              }
              
              // Eğer connectionState active veya done ise ama veri yoksa, empty state göster
              if ((snapshot.connectionState == ConnectionState.active || 
                   snapshot.connectionState == ConnectionState.done) &&
                  allEntries.isEmpty) {
                // Veri geldi ama boş, empty state göster
                if (!_hasReceivedData) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      setState(() {
                        _hasReceivedData = true;
                      });
                    }
                  });
                }
              }
              
              // Eğer veri geldiyse ama boşsa, empty state göster
              final filteredEntries = _filterAndSort(allEntries);

              if (allEntries.isEmpty) {
                return EmptyStateWidget(
                  title: 'Henüz kayıt eklemediniz',
                  subtitle: 'Yukarıdaki "Ekleme" sekmesinden kayıt ekleyebilirsiniz',
                  icon: Icons.receipt_long,
                );
              }

              if (filteredEntries.isEmpty) {
                return EmptyStateWidget(
                  title: 'Arama sonucu bulunamadı',
                  subtitle: 'Farklı bir arama terimi deneyin',
                  icon: Icons.search_off,
                );
              }

              // Toplam hesapla
              final totalAmount = filteredEntries.fold<double>(
                0.0,
                (sum, entry) => sum + entry.amount,
              );

              return RefreshIndicator(
                onRefresh: () async {
                  await Future.delayed(const Duration(milliseconds: 500));
                },
                child: ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  shrinkWrap: false,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: filteredEntries.length + (filteredEntries.isNotEmpty ? 1 : 0),
                  cacheExtent: AppConfig.listViewCacheExtent.toDouble(),
                  addAutomaticKeepAlives: false,
                  addRepaintBoundaries: true,
                  itemBuilder: (context, index) {
                    // İlk item toplam kartı
                    if (index == 0 && filteredEntries.isNotEmpty) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12, top: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.account_balance_wallet_rounded,
                                  size: 20,
                                  color: theme.colorScheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _searchController.text.isEmpty ? 'Toplam' : 'Filtrelenmiş',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              NumberFormat.currency(
                                symbol: '₺',
                                decimalDigits: 2,
                                locale: 'tr_TR',
                              ).format(totalAmount),
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    
                    // Entry item'ları (index - 1 çünkü ilk item toplam kartı)
                    final entryIndex = filteredEntries.isNotEmpty ? index - 1 : index;
                    final entry = filteredEntries[entryIndex];
                    final displayEntry = entry.ownerName.isEmpty || entry.ownerId == widget.currentUser.userId
                        ? entry.copyWith(ownerName: widget.currentUser.fullName)
                        : entry;
                    return RepaintBoundary(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: EntryCard(
                          entry: displayEntry,
                          onDelete: () => _deleteEntry(context, entry),
                          showOwnerIcon: true,
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin için gerekli
    final theme = Theme.of(context);
    return Scaffold(
      body: _buildContent(theme),
      floatingActionButton: FloatingActionButton(
        heroTag: 'my_entries_excel_fab',
        onPressed: () => _openExcel(context),
        tooltip: 'Excel',
        child: const Icon(Icons.table_chart_rounded),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
      ),
    );
  }
}

