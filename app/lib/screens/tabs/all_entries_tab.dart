/**
 * Tüm Eklenenler sekmesi
 * Tüm kullanıcıların kayıtlarını gösterir ve filtreleme yapar
 */

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/firestore_service.dart';
import '../../widgets/entry_card.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/error_retry_widget.dart';
import '../../widgets/loading_widget.dart';
import '../../widgets/total_amount_card.dart';
import '../../models/expense_entry.dart';
import '../home_screen.dart';

class AllEntriesTab extends StatefulWidget {
  const AllEntriesTab({super.key});

  @override
  State<AllEntriesTab> createState() => _AllEntriesTabState();
}

enum SortOption {
  dateDesc,
  dateAsc,
  amountDesc,
  amountAsc,
}

class _AllEntriesTabState extends State<AllEntriesTab> {
  String? _selectedOwnerFilter;
  DateTimeRange? _selectedDateRange;
  final TextEditingController _searchController = TextEditingController();
  SortOption _sortOption = SortOption.dateDesc;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<ExpenseEntry> _filterEntries(List<ExpenseEntry> entries) {
    var filtered = entries;

    // Kişi filtresi
    if (_selectedOwnerFilter != null && _selectedOwnerFilter != 'Hepsi') {
      filtered = filtered
          .where((entry) => entry.ownerName == _selectedOwnerFilter)
          .toList();
    }

    // Tarih filtresi
    if (_selectedDateRange != null) {
      filtered = filtered.where((entry) {
        if (entry.createdAt == null) return false;
        
        // Entry tarihini normalize et (sadece tarih kısmı)
        final entryDate = DateTime(
          entry.createdAt!.year,
          entry.createdAt!.month,
          entry.createdAt!.day,
        );
        
        // Seçili tarih aralığını normalize et
        final startDate = DateTime(
          _selectedDateRange!.start.year,
          _selectedDateRange!.start.month,
          _selectedDateRange!.start.day,
        );
        final endDate = DateTime(
          _selectedDateRange!.end.year,
          _selectedDateRange!.end.month,
          _selectedDateRange!.end.day,
          23,
          59,
          59,
          999,
        );
        
        // Tarih aralığında mı kontrol et (>= startDate && <= endDate)
        return entryDate.compareTo(startDate) >= 0 &&
            entryDate.compareTo(endDate) <= 0;
      }).toList();
    }

    // Arama filtresi
    final searchQuery = _searchController.text.trim().toLowerCase();
    if (searchQuery.isNotEmpty) {
      filtered = filtered.where((entry) {
        return entry.description.toLowerCase().contains(searchQuery) ||
            entry.ownerName.toLowerCase().contains(searchQuery) ||
            entry.amount.toString().contains(searchQuery);
      }).toList();
    }

    // Sıralama
    filtered.sort((a, b) {
      switch (_sortOption) {
        case SortOption.dateDesc:
          if (a.createdAt == null && b.createdAt == null) return 0;
          if (a.createdAt == null) return 1;
          if (b.createdAt == null) return -1;
          return b.createdAt!.compareTo(a.createdAt!);
        case SortOption.dateAsc:
          if (a.createdAt == null && b.createdAt == null) return 0;
          if (a.createdAt == null) return 1;
          if (b.createdAt == null) return -1;
          return a.createdAt!.compareTo(b.createdAt!);
        case SortOption.amountDesc:
          return b.amount.compareTo(a.amount);
        case SortOption.amountAsc:
          return a.amount.compareTo(b.amount);
      }
    });

    return filtered;
  }

  Future<void> _selectDateRange(BuildContext context) async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _selectedDateRange,
      locale: const Locale('tr', 'TR'),
      helpText: 'Tarih Aralığı Seçin',
      cancelText: 'İptal',
      confirmText: 'Seç',
    );
    if (picked != null) {
      setState(() {
        _selectedDateRange = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSmallScreen = MediaQuery.of(context).size.width < 600;

    return Column(
      children: [
        // Arama bar
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: isSmallScreen ? 16 : 16,
            vertical: 12,
          ),
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
                    hintText: 'Ara... (açıklama, kişi, miktar)',
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
                child: PopupMenuButton<SortOption>(
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
                    value: SortOption.dateDesc,
                    child: Row(
                      children: [
                        Icon(Icons.arrow_downward, size: 18),
                        SizedBox(width: 8),
                        Text('Tarih (Yeni → Eski)'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: SortOption.dateAsc,
                    child: Row(
                      children: [
                        Icon(Icons.arrow_upward, size: 18),
                        SizedBox(width: 8),
                        Text('Tarih (Eski → Yeni)'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: SortOption.amountDesc,
                    child: Row(
                      children: [
                        Icon(Icons.arrow_downward, size: 18),
                        SizedBox(width: 8),
                        Text('Miktar (Yüksek → Düşük)'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: SortOption.amountAsc,
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
        // Filtre bar - Responsive layout
        StreamBuilder<List<String>>(
          stream: FirestoreService.streamAllOwnerNames(),
          builder: (context, ownerNamesSnapshot) {
            final ownerNames = ownerNamesSnapshot.data ?? [];
            final isLoadingOwners = ownerNamesSnapshot.connectionState ==
                ConnectionState.waiting;

            return Container(
              padding: EdgeInsets.symmetric(
                horizontal: isSmallScreen ? 12 : 16,
                vertical: isSmallScreen ? 8 : 12,
              ),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(
                  bottom: BorderSide(
                    color: Theme.of(context).dividerColor,
                    width: 1,
                  ),
                ),
              ),
              child: isSmallScreen
                  ? // Küçük ekranlarda dikey layout
                  Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.filter_list, size: 20),
                            const SizedBox(width: 8),
                            const Text(
                              'Kişi Filtresi:',
                              style: TextStyle(
                                fontWeight: FontWeight.w500,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        DropdownButton<String>(
                          value: _selectedOwnerFilter ?? 'Hepsi',
                          isExpanded: true,
                          items: [
                            const DropdownMenuItem<String>(
                              value: 'Hepsi',
                              child: Text('Hepsi'),
                            ),
                            ...ownerNames.map((name) {
                              return DropdownMenuItem<String>(
                                value: name,
                                child: Text(
                                  name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }),
                          ],
                          onChanged: isLoadingOwners
                              ? null
                              : (value) {
                                  setState(() {
                                    _selectedOwnerFilter = value;
                                  });
                                },
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () => _selectDateRange(context),
                          icon: const Icon(Icons.calendar_today, size: 18),
                          label: Text(
                            _selectedDateRange == null
                                ? 'Tarih Filtresi'
                                : '${DateFormat('dd.MM.yyyy', 'tr_TR').format(_selectedDateRange!.start)} - ${DateFormat('dd.MM.yyyy', 'tr_TR').format(_selectedDateRange!.end)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        if (_selectedDateRange != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: TextButton.icon(
                              onPressed: () {
                                setState(() {
                                  _selectedDateRange = null;
                                });
                              },
                              icon: const Icon(Icons.close, size: 16),
                              label: const Text('Filtreyi Temizle', style: TextStyle(fontSize: 12)),
                            ),
                          ),
                      ],
                    )
                  : // Büyük ekranlarda yatay layout
                  Row(
                      children: [
                        const Icon(Icons.filter_list),
                        const SizedBox(width: 8),
                        const Text(
                          'Kişi Filtresi:',
                          style: TextStyle(fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButton<String>(
                            value: _selectedOwnerFilter ?? 'Hepsi',
                            isExpanded: true,
                            items: [
                              const DropdownMenuItem<String>(
                                value: 'Hepsi',
                                child: Text('Hepsi'),
                              ),
                              ...ownerNames.map((name) {
                                return DropdownMenuItem<String>(
                                  value: name,
                                  child: Text(
                                    name,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              }),
                            ],
                            onChanged: isLoadingOwners
                                ? null
                                : (value) {
                                    setState(() {
                                      _selectedOwnerFilter = value;
                                    });
                                  },
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () => _selectDateRange(context),
                          icon: const Icon(Icons.calendar_today, size: 18),
                          label: Text(
                            _selectedDateRange == null
                                ? 'Tarih'
                                : DateFormat('dd.MM', 'tr_TR').format(_selectedDateRange!.start),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        if (_selectedDateRange != null)
                          IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () {
                              setState(() {
                                _selectedDateRange = null;
                              });
                            },
                            tooltip: 'Tarih filtresini temizle',
                          ),
                      ],
                    ),
            );
          },
        ),
        // Liste
        Expanded(
          child: StreamBuilder<List<ExpenseEntry>>(
            stream: FirestoreService.streamAllEntries(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const LoadingWidget(message: 'Kayıtlar yükleniyor...');
              }

              if (snapshot.hasError) {
                return ErrorRetryWidget(
                  message: 'Veriler yüklenirken bir hata oluştu',
                  onRetry: () {
                    // StreamBuilder otomatik yeniden deneyecek
                  },
                );
              }

              final allEntries = snapshot.data ?? [];
              final filteredEntries = _filterEntries(allEntries);

              if (allEntries.isEmpty) {
                return EmptyStateWidget(
                  title: 'Henüz kayıt yok',
                  subtitle: 'İlk kaydı eklemek için "Ekleme" sekmesini kullanın',
                  icon: Icons.receipt_long,
                );
              }

              if (filteredEntries.isEmpty) {
                return EmptyStateWidget(
                  title: 'Arama/Filtre sonucu bulunamadı',
                  subtitle: 'Farklı bir arama terimi veya filtre deneyin',
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
                      title: _selectedOwnerFilter == null ||
                              _selectedOwnerFilter == 'Hepsi'
                          ? 'Toplam Harcama'
                          : 'Filtrelenmiş Toplam',
                    ),
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
                            child: EntryCard(entry: filteredEntries[index]),
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

