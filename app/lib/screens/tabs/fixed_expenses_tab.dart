/**
 * Sabit Giderler sekmesi
 * Sabit giderleri görüntüleme ve ekleme
 */

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../home_screen.dart';
import '../../utils/app_logger.dart';
import '../../services/firestore_service.dart';
import '../../models/fixed_expense.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/error_retry_widget.dart';
import '../../widgets/loading_widget.dart';
import '../../services/upload_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'dart:io';

class FixedExpensesTab extends StatefulWidget {
  final UserProfile? currentUser;

  const FixedExpensesTab({
    super.key,
    this.currentUser,
  });

  @override
  State<FixedExpensesTab> createState() => _FixedExpensesTabState();
}

class _FixedExpensesTabState extends State<FixedExpensesTab> with AutomaticKeepAliveClientMixin {
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _categoryController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  DateTime? _selectedStartDate;
  String? _selectedRecurrence;
  bool _isActive = true;
  bool _isAdding = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _descriptionController.dispose();
    _amountController.dispose();
    _categoryController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _addFixedExpense() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null || widget.currentUser == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Kullanıcı oturumu bulunamadı. Lütfen tekrar giriş yapın.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    setState(() {
      _isAdding = true;
    });

    try {
      // Miktarı parse et (Türkçe format: 1.234,56)
      final amountText = _amountController.text.replaceAll('.', '').replaceAll(',', '.');
      final amount = double.tryParse(amountText) ?? 0.0;

      if (amount <= 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Geçerli bir miktar giriniz.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        setState(() {
          _isAdding = false;
        });
        return;
      }

      final fixedExpense = FixedExpense(
        ownerId: currentUser.uid,
        ownerName: widget.currentUser!.fullName,
        description: _descriptionController.text.trim(),
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        amount: amount,
        category: _categoryController.text.trim().isEmpty ? null : _categoryController.text.trim(),
        startDate: _selectedStartDate,
        recurrence: _selectedRecurrence,
        isActive: _isActive,
      );

      await FirestoreService.addFixedExpense(fixedExpense);

      if (mounted) {
        // Modal'ı kapat
        Navigator.of(context).pop();
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sabit gider başarıyla eklendi.'),
            backgroundColor: Colors.green,
          ),
        );

        // Formu temizle
        _formKey.currentState!.reset();
        _descriptionController.clear();
        _amountController.clear();
        _categoryController.clear();
        _notesController.clear();
        setState(() {
          _selectedStartDate = null;
          _selectedRecurrence = null;
          _isActive = true;
        });

        // CSV dosyasını güncelle (non-blocking, arka planda)
        _updateGoogleSheetsInBackground();
      }
    } catch (e) {
      AppLogger.error('Sabit gider ekleme hatası', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sabit gider eklenirken hata oluştu: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAdding = false;
        });
      }
    }
  }

  /// Tüm Excel dosyalarını arka planda güncelle (non-blocking)
  Future<void> _updateGoogleSheetsInBackground() async {
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
          'fileUrl': entry.fileUrl ?? '',
        };
      }).toList();

      // 2. Tüm sabit giderleri al
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

      // 3. Tüm Excel dosyalarını paralel olarak güncelle (hata olsa bile devam et)
      await Future.wait([
        // Tüm entry'ler Excel'i
        UploadService.initializeGoogleSheetsWithEntries(formattedAllEntries).catchError((e) {
          AppLogger.warning('Tüm entry\'ler Excel güncellenirken hata: $e');
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

      AppLogger.info('Tüm Excel dosyaları güncellendi (${formattedAllEntries.length} entry, ${formattedFixedExpenses.length} sabit gider)');
    } catch (e) {
      // Hata olsa bile kullanıcıyı rahatsız etme, sadece log'a yaz
      AppLogger.warning('Excel dosyaları güncellenirken genel hata (non-blocking): $e');
    }
  }

  Future<void> _selectStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedStartDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      locale: const Locale('tr', 'TR'),
      helpText: 'Başlangıç Tarihi Seçin',
      cancelText: 'İptal',
      confirmText: 'Seç',
    );
    if (picked != null) {
      setState(() {
        _selectedStartDate = picked;
      });
    }
  }

  Future<void> _openGoogleSheets() async {
    try {
      AppLogger.info('📊 Excel açma işlemi başlatıldı (Sabit Giderler)');
      
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

      // Tüm sabit giderleri al
      AppLogger.info('Firestore\'dan sabit giderler alınıyor...');
      final fixedExpenses = await FirestoreService.getAllFixedExpenses();
      AppLogger.info('${fixedExpenses.length} sabit gider bulundu');

      if (!mounted) return;

      if (fixedExpenses.isEmpty) {
        AppLogger.warning('Sabit gider bulunamadı, işlem iptal ediliyor');
        Navigator.of(context).pop(); // Loading dialog'u kapat
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Henüz sabit gider bulunmuyor.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 4),
            ),
          );
        }
        return;
      }

      // Sabit giderleri formatla (backend'in beklediği formatta)
      AppLogger.debug('Sabit giderler formatlanıyor...');
      final formattedExpenses = fixedExpenses.map((expense) {
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
      AppLogger.debug('${formattedExpenses.length} sabit gider formatlandı');

      // Google Sheets'i oluştur/aç
      AppLogger.info('Excel dosyası oluşturuluyor/güncelleniyor...');
      final result = await UploadService.initializeGoogleSheetsWithFixedExpenses(formattedExpenses);
      AppLogger.debug('Excel oluşturma sonucu: ${result != null ? "Başarılı" : "Başarısız"}');

      if (!mounted) return;
      Navigator.of(context).pop(); // Loading dialog'u kapat

      if (result != null && result['url'] != null) {
        final sheetsUrl = result['url'] as String;
        AppLogger.info('Excel URL alındı: $sheetsUrl');
        
        // File ID'yi çıkar
        String? fileId;
        if (sheetsUrl.contains('drive.google.com')) {
          AppLogger.debug('Google Drive URL tespit edildi, File ID çıkarılıyor...');
          // Format 1: /file/d/FILE_ID/view veya /file/d/FILE_ID
          final fileIdMatch1 = RegExp(r'/file/d/([a-zA-Z0-9_-]+)').firstMatch(sheetsUrl);
          if (fileIdMatch1 != null) {
            fileId = fileIdMatch1.group(1);
            AppLogger.debug('File ID bulundu (format 1): $fileId');
          } else {
            // Format 2: id=FILE_ID
            final fileIdMatch2 = RegExp(r'[?&]id=([a-zA-Z0-9_-]+)').firstMatch(sheetsUrl);
            if (fileIdMatch2 != null) {
              fileId = fileIdMatch2.group(1);
              AppLogger.debug('File ID bulundu (format 2): $fileId');
            }
          }
        }
        
        if (fileId != null) {
          // Excel dosyasını indirip lokal aç (hesap seçimi olmadan)
          await _openExcelFromDrive(context, fileId, formattedExpenses.length);
        } else {
          AppLogger.warning('File ID bulunamadı, orijinal URL kullanılıyor');
          // Fallback: Orijinal URL'i aç
          final uri = Uri.parse(sheetsUrl);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        }
      } else {
        AppLogger.error('Excel oluşturulamadı (result null veya url yok)');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Excel oluşturulamadı. Lütfen tekrar deneyin.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e, stackTrace) {
      AppLogger.error('Excel açma hatası', e, stackTrace);
      if (!mounted) return;
      Navigator.of(context).pop(); // Loading dialog'u kapat

      String errorMessage = 'Google Sheets oluşturulurken hata oluştu';
      final errorString = e.toString().toLowerCase();

      if (errorString.contains('permission') || errorString.contains('permission denied')) {
        errorMessage = 'Firestore izin hatası. Lütfen Firebase Console\'da güvenlik kurallarını kontrol edin.';
      } else if (errorString.contains('timeout') || errorString.contains('connection') || errorString.contains('network')) {
        errorMessage = 'Bağlantı zaman aşımı. İnternet bağlantınızı kontrol edip tekrar deneyin.';
      } else if (errorString.contains('not found') || errorString.contains('404')) {
        errorMessage = 'Backend servisi bulunamadı. Lütfen daha sonra tekrar deneyin.';
      } else if (errorString.contains('500') || errorString.contains('internal')) {
        errorMessage = 'Sunucu hatası. Lütfen daha sonra tekrar deneyin.';
      } else {
        errorMessage = 'Hata: ${e.toString()}';
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    }
  }

  /// Excel dosyasını Google Drive'dan indirip geçici olarak saklayıp açar (hesap seçimi olmadan)
  Future<void> _openExcelFromDrive(BuildContext context, String fileId, int entryCount) async {
    try {
      AppLogger.info('📥 Excel dosyası indirme işlemi başlatıldı');
      AppLogger.debug('File ID: $fileId');
      
      // Loading göster
      if (context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: CircularProgressIndicator(),
          ),
        );
      }
      
      // Önce backend'den indirmeyi dene
      List<int>? fileBytes;
      try {
        AppLogger.debug('Backend üzerinden dosya indiriliyor...');
        fileBytes = await UploadService.downloadFileFromDrive(fileId);
        if (fileBytes != null && fileBytes.isNotEmpty) {
          AppLogger.success('Backend üzerinden dosya başarıyla indirildi');
        }
      } catch (backendError) {
        AppLogger.warning('Backend download başarısız, direkt Google Drive URL deneniyor...');
        // Fallback: Direkt Google Drive download URL'i kullan
        try {
          final directUrl = 'https://drive.google.com/uc?export=download&id=$fileId&confirm=t';
          AppLogger.debug('Direkt download URL: $directUrl');
          final directResponse = await http.get(Uri.parse(directUrl));
          if (directResponse.statusCode == 200 && directResponse.bodyBytes.isNotEmpty) {
            fileBytes = directResponse.bodyBytes;
            AppLogger.success('Direkt Google Drive URL ile dosya başarıyla indirildi');
          } else {
            throw Exception('Direkt download da başarısız: ${directResponse.statusCode}');
          }
        } catch (directError) {
          AppLogger.error('Direkt download da başarısız', directError);
          // Loading'i kapat
          if (context.mounted) {
            Navigator.of(context).pop();
          }
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Excel dosyası indirilemedi. Lütfen tekrar deneyin.'),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 3),
              ),
            );
          }
          return;
        }
      }

      if (fileBytes != null && fileBytes.isNotEmpty) {
        AppLogger.success('Dosya başarıyla indirildi (${fileBytes.length} bytes)');
        
        // Geçici dizin al
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/excel_$fileId.csv');
        AppLogger.debug('Geçici dosya yolu: ${file.path}');
        
        // Dosyayı kaydet
        AppLogger.debug('Dosya geçici dizine kaydediliyor...');
        await file.writeAsBytes(fileBytes);
        AppLogger.success('Dosya geçici dizine kaydedildi');
        
        // Loading'i kapat
        if (context.mounted) {
          Navigator.of(context).pop();
        }

        // Android/iOS için open_file kullan, diğer platformlar için url_launcher
        if (Platform.isAndroid || Platform.isIOS) {
          AppLogger.info('Mobil platform tespit edildi, open_file ile dosya açılıyor...');
          try {
            // OpenFile.open() ile dosyayı aç (hesap seçimi olmadan, MIME type belirtilerek)
            final result = await OpenFile.open(
              file.path,
              type: 'text/csv', // CSV MIME type
            );
            if (result.type == ResultType.done) {
              AppLogger.success('Excel dosyası başarıyla açıldı');
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Excel açılıyor... ($entryCount sabit gider)'),
                    backgroundColor: Colors.green,
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            } else {
              AppLogger.warning('Dosya açılamadı: ${result.message}');
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Excel açılamadı: ${result.message}'),
                    backgroundColor: Colors.orange,
                    duration: const Duration(seconds: 3),
                  ),
                );
              }
            }
          } catch (openError) {
            AppLogger.error('Open file hatası', openError);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Excel açma hatası: ${openError.toString()}'),
                  backgroundColor: Colors.red,
                  duration: const Duration(seconds: 3),
                ),
              );
            }
          }
        } else {
          // Diğer platformlar için url_launcher
          final uri = Uri.file(file.path);
          AppLogger.info('Dosya açılıyor: $uri');
          if (await canLaunchUrl(uri)) {
            AppLogger.success('Dosya açılabilir, açılıyor...');
            await launchUrl(uri, mode: LaunchMode.externalApplication);
            AppLogger.success('Excel dosyası başarıyla açıldı');
          } else {
            AppLogger.error('Dosya açılamıyor (canLaunchUrl false döndü)');
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Excel açılamadı. Lütfen uygun bir uygulama yükleyin.'),
                  backgroundColor: Colors.red,
                  duration: const Duration(seconds: 3),
                ),
              );
            }
          }
        }
      } else {
        // Dosya boşsa
        AppLogger.warning('Dosya boş');
        if (context.mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Excel dosyası boş veya indirilemedi.'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e, stackTrace) {
      AppLogger.error('Excel açma hatası', e, stackTrace);
      // Loading'i kapat
      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Excel açma hatası: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final isSmallScreen = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      body: Column(
        children: [
          // Kompakt başlık ve Google Sheets butonu
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
                  'Sabit Giderler',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
          // Liste görünümü
          Expanded(
            child: _buildListTab(theme, isSmallScreen),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.extended(
            onPressed: () => _openGoogleSheets(),
            icon: const Icon(Icons.table_chart_rounded),
            label: const Text('Excel'),
            backgroundColor: theme.colorScheme.secondary,
            foregroundColor: theme.colorScheme.onSecondary,
            heroTag: 'excel_button',
          ),
          const SizedBox(height: 16),
          FloatingActionButton.extended(
            onPressed: () => _showAddExpenseDialog(context, theme, isSmallScreen),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Ekle'),
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: theme.colorScheme.onPrimary,
            heroTag: 'add_button',
          ),
        ],
      ),
    );
  }

  void _showAddExpenseDialog(BuildContext context, ThemeData theme, bool isSmallScreen) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outline.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Yeni Sabit Gider Ekle',
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
            ),
            // Form içeriği
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: _buildAddForm(theme, isSmallScreen),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildListTab(ThemeData theme, bool isSmallScreen) {
    return StreamBuilder<List<FixedExpense>>(
      stream: FirestoreService.streamAllFixedExpenses(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const LoadingWidget(message: 'Sabit giderler yükleniyor...');
        }

        if (snapshot.hasError) {
          final errorMessage = snapshot.error.toString();
          AppLogger.error('FixedExpensesTab StreamBuilder hatası', snapshot.error);
          
          String userMessage = 'Sabit giderler yüklenirken bir hata oluştu';
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

        final expenses = snapshot.data ?? [];

        if (expenses.isEmpty) {
          return EmptyStateWidget(
            title: 'Henüz sabit gider yok',
            subtitle: 'İlk sabit gideri eklemek için sağ alttaki "+" butonuna tıklayın',
            icon: Icons.receipt_long,
          );
        }

        // Aktif ve pasif giderleri ayır
        final activeExpenses = expenses.where((e) => e.isActive).toList();
        final inactiveExpenses = expenses.where((e) => !e.isActive).toList();

        // Toplam hesapla
        final totalAmount = expenses.fold<double>(
          0.0,
          (sum, expense) => sum + (expense.isActive ? expense.amount : 0),
        );

        return RefreshIndicator(
          onRefresh: () async {
            await Future.delayed(const Duration(milliseconds: 500));
          },
          child: ListView(
            padding: EdgeInsets.all(isSmallScreen ? 16 : 20),
            children: [
              // Toplam kartı
              Card(
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Toplam Sabit Gider',
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            NumberFormat.currency(
                              symbol: '₺',
                              decimalDigits: 2,
                              locale: 'tr_TR',
                            ).format(totalAmount),
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                      Icon(
                        Icons.account_balance_wallet_rounded,
                        size: 40,
                        color: theme.colorScheme.primary,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Aktif giderler
              if (activeExpenses.isNotEmpty) ...[
                Text(
                  'Aktif Giderler',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                ...activeExpenses.map((expense) => RepaintBoundary(
                  child: _buildExpenseCard(expense, theme, isSmallScreen),
                )),
                const SizedBox(height: 16),
              ],
              // Pasif giderler
              if (inactiveExpenses.isNotEmpty) ...[
                Text(
                  'Pasif Giderler',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 8),
                ...inactiveExpenses.map((expense) => RepaintBoundary(
                  child: _buildExpenseCard(expense, theme, isSmallScreen),
                )),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildExpenseCard(FixedExpense expense, ThemeData theme, bool isSmallScreen) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: EdgeInsets.all(isSmallScreen ? 12 : 16),
        leading: CircleAvatar(
          backgroundColor: expense.isActive
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          child: Icon(
            expense.isActive ? Icons.check_circle : Icons.cancel,
            color: expense.isActive
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
        title: Text(
          expense.description,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (expense.category != null) ...[
              Text(
                'Kategori: ${expense.category}',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
            ],
            if (expense.startDate != null)
              Text(
                'Başlangıç: ${DateFormat('dd.MM.yyyy', 'tr_TR').format(expense.startDate!)}',
                style: theme.textTheme.bodySmall,
              ),
            if (expense.recurrence != null)
              Text(
                'Tekrarlama: ${_getRecurrenceText(expense.recurrence!)}',
                style: theme.textTheme.bodySmall,
              ),
            if (expense.notes != null && expense.notes!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                expense.notes!,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontStyle: FontStyle.italic,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 4),
            Text(
              expense.ownerName,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
        trailing: Text(
          NumberFormat.currency(
            symbol: '₺',
            decimalDigits: 2,
            locale: 'tr_TR',
          ).format(expense.amount),
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.primary,
          ),
        ),
        isThreeLine: true,
      ),
    );
  }

  String _getRecurrenceText(String recurrence) {
    switch (recurrence) {
      case 'monthly':
        return 'Aylık';
      case 'yearly':
        return 'Yıllık';
      case 'one-time':
        return 'Tek Seferlik';
      default:
        return recurrence;
    }
  }

  Widget _buildAddForm(ThemeData theme, bool isSmallScreen) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
            // Açıklama
            TextFormField(
              controller: _descriptionController,
              decoration: InputDecoration(
                labelText: 'Açıklama *',
                hintText: 'Örn: Üretim Maliyeti',
                prefixIcon: const Icon(Icons.description_rounded),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Açıklama gereklidir';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            // Miktar
            TextFormField(
              controller: _amountController,
              decoration: InputDecoration(
                labelText: 'Miktar *',
                hintText: 'Örn: 1.500,00',
                prefixIcon: const Icon(Icons.currency_lira_rounded),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              keyboardType: TextInputType.text,
              inputFormatters: [
                _TurkishNumberInputFormatter(),
              ],
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Miktar gereklidir';
                }
                final amountText = value.replaceAll('.', '').replaceAll(',', '.');
                final amount = double.tryParse(amountText);
                if (amount == null || amount <= 0) {
                  return 'Geçerli bir miktar giriniz';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            // Kategori (opsiyonel)
            TextFormField(
              controller: _categoryController,
              decoration: InputDecoration(
                labelText: 'Kategori (Opsiyonel)',
                hintText: 'Örn: Ürün',
                prefixIcon: const Icon(Icons.category_rounded),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Başlangıç tarihi
            InkWell(
              onTap: _selectStartDate,
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Başlangıç Tarihi (Opsiyonel)',
                  prefixIcon: const Icon(Icons.calendar_today_rounded),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  _selectedStartDate != null
                      ? DateFormat('dd.MM.yyyy', 'tr_TR').format(_selectedStartDate!)
                      : 'Tarih seçin',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: _selectedStartDate != null
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Tekrarlama
            DropdownButtonFormField<String>(
              value: _selectedRecurrence,
              decoration: InputDecoration(
                labelText: 'Tekrarlama (Opsiyonel)',
                prefixIcon: const Icon(Icons.repeat_rounded),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              items: const [
                DropdownMenuItem(value: 'monthly', child: Text('Aylık')),
                DropdownMenuItem(value: 'yearly', child: Text('Yıllık')),
                DropdownMenuItem(value: 'one-time', child: Text('Tek Seferlik')),
              ],
              onChanged: (value) {
                setState(() {
                  _selectedRecurrence = value;
                });
              },
            ),
            const SizedBox(height: 16),
            // Notlar (opsiyonel)
            TextFormField(
              controller: _notesController,
              decoration: InputDecoration(
                labelText: 'Notlar (Opsiyonel)',
                hintText: 'Ek bilgiler...',
                prefixIcon: const Icon(Icons.note_rounded),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            // Aktif/Pasif
            SwitchListTile(
              title: const Text('Aktif'),
              subtitle: const Text('Pasif yapıldığında toplam hesaplamaya dahil edilmez'),
              value: _isActive,
              onChanged: (value) {
                setState(() {
                  _isActive = value;
                });
              },
            ),
            const SizedBox(height: 24),
            // Ekle butonu
            ElevatedButton.icon(
              onPressed: _isAdding ? null : _addFixedExpense,
              icon: _isAdding
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_rounded),
              label: Text(_isAdding ? 'Ekleniyor...' : 'Sabit Gider Ekle'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// Türkçe sayı formatı için input formatter
// Binlik ayırıcı: nokta (.), ondalık ayırıcı: virgül (,)
class _TurkishNumberInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue;
    }

    // Sadece rakam, nokta ve virgül kabul et
    String text = newValue.text.replaceAll(RegExp(r'[^\d.,]'), '');
    
    // Virgül sadece bir kez olabilir (ondalık ayırıcı)
    final commaCount = text.split(',').length - 1;
    if (commaCount > 1) {
      return oldValue;
    }
    
    // Virgülden sonra maksimum 2 rakam
    if (text.contains(',')) {
      final parts = text.split(',');
      if (parts.length == 2 && parts[1].length > 2) {
        return oldValue;
      }
    }
    
    // Noktalar sadece binlik ayırıcı olarak kullanılabilir (virgülden önce)
    String formatted = text;
    if (text.contains(',')) {
      final parts = text.split(',');
      final integerPart = parts[0].replaceAll('.', '');
      final decimalPart = parts[1];
      
      // Binlik ayırıcıları ekle (sağdan sola 3'er 3'er)
      String formattedInteger = '';
      for (int i = integerPart.length - 1; i >= 0; i--) {
        formattedInteger = integerPart[i] + formattedInteger;
        if ((integerPart.length - i) % 3 == 0 && i > 0) {
          formattedInteger = '.' + formattedInteger;
        }
      }
      
      formatted = formattedInteger + ',' + decimalPart;
    } else {
      // Virgül yoksa, sadece binlik ayırıcıları ekle
      final integerPart = text.replaceAll('.', '');
      String formattedInteger = '';
      for (int i = integerPart.length - 1; i >= 0; i--) {
        formattedInteger = integerPart[i] + formattedInteger;
        if ((integerPart.length - i) % 3 == 0 && i > 0) {
          formattedInteger = '.' + formattedInteger;
        }
      }
      formatted = formattedInteger;
    }
    
    // Cursor pozisyonunu hesapla (formatlamadan sonra)
    int cursorPosition = formatted.length;
    if (newValue.selection.baseOffset <= oldValue.text.length) {
      // Eski pozisyonu korumaya çalış
      final oldText = oldValue.text;
      final newText = formatted;
      final offset = newValue.selection.baseOffset;
      
      if (offset <= oldText.length) {
        // Formatlamadan önceki karakter sayısını hesapla
        final charsBeforeCursor = oldText.substring(0, offset).replaceAll(RegExp(r'[^\d]'), '').length;
        
        // Formatlamadan sonra aynı sayıda karaktere kadar cursor'ı ayarla
        int count = 0;
        cursorPosition = 0;
        for (int i = 0; i < newText.length && count < charsBeforeCursor; i++) {
          if (RegExp(r'\d').hasMatch(newText[i])) {
            count++;
          }
          cursorPosition = i + 1;
        }
      }
    }
    
    if (cursorPosition > formatted.length) {
      cursorPosition = formatted.length;
    }
    
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: cursorPosition),
    );
  }
}

