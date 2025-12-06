/**
 * Eklediklerim sekmesi
 * Kullanıcının kendi eklediği kayıtları gösterir
 */

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../services/firestore_service.dart';
import '../../services/export_service.dart';
import '../../widgets/entry_card.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/error_retry_widget.dart';
import '../../widgets/loading_widget.dart';
import '../../widgets/total_amount_card.dart';
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

class _MyEntriesTabState extends State<MyEntriesTab> {
  final TextEditingController _searchController = TextEditingController();
  MySortOption _sortOption = MySortOption.dateDesc;

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

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Arama bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.05),
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
                        color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
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
                      horizontal: 20,
                      vertical: 14,
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
                  color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
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
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const LoadingWidget(message: 'Kayıtlar yükleniyor...');
              }

              if (snapshot.hasError) {
                final errorMessage = snapshot.error.toString();
                debugPrint('MyEntriesTab StreamBuilder hatası: $errorMessage');
                
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
                    setState(() {});
                  },
                );
              }

              final allEntries = snapshot.data ?? [];
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
                        itemBuilder: (context, index) {
                          return TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0.0, end: 1.0),
                            duration: Duration(milliseconds: 200 + (index * 50)),
                            curve: Curves.easeOut,
                            builder: (context, value, child) {
                              return Opacity(
                                opacity: value,
                                child: Transform.translate(
                                  offset: Offset(0, 20 * (1 - value)),
                                  child: child,
                                ),
                              );
                            },
                            child: EntryCard(
                              entry: filteredEntries[index],
                            ),
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

