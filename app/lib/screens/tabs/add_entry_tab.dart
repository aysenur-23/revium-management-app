/**
 * Ekleme sekmesi
 * Yeni harcama kaydı eklemek için form
 */

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';
import '../home_screen.dart';
import '../../services/upload_service.dart';
import '../../services/firestore_service.dart';
import '../../services/connectivity_service.dart';
import '../../widgets/primary_button.dart';
import '../../models/fixed_expense.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../utils/app_logger.dart';

class AddEntryTab extends StatefulWidget {
  final UserProfile currentUser;

  const AddEntryTab({
    super.key,
    required this.currentUser,
  });

  @override
  State<AddEntryTab> createState() => _AddEntryTabState();
}

class _AddEntryTabState extends State<AddEntryTab> with AutomaticKeepAliveClientMixin {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final _notesController = TextEditingController(); // Opsiyonel açıklama
  final _amountController = TextEditingController();
  File? _selectedFile; // Mobil için
  Uint8List? _selectedFileBytes; // Web için
  String? _selectedFileName;
  bool _isUploading = false;
  String? _selectedFixedExpenseId; // Seçilen sabit gider ID'si

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _descriptionController.dispose();
    _notesController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  /// Tüm Excel dosyalarını arka planda güncelle (hata olsa bile devam et)
  Future<void> _updateExcelFileInBackground() async {
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

      // 2. Kullanıcının entry'lerini çek
      final myEntries = await FirestoreService.getMyEntries(widget.currentUser.userId);
      final formattedMyEntries = myEntries.map((entry) {
        return {
          'createdAt': entry.createdAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
          'notes': entry.notes ?? '',
          'ownerName': entry.ownerName,
          'amount': entry.amount,
          'description': entry.description,
          'fileUrl': entry.fileUrl ?? '',
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
        }),
        // Kullanıcının entry'leri Excel'i
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

      AppLogger.info('Tüm Excel dosyaları güncellendi (${formattedAllEntries.length} entry, ${formattedFixedExpenses.length} sabit gider)');
    } catch (e) {
      // Hata olsa bile sessizce devam et (kullanıcıyı rahatsız etme)
      AppLogger.warning('Excel dosyaları güncellenirken genel hata: $e');
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
        withData: kIsWeb, // Web için dosya baytlarını al
      );

      if (result != null && result.files.isNotEmpty && result.files.single.name.isNotEmpty) {
        final platformFile = result.files.single;
        final fileName = platformFile.name;
        final fileSize = platformFile.size;
        const maxFileSize = 50 * 1024 * 1024; // 50MB

        if (fileSize > maxFileSize) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Dosya boyutu çok büyük. Maksimum 50MB olmalıdır.'),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        }

        // Dosya uzantısı kontrolü
        final extension = fileName.toLowerCase().split('.').last;
        final allowedExtensions = ['jpg', 'jpeg', 'png', 'pdf'];
        if (!allowedExtensions.contains(extension)) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Sadece PNG, JPEG, JPG ve PDF dosyaları desteklenmektedir.'),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        }

        setState(() {
          _selectedFileName = fileName;
          if (kIsWeb) {
            _selectedFileBytes = platformFile.bytes;
            _selectedFile = null; // Web'de File objesi kullanmıyoruz
          } else {
            if (platformFile.path != null && platformFile.path!.isNotEmpty) {
              _selectedFile = File(platformFile.path!);
              _selectedFileBytes = null;
            } else {
              throw Exception('Dosya yolu alınamadı. Lütfen tekrar deneyin.');
            }
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Dosya seçme hatası: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _getFileType(String? fileName) {
    if (fileName == null) return 'image';
    final extension = fileName.toLowerCase().split('.').last;
    return extension == 'pdf' ? 'pdf' : 'image';
  }

  Future<void> _saveEntry() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedFileName == null ||
        (kIsWeb && _selectedFileBytes == null) ||
        (!kIsWeb && _selectedFile == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lütfen bir dosya seçiniz'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Dosya boyutu kontrolü (50MB limit)
    final fileSize = kIsWeb
        ? _selectedFileBytes!.length
        : await _selectedFile!.length();
    const maxFileSize = 50 * 1024 * 1024; // 50MB
    if (fileSize > maxFileSize) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dosya boyutu çok büyük. Maksimum 50MB olmalıdır.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // İnternet bağlantısı kontrolü
    final hasInternet = await ConnectivityService.hasInternetConnection();
    if (!hasInternet) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('İnternet bağlantısı yok. Lütfen bağlantınızı kontrol edin.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isUploading = true;
    });

    // Upload progress dialog göster
    BuildContext? dialogContext;
    bool dialogShown = false;

    // Dialog'u göster
    if (mounted) {
      await Future.delayed(const Duration(milliseconds: 100)); // UI güncellemesi için bekle
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (dialogCtx) {
            dialogContext = dialogCtx;
            return PopScope(
              canPop: false,
              child: AlertDialog(
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      'Dosya yükleniyor...',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            );
          },
        );
        dialogShown = true;
      }
    }

    try {
      // Miktarı parse et (Türkçe format: nokta binlik, virgül ondalık)
      final amountText = _amountController.text.trim()
          .replaceAll('.', '') // Binlik ayırıcıları kaldır
          .replaceAll(',', '.'); // Ondalık ayırıcıyı noktaya çevir
      final amount = double.tryParse(amountText);
      if (amount == null || amount <= 0) {
        throw Exception('Geçersiz miktar. Lütfen geçerli bir sayı girin.');
      }

      // Backend'e dosya yükle
      UploadResult uploadResult;
      try {
        uploadResult = await UploadService.uploadFile(
          file: kIsWeb ? null : _selectedFile,
          fileBytes: kIsWeb ? _selectedFileBytes : null,
          fileName: _selectedFileName,
          ownerId: widget.currentUser.userId,
          ownerName: widget.currentUser.fullName,
          amount: amount,
          description: _descriptionController.text.trim(),
          notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        );
      } catch (uploadError) {
        // Upload hatası - dialog'u kapat ve hatayı fırlat
        if (dialogShown && mounted) {
          _closeDialogSafely(dialogContext, dialogShown);
          dialogShown = false;
        }
        rethrow;
      }
      
      // Başarılı olduysa dialog'u kapat
      if (dialogShown && mounted) {
        _closeDialogSafely(dialogContext, dialogShown);
        dialogShown = false;
      }

      // MIME type ve dosya adını belirle
      if (_selectedFileName == null || _selectedFileName!.isEmpty) {
        throw Exception('Dosya adı bulunamadı');
      }
      final extension = _selectedFileName!.toLowerCase().split('.').last;
      String mimeType;
      if (extension == 'pdf') {
        mimeType = 'application/pdf';
      } else if (['jpg', 'jpeg'].contains(extension)) {
        mimeType = 'image/jpeg';
      } else if (extension == 'png') {
        mimeType = 'image/png';
      } else {
        mimeType = 'application/octet-stream';
      }
      
      // fileType'ı belirle (legacy uyumluluk için)
      String fileType;
      if (extension == 'pdf') {
        fileType = 'pdf';
      } else {
        fileType = 'image';
      }

      // ExpenseEntry oluştur
      final entry = ExpenseEntry(
        ownerId: widget.currentUser.userId,
        ownerName: widget.currentUser.fullName,
        description: _descriptionController.text.trim(),
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        amount: amount,
        fileUrl: uploadResult.fileUrl,
        fileType: fileType,
        driveFileId: uploadResult.fileId,
        mimeType: mimeType,
        fileName: _selectedFileName,
        fixedExpenseId: _selectedFixedExpenseId,
      );

      // Firestore'a kaydet
      await FirestoreService.addEntry(entry);

      // Excel dosyasını güncelle (arka planda, hata olsa bile devam et)
      _updateExcelFileInBackground();

      // Formu temizle
      _descriptionController.clear();
      _notesController.clear();
      _amountController.clear();
      setState(() {
        _selectedFile = null;
        _selectedFileBytes = null;
        _selectedFileName = null;
        _selectedFixedExpenseId = null;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Kayıt başarıyla eklendi'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e, stackTrace) {
      AppLogger.error('Kayıt ekleme hatası', e, stackTrace);
      
      // Hata mesajını hazırla
      final errorMessage = e.toString();
      String userMessage = 'Kayıt ekleme hatası';
      
      if (errorMessage.contains('zaman aşımı') || errorMessage.contains('timeout')) {
        userMessage = 'Dosya yükleme zaman aşımı. İnternet bağlantınızı kontrol edin.';
      } else if (errorMessage.contains('bağlanılamadı') || errorMessage.contains('connection') || errorMessage.contains('SocketException')) {
        userMessage = 'Backend sunucusuna bağlanılamıyor. İnternet bağlantınızı kontrol edin.';
      } else if (errorMessage.contains('500') || errorMessage.contains('Internal')) {
        userMessage = 'Backend sunucusunda bir hata oluştu. Lütfen daha sonra tekrar deneyin.';
      } else if (errorMessage.contains('401') || errorMessage.contains('403') || errorMessage.contains('authorization')) {
        userMessage = 'Yetkilendirme hatası. Backend ayarlarını kontrol edin.';
      } else if (errorMessage.contains('404')) {
        userMessage = 'Backend endpoint bulunamadı. Backend URL\'ini kontrol edin.';
      } else {
        userMessage = 'Hata: ${errorMessage.length > 100 ? errorMessage.substring(0, 100) + "..." : errorMessage}';
      }
      
      // Dialog'u hata mesajı ile değiştir
      if (dialogShown && mounted && dialogContext != null) {
        Navigator.of(dialogContext!, rootNavigator: true).pop(); // Progress dialog'u kapat
        await Future.delayed(const Duration(milliseconds: 200));
        
        // Hata dialog'unu göster
        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: true,
            builder: (ctx) => AlertDialog(
              title: const Text('Hata'),
              content: Text(userMessage),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                  },
                  child: const Text('Tamam'),
                ),
              ],
            ),
          );
        }
      } else if (mounted) {
        // Dialog yoksa SnackBar göster
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(userMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
              label: 'Tamam',
              textColor: Colors.white,
              onPressed: () {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
              },
            ),
          ),
        );
      }
    } finally {
      // Dialog'u kesinlikle kapat (eğer hala açıksa)
      if (dialogShown && mounted) {
        _closeDialogSafely(dialogContext, dialogShown);
        dialogShown = false;
      }
      
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  /// Dialog'u güvenli bir şekilde kapatır
  void _closeDialogSafely(BuildContext? dialogContext, bool dialogShown) {
    if (!dialogShown) {
      return;
    }

    try {
      // Önce dialog context ile dene
      if (dialogContext != null && mounted) {
        try {
          final navigator = Navigator.of(dialogContext, rootNavigator: true);
          if (navigator.canPop()) {
            navigator.pop();
            AppLogger.debug('Dialog dialogContext ile kapatıldı');
            return;
          }
        } catch (e) {
          AppLogger.warning('Dialog kapatma hatası (dialogContext): $e');
        }
      }
      
      // Ana context ile kapat
      if (mounted) {
        try {
          final navigator = Navigator.of(context, rootNavigator: true);
          if (navigator.canPop()) {
            navigator.pop();
            AppLogger.debug('Dialog ana context ile kapatıldı');
          } else {
            AppLogger.warning('Dialog zaten kapatılmış (canPop false)');
          }
        } catch (e) {
          AppLogger.warning('Dialog kapatma hatası (ana context): $e');
        }
      }
    } catch (e) {
      AppLogger.error('Dialog kapatma genel hatası', e);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final padding = MediaQuery.of(context).size.width < 360 ? 16.0 : 24.0;
    final spacing = MediaQuery.of(context).size.width < 360 ? 20.0 : 24.0;

    return SingleChildScrollView(
      padding: EdgeInsets.all(padding),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Kompakt başlık
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Yeni Harcama Ekle',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                ),
              ),
            ),
            // Harcama Kalemi
            TextFormField(
              controller: _descriptionController,
              decoration: InputDecoration(
                labelText: 'Harcama Kalemi',
                hintText: 'Örn: Üretim Maliyeti',
                prefixIcon: Icon(
                  Icons.description_outlined,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: theme.colorScheme.outline.withValues(alpha: 0.2),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: theme.colorScheme.outline.withValues(alpha: 0.2),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: theme.colorScheme.primary,
                    width: 2,
                  ),
                ),
                filled: true,
                fillColor: theme.colorScheme.surface,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Lütfen harcama kalemi giriniz';
                }
                if (value.trim().length < 3) {
                  return 'Harcama kalemi en az 3 karakter olmalıdır';
                }
                if (value.trim().length > 100) {
                  return 'Harcama kalemi en fazla 100 karakter olabilir';
                }
                return null;
              },
              enabled: !_isUploading,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
            // Miktar
            TextFormField(
              controller: _amountController,
              decoration: InputDecoration(
                labelText: 'Miktar (₺)',
                hintText: 'Örn: 1.234,56',
                prefixIcon: Icon(
                  Icons.account_balance_wallet_outlined,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: theme.colorScheme.outline.withValues(alpha: 0.2),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: theme.colorScheme.outline.withValues(alpha: 0.2),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: theme.colorScheme.primary,
                    width: 2,
                  ),
                ),
                filled: true,
                fillColor: theme.colorScheme.surface,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
              ),
              keyboardType: TextInputType.text,
              inputFormatters: [
                _TurkishNumberInputFormatter(),
              ],
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Lütfen miktar giriniz';
                }
                // Türkçe format: nokta binlik ayırıcı, virgül ondalık ayırıcı
                // Parse için: noktaları kaldır, virgülü noktaya çevir
                final cleanedValue = value.trim()
                    .replaceAll('.', '') // Binlik ayırıcıları kaldır
                    .replaceAll(',', '.'); // Ondalık ayırıcıyı noktaya çevir
                final amount = double.tryParse(cleanedValue);
                if (amount == null) {
                  return 'Geçerli bir sayı giriniz (örn: 1.234,56)';
                }
                if (amount <= 0) {
                  return 'Miktar 0\'dan büyük olmalıdır';
                }
                if (amount > 999999999) {
                  return 'Miktar çok büyük (maksimum: 999.999.999,99)';
                }
                return null;
              },
              enabled: !_isUploading,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
            // Sabit Gider Seçimi (Opsiyonel)
            StreamBuilder<List<FixedExpense>>(
              stream: FirestoreService.streamAllFixedExpenses(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox.shrink();
                }
                
                final fixedExpenses = snapshot.data ?? [];
                final activeExpenses = fixedExpenses.where((e) => e.isActive).toList();
                
                if (activeExpenses.isEmpty) {
                  return const SizedBox.shrink();
                }
                
                return DropdownButtonFormField<String>(
                  value: _selectedFixedExpenseId,
                  decoration: InputDecoration(
                    labelText: 'Sabit Gider (Opsiyonel)',
                    hintText: 'Bir sabit gidere bağla',
                    prefixIcon: Icon(
                      Icons.receipt_long_rounded,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: theme.colorScheme.outline.withValues(alpha: 0.2),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: theme.colorScheme.outline.withValues(alpha: 0.2),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: theme.colorScheme.primary,
                        width: 2,
                      ),
                    ),
                    filled: true,
                    fillColor: theme.colorScheme.surface,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('Sabit gidere bağlama'),
                    ),
                    ...activeExpenses.map((expense) {
                      return DropdownMenuItem<String>(
                        value: expense.id,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              expense.description,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (expense.category != null)
                              Text(
                                expense.category!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                ),
                              ),
                          ],
                        ),
                      );
                    }),
                  ],
                  onChanged: _isUploading
                      ? null
                      : (value) {
                          setState(() {
                            _selectedFixedExpenseId = value;
                            
                            // Sabit gider seçildiyse, bilgilerini otomatik doldur
                            if (value != null) {
                              final selectedExpense = activeExpenses.firstWhere(
                                (e) => e.id == value,
                                orElse: () => activeExpenses.first,
                              );
                              
                              // Miktarı Türkçe formatta doldur
                              final amountText = selectedExpense.amount.toStringAsFixed(2)
                                  .replaceAll('.', ',')
                                  .replaceAllMapped(
                                    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
                                    (match) => '${match.group(1)}.',
                                  );
                              _amountController.text = amountText;
                              
                              // Açıklama alanını doldur (eğer boşsa)
                              if (_descriptionController.text.trim().isEmpty) {
                                _descriptionController.text = selectedExpense.description;
                              }
                              
                              // Notlar alanını doldur (eğer boşsa ve sabit giderde not varsa)
                              if (_notesController.text.trim().isEmpty && 
                                  selectedExpense.notes != null && 
                                  selectedExpense.notes!.isNotEmpty) {
                                _notesController.text = selectedExpense.notes!;
                              }
                            } else {
                              // Sabit gider seçimi kaldırıldıysa, alanları temizleme (kullanıcı manuel doldurmuş olabilir)
                            }
                          });
                        },
                );
              },
            ),
            const SizedBox(height: 16),
            // Açıklama (Opsiyonel)
            TextFormField(
              controller: _notesController,
              decoration: InputDecoration(
                labelText: 'Açıklama (opsiyonel)',
                hintText: 'Ek bilgi veya notlar',
                prefixIcon: Icon(
                  Icons.note_outlined,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: theme.colorScheme.outline.withValues(alpha: 0.2),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: theme.colorScheme.outline.withValues(alpha: 0.2),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: theme.colorScheme.primary,
                    width: 2,
                  ),
                ),
                filled: true,
                fillColor: theme.colorScheme.surface,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
              ),
              maxLines: 3,
              enabled: !_isUploading,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
            // Dosya Seç butonu
            OutlinedButton.icon(
              onPressed: _isUploading ? null : _pickFile,
              icon: const Icon(Icons.attach_file, size: 20),
              label: const Text(
                'Dosya Seç',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                side: BorderSide(
                  color: theme.colorScheme.primary.withValues(alpha: 0.5),
                  width: 1.5,
                ),
              ),
            ),
            // Seçilen dosya adı ve önizleme
            if (_selectedFileName != null)
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                builder: (context, value, child) {
                  return Opacity(
                    opacity: value,
                    child: Transform.scale(
                      scale: 0.95 + (value * 0.05),
                      child: child,
                    ),
                  );
                },
                child: Container(
                  margin: EdgeInsets.only(top: spacing / 2),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: theme.colorScheme.outline.withValues(alpha: 0.1),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          // Dosya önizleme
                          if (_getFileType(_selectedFileName) == 'image' &&
                              (kIsWeb ? _selectedFileBytes != null : _selectedFile != null))
                            Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: theme.colorScheme.primary.withValues(alpha: 0.2),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: kIsWeb
                                    ? Image.memory(
                                        _selectedFileBytes!,
                                        width: 70,
                                        height: 70,
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stackTrace) {
                                          return Container(
                                            width: 70,
                                            height: 70,
                                            decoration: BoxDecoration(
                                              color: theme.colorScheme.surface,
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: Icon(
                                              Icons.image_outlined,
                                              color: theme.colorScheme.onSurface
                                                  .withValues(alpha: 0.5),
                                            ),
                                          );
                                        },
                                      )
                                    : Image.file(
                                        _selectedFile!,
                                        width: 70,
                                        height: 70,
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stackTrace) {
                                          return Container(
                                            width: 70,
                                            height: 70,
                                            decoration: BoxDecoration(
                                              color: theme.colorScheme.surface,
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: Icon(
                                              Icons.image_outlined,
                                              color: theme.colorScheme.onSurface
                                                  .withValues(alpha: 0.5),
                                            ),
                                          );
                                        },
                                      ),
                              ),
                            )
                          else
                            Container(
                              width: 70,
                              height: 70,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: theme.colorScheme.primary.withValues(alpha: 0.2),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Icon(
                                Icons.picture_as_pdf,
                                color: theme.colorScheme.primary,
                                size: 36,
                              ),
                            ),
                          const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    _getFileType(_selectedFileName) == 'pdf'
                                        ? Icons.picture_as_pdf
                                        : Icons.image,
                                    color: theme.colorScheme.onPrimaryContainer,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      _selectedFileName!,
                                      style: TextStyle(
                                        color: theme.colorScheme
                                            .onPrimaryContainer,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Builder(
                                builder: (context) {
                                  final fileSize = kIsWeb
                                      ? (_selectedFileBytes?.length ?? 0)
                                      : (_selectedFile?.lengthSync() ?? 0);
                                  if (fileSize > 0) {
                                    final sizeInMB = fileSize / (1024 * 1024);
                                    return Text(
                                      sizeInMB < 1
                                          ? '${(fileSize / 1024).toStringAsFixed(1)} KB'
                                          : '${sizeInMB.toStringAsFixed(2)} MB',
                                      style: TextStyle(
                                        color: theme.colorScheme
                                            .onPrimaryContainer
                                            .withValues(alpha: 0.7),
                                        fontSize: 12,
                                      ),
                                    );
                                  }
                                  return const SizedBox.shrink();
                                },
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: _isUploading
                              ? null
                              : () {
                                  setState(() {
                                    _selectedFile = null;
                                    _selectedFileBytes = null;
                                    _selectedFileName = null;
                                  });
                                },
                          color: theme.colorScheme.onPrimaryContainer,
                          tooltip: 'Dosyayı kaldır',
                        ),
                      ],
                    ),
                  ],
                ),
                ),
              ),
            SizedBox(height: spacing * 1.5),
            // Kaydet butonu
            PrimaryButton(
              text: 'Kaydet',
              onPressed: _saveEntry,
              isLoading: _isUploading,
            ),
          ],
        ),
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

