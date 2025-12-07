/**
 * Eklediklerim sekmesi
 * Kullanıcının kendi eklediği kayıtları gösterir
 */

import 'package:flutter/material.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../services/firestore_service.dart';
import '../../services/export_service.dart';
import '../../services/upload_service.dart';
import '../../widgets/entry_card.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/error_retry_widget.dart';
import '../../widgets/loading_widget.dart';
import '../../widgets/total_amount_card.dart';
import '../../config/app_config.dart';
import '../../utils/app_logger.dart';
import '../home_screen.dart';

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

  Future<void> _exportToCSV(BuildContext context, List<ExpenseEntry> entries) async {
    try {
      // CSV içeriğini oluştur
      final csvContent = ExportService.exportToCSV(entries);
      final fileName = ExportService.generateFileName('harcamalar');

      // Geçici dosya oluştur
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/$fileName');
      await file.writeAsString(csvContent);

      // Paylaş
      final result = await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Harcama kayıtları',
        subject: fileName,
      );

      if (result.status == ShareResultStatus.success && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Dosya başarıyla paylaşıldı'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export hatası: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin için gerekli
    return Column(
      children: [
        // Arama bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.05),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Ara... (açıklama, miktar)',
                    prefixIcon: Icon(
                      Icons.search,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              setState(() {
                                _searchController.clear();
                              });
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.primary,
                        width: 2,
                      ),
                    ),
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surface,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                  ),
                  onChanged: (value) {
                    setState(() {});
                  },
                ),
              ),
              const SizedBox(width: 12),
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: PopupMenuButton<MySortOption>(
                  icon: Icon(
                    Icons.sort,
                    color: Theme.of(context).colorScheme.primary,
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
                  const PopupMenuItem(
                    value: MySortOption.dateDesc,
                    child: Row(
                      children: [
                        Icon(Icons.arrow_downward, size: 18),
                        SizedBox(width: 8),
                        Text('Tarih (Yeni → Eski)'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: MySortOption.dateAsc,
                    child: Row(
                      children: [
                        Icon(Icons.arrow_upward, size: 18),
                        SizedBox(width: 8),
                        Text('Tarih (Eski → Yeni)'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: MySortOption.amountDesc,
                    child: Row(
                      children: [
                        Icon(Icons.arrow_downward, size: 18),
                        SizedBox(width: 8),
                        Text('Miktar (Yüksek → Düşük)'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: MySortOption.amountAsc,
                    child: Row(
                      children: [
                        Icon(Icons.arrow_upward, size: 18),
                        SizedBox(width: 8),
                        Text('Miktar (Düşük → Yüksek)'),
                      ],
                    ),
                  ),
                ],
                ),
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
                } else if (errorMessage.contains('permission') || errorMessage.contains('Permission')) {
                  userMessage = 'Firestore izin hatası. Lütfen Firestore rules\'ı kontrol edin.';
                }
                
                return ErrorRetryWidget(
                  message: userMessage,
                  onRetry: () {
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

              return RefreshIndicator(
                onRefresh: () async {
                  // StreamBuilder otomatik yenilenecek
                  await Future.delayed(const Duration(milliseconds: 500));
                },
                child: Column(
                  children: [
                    TotalAmountCard(
                      entries: filteredEntries,
                      title: _searchController.text.isEmpty
                          ? 'Toplam Harcama'
                          : 'Filtrelenmiş Toplam',
                    ),
                    // Export butonu
                    if (filteredEntries.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: OutlinedButton.icon(
                          onPressed: () => _exportToCSV(context, filteredEntries),
                          icon: const Icon(Icons.download),
                          label: const Text('CSV Olarak Dışa Aktar'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 40),
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        itemCount: filteredEntries.length,
                        cacheExtent: 500.0, // Daha büyük cache için
                        addAutomaticKeepAlives: false, // Performans için
                        addRepaintBoundaries: true, // Repaint optimizasyonu
                        itemBuilder: (context, index) {
                          return EntryCard(
                            entry: filteredEntries[index],
                            onDelete: () => _deleteEntry(context, filteredEntries[index]),
                            showOwnerIcon: true, // "Benim yüklediklerim" sekmesinde kullanıcı adını göster
                          );
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

