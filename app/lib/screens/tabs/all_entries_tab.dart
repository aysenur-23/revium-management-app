/**
 * Tüm Eklenenler sekmesi
 * Tüm kullanıcıların kayıtlarını gösterir ve filtreleme yapar
 */

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/firestore_service.dart';
import '../../services/upload_service.dart';
import '../../services/local_excel_service.dart';
import '../../widgets/entry_card.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/error_retry_widget.dart';
import '../../widgets/loading_widget.dart';
import '../../models/expense_entry.dart';
import '../../config/app_config.dart';
import '../../utils/app_logger.dart';
import '../home_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:typed_data';
import 'dart:async';
import 'dart:io';
import '../../services/file_opener/file_open_service.dart';
import '../../models/app_file_reference.dart';

class AllEntriesTab extends StatefulWidget {
  final UserProfile? currentUser;

  const AllEntriesTab({
    super.key,
    this.currentUser,
  });

  @override
  State<AllEntriesTab> createState() => _AllEntriesTabState();
}

enum SortOption {
  dateDesc,
  dateAsc,
  amountDesc,
  amountAsc,
}

class _AllEntriesTabState extends State<AllEntriesTab> with AutomaticKeepAliveClientMixin {
  String? _selectedOwnerFilter;
  DateTimeRange? _selectedDateRange;
  final TextEditingController _searchController = TextEditingController();
  SortOption _sortOption = SortOption.dateDesc;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openExcel(BuildContext context) async {
    try {
      AppLogger.info('📊 Excel açma işlemi başlatıldı (Tüm Eklenenler)');
      
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

      // Tüm entry'leri al
      AppLogger.info('Firestore\'dan tüm entry\'ler alınıyor...');
      final allEntries = await FirestoreService.getAllEntries();
      AppLogger.info('${allEntries.length} entry bulundu');

      if (!mounted) return;
      Navigator.of(context).pop(); // Loading dialog'u kapat

      if (allEntries.isEmpty) {
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
        entries: allEntries,
        fileName: 'Tum_Eklenenler_${DateTime.now().toString().split(' ')[0]}.csv',
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

  /// Excel dosyasını Google Drive'dan indirip geçici olarak saklayıp açar (yeni modüler servis)
  Future<void> _openExcelFromDrive(BuildContext context, String fileId, int entryCount) async {
    try {
      AppLogger.info('📥 Excel dosyası açma işlemi başlatıldı');
      AppLogger.debug('File ID: $fileId');
      
      // Loading göster
      if (context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => Center(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    const Text('Excel yükleniyor...'),
                  ],
                ),
              ),
            ),
          ),
        );
      }

      // AppFileReference oluştur (Excel için)
      final fileRef = AppFileReference(
        id: 'excel_$fileId',
        driveFileId: fileId,
        name: 'Harcama Takibi.xlsx',
        mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        createdAt: DateTime.now(),
        uploadedByUserId: '',
      );

      // Yeni modüler servis ile aç
      await FileOpenService.openOrDownloadAndOpen(fileRef);

      // Loading'i kapat
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    } catch (e, stackTrace) {
      AppLogger.error('Excel açma hatası', e, stackTrace);
      // Loading'i kapat
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    }
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

  void _showFilterDialog(BuildContext context, ThemeData theme, List<String> ownerNames) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outline.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Başlık
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Filtrele',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 24),
            // Kişi filtresi
            Text(
              'Kişi',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _selectedOwnerFilter ?? 'Hepsi',
              isExpanded: true,
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              items: [
                const DropdownMenuItem<String>(
                  value: 'Hepsi',
                  child: Text('Hepsi'),
                ),
                ...ownerNames.map((name) {
                  return DropdownMenuItem<String>(
                    value: name,
                    child: Text(name),
                  );
                }),
              ],
              onChanged: (value) {
                setState(() {
                  _selectedOwnerFilter = value;
                });
              },
            ),
            const SizedBox(height: 24),
            // Tarih filtresi
            Text(
              'Tarih Aralığı',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                Navigator.of(context).pop();
                await _selectDateRange(context);
              },
              icon: const Icon(Icons.calendar_today, size: 18),
              label: Text(
                _selectedDateRange == null
                    ? 'Tarih Seç'
                    : '${DateFormat('dd.MM.yyyy', 'tr_TR').format(_selectedDateRange!.start)} - ${DateFormat('dd.MM.yyyy', 'tr_TR').format(_selectedDateRange!.end)}',
              ),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            if (_selectedDateRange != null) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _selectedDateRange = null;
                  });
                },
                icon: const Icon(Icons.close, size: 16),
                label: const Text('Tarih Filtresini Temizle'),
              ),
            ],
            const SizedBox(height: 24),
            // Tüm filtreleri temizle
            if (_getActiveFilterCount() > 0)
              OutlinedButton(
                onPressed: () {
                  setState(() {
                    _selectedOwnerFilter = null;
                    _selectedDateRange = null;
                    _searchController.clear();
                  });
                  Navigator.of(context).pop();
                },
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Tüm Filtreleri Temizle'),
              ),
          ],
        ),
      ),
    );
  }

  int _getActiveFilterCount() {
    int count = 0;
    if (_selectedOwnerFilter != null && _selectedOwnerFilter != 'Hepsi') {
      count++;
    }
    if (_selectedDateRange != null) {
      count++;
    }
    if (_searchController.text.trim().isNotEmpty) {
      count++;
    }
    return count;
  }

  /// Entry'yi siler (sadece sahibi silebilir)
  Future<void> _deleteEntry(BuildContext context, ExpenseEntry entry) async {
    // Entry'nin sahibi kontrolü
    if (widget.currentUser == null || entry.ownerId != widget.currentUser!.userId) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bu kaydı silme yetkiniz yok. Sadece kendi kayıtlarınızı silebilirsiniz.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    // Onay dialog'u göster
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kaydı Sil'),
        content: const Text('Bu kaydı silmek istediğinize emin misiniz? Bu işlem geri alınamaz.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('Sil'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Loading göster
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
                  Text('Kayıt siliniyor...'),
                ],
              ),
            ),
          ),
        ),
      );
    }

    try {
      // Entry'yi Firestore'dan sil
      await FirestoreService.deleteEntry(entry.id!, widget.currentUser!.userId);

      // Google Drive'dan dosyayı sil (varsa)
      if (entry.driveFileId != null && entry.driveFileId!.isNotEmpty) {
        try {
          await UploadService.deleteFile(entry.driveFileId!);
          AppLogger.info('Google Drive dosyası silindi: ${entry.driveFileId}');
        } catch (e) {
          AppLogger.warning('Google Drive dosyası silinirken hata: $e');
          // Dosya silme hatası kritik değil, devam et
        }
      }

      // Excel dosyalarını güncelle (arka planda)
      _updateExcelFilesInBackground();

      if (mounted) {
        Navigator.of(context).pop(); // Loading dialog'u kapat
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Kayıt başarıyla silindi'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      AppLogger.error('Entry silme hatası', e);
      if (mounted) {
        Navigator.of(context).pop(); // Loading dialog'u kapat
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kayıt silinirken hata oluştu: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// Excel dosyalarını arka planda güncelle (entry silindikten sonra)
  Future<void> _updateExcelFilesInBackground() async {
    try {
      // Tüm entry'leri çek
      final allEntries = await FirestoreService.getAllEntries();
      final formattedAllEntries = allEntries.map((entry) {
        return {
          'createdAt': entry.createdAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
          'notes': entry.notes ?? '',
          'ownerName': entry.ownerName,
          'amount': entry.amount,
          'description': entry.description,
          'fileUrl': entry.fileUrl ?? '',
        };
      }).toList();

      // Tüm sabit giderleri çek
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

      // Kullanıcının entry'lerini çek (my entries Excel için)
      final currentUserId = widget.currentUser?.userId;
      List<Map<String, dynamic>> formattedMyEntries = [];
      if (currentUserId != null) {
        final myEntries = await FirestoreService.getMyEntries(currentUserId);
        formattedMyEntries = myEntries.map((entry) {
          return {
            'createdAt': entry.createdAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
            'notes': entry.notes ?? '',
            'ownerName': entry.ownerName,
            'amount': entry.amount,
            'description': entry.description,
            'fileUrl': entry.fileUrl ?? '',
          };
        }).toList();
      }

      // Tüm Excel dosyalarını paralel olarak güncelle
      await Future.wait([
        // Tüm entry'ler Excel'i
        UploadService.initializeGoogleSheetsWithEntries(formattedAllEntries).catchError((e) {
          AppLogger.warning('Tüm entry\'ler Excel güncellenirken hata: $e');
        }),
        // Kullanıcının entry'leri Excel'i (varsa)
        if (formattedMyEntries.isNotEmpty)
          UploadService.createMyEntriesExcel(formattedMyEntries).catchError((e) {
            AppLogger.warning('Kullanıcı entry\'leri Excel güncellenirken hata: $e');
          }),
        // Sabit giderler Excel'i
        UploadService.initializeGoogleSheetsWithFixedExpenses(formattedFixedExpenses).catchError((e) {
          AppLogger.warning('Sabit giderler Excel güncellenirken hata: $e');
        }),
        // Tüm veriler Excel'i (settings)
        UploadService.initializeGoogleSheetsWithAllData(formattedAllEntries, formattedFixedExpenses).catchError((e) {
          AppLogger.warning('Tüm veriler Excel güncellenirken hata: $e');
        }),
      ], eagerError: false);

      AppLogger.info('Excel dosyaları güncellendi (${formattedAllEntries.length} entry, ${formattedFixedExpenses.length} sabit gider)');
    } catch (e) {
      AppLogger.warning('Excel dosyaları güncellenirken genel hata: $e');
    }
  }

  Widget _buildContent(ThemeData theme, bool isSmallScreen) {
    return Column(
      children: [
        // Kompakt başlık ve arama barı
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: isSmallScreen ? 16 : 20,
            vertical: 12,
          ),
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
              // Başlık
              Text(
                'Tüm Eklenenler',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                ),
              ),
              const SizedBox(width: 8),
              // Arama - Flexible ile taşmayı önle
              Flexible(
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
              // Sıralama butonu
              PopupMenuButton<SortOption>(
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
                    value: SortOption.dateDesc,
                    child: Row(
                      children: [
                        Icon(
                          Icons.arrow_downward,
                          size: 18,
                          color: _sortOption == SortOption.dateDesc
                              ? theme.colorScheme.primary
                              : null,
                        ),
                        const SizedBox(width: 8),
                        const Text('Tarih (Yeni → Eski)'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: SortOption.dateAsc,
                    child: Row(
                      children: [
                        Icon(
                          Icons.arrow_upward,
                          size: 18,
                          color: _sortOption == SortOption.dateAsc
                              ? theme.colorScheme.primary
                              : null,
                        ),
                        const SizedBox(width: 8),
                        const Text('Tarih (Eski → Yeni)'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: SortOption.amountDesc,
                    child: Row(
                      children: [
                        Icon(
                          Icons.arrow_downward,
                          size: 18,
                          color: _sortOption == SortOption.amountDesc
                              ? theme.colorScheme.primary
                              : null,
                        ),
                        const SizedBox(width: 8),
                        const Text('Miktar (Yüksek → Düşük)'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: SortOption.amountAsc,
                    child: Row(
                      children: [
                        Icon(
                          Icons.arrow_upward,
                          size: 18,
                          color: _sortOption == SortOption.amountAsc
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
              const SizedBox(width: 8),
              // Filtre butonu
              StreamBuilder<List<String>>(
                stream: FirestoreService.streamAllOwnerNames(),
                builder: (context, ownerNamesSnapshot) {
                  final ownerNames = ownerNamesSnapshot.data ?? [];
                  return IconButton(
                    icon: Stack(
                      children: [
                        Icon(
                          Icons.tune_rounded,
                          color: _getActiveFilterCount() > 0
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                        if (_getActiveFilterCount() > 0)
                          Positioned(
                            right: 0,
                            top: 0,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.error,
                                shape: BoxShape.circle,
                              ),
                              constraints: const BoxConstraints(
                                minWidth: 12,
                                minHeight: 12,
                              ),
                              child: Text(
                                '${_getActiveFilterCount()}',
                                style: TextStyle(
                                  color: theme.colorScheme.onError,
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                      ],
                    ),
                    tooltip: 'Filtrele',
                    onPressed: () => _showFilterDialog(context, theme, ownerNames),
                  );
                },
              ),
            ],
          ),
        ),
        // Liste
        Expanded(
          child: StreamBuilder<List<ExpenseEntry>>(
            stream: FirestoreService.streamAllEntries(),
            builder: (context, snapshot) {
              // Sadece ilk yüklemede loading göster
              if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                return const LoadingWidget(message: 'Kayıtlar yükleniyor...');
              }

              if (snapshot.hasError) {
                final errorMessage = snapshot.error.toString();
                AppLogger.error('AllEntriesTab StreamBuilder hatası', snapshot.error);
                
                String userMessage = 'Veriler yüklenirken bir hata oluştu';
                if (errorMessage.contains('permission') || errorMessage.contains('Permission') || errorMessage.contains('permission-denied')) {
                  userMessage = 'Firestore erişim izni hatası. Lütfen çıkış yapıp tekrar giriş yapın. Sorun devam ederse Firebase Console\'da güvenlik kurallarını kontrol edin.';
                } else if (errorMessage.contains('index') || errorMessage.contains('Index')) {
                  userMessage = 'Firestore index hatası. Lütfen Firebase Console\'da gerekli index\'i oluşturun.';
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

              // Toplam hesapla
              final totalAmount = filteredEntries.fold<double>(
                0.0,
                (sum, entry) => sum + entry.amount,
              );

              return RefreshIndicator(
                onRefresh: () async {
                  await Future.delayed(const Duration(milliseconds: 500));
                },
                child: Column(
                  children: [
                    // Kompakt toplam kartı
                    if (filteredEntries.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                                  _getActiveFilterCount() > 0 ? 'Filtrelenmiş Toplam' : 'Toplam',
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
                      ),
                    // Liste
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: filteredEntries.length,
                        cacheExtent: AppConfig.listViewCacheExtent.toDouble(),
                        addAutomaticKeepAlives: false,
                        addRepaintBoundaries: true,
                        itemBuilder: (context, index) {
                          final entry = widget.currentUser != null && 
                                       filteredEntries[index].ownerId == widget.currentUser!.userId &&
                                       filteredEntries[index].ownerName.isEmpty
                            ? filteredEntries[index].copyWith(ownerName: widget.currentUser!.fullName)
                            : filteredEntries[index];
                          
                          // Sadece entry'nin sahibi silme yapabilir
                          final canDelete = widget.currentUser != null && 
                                          entry.ownerId == widget.currentUser!.userId;
                          
                          return RepaintBoundary(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: EntryCard(
                                entry: entry,
                                onDelete: canDelete ? () => _deleteEntry(context, entry) : null,
                              ),
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

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin için gerekli
    final theme = Theme.of(context);
    final isSmallScreen = MediaQuery.of(context).size.width < 600;
    return Scaffold(
      body: _buildContent(theme, isSmallScreen),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openExcel(context),
        icon: const Icon(Icons.table_chart_rounded),
        label: const Text('Excel'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
      ),
    );
  }
}

