/**
 * Ekleme sekmesi
 * Yeni harcama kaydı eklemek için form
 */

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';
import '../home_screen.dart';
import '../../services/upload_service.dart';
import '../../services/firestore_service.dart';
import '../../services/connectivity_service.dart';
import '../../models/expense_entry.dart';
import '../../widgets/primary_button.dart';
import '../../utils/app_logger.dart';
import '../../config/app_config.dart';

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

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _descriptionController.dispose();
    _notesController.dispose();
    _amountController.dispose();
    super.dispose();
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
        final fileSize = platformFile.size ?? 0;
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
      // Miktarı parse et (dosya isimlendirme için)
      final amountText = _amountController.text.trim().replaceAll(',', '.');
      final amount = double.tryParse(amountText);
      if (amount == null || amount <= 0) {
        throw Exception('Geçersiz miktar. Lütfen geçerli bir sayı girin.');
      }

      // Backend'e dosya yükle
      UploadResult? uploadResult;
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

      if (uploadResult == null) {
        throw Exception('Dosya yükleme başarısız oldu.');
      }

      // ExpenseEntry oluştur

      final entry = ExpenseEntry(
        ownerId: widget.currentUser.userId,
        ownerName: widget.currentUser.fullName,
        description: _descriptionController.text.trim(),
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        amount: amount,
        fileUrl: uploadResult.fileUrl,
        fileType: _getFileType(_selectedFileName),
        driveFileId: uploadResult.fileId,
      );

      // Firestore'a kaydet
      await FirestoreService.addEntry(entry);

      // Formu temizle
      _descriptionController.clear();
      _notesController.clear();
      _amountController.clear();
      setState(() {
        _selectedFile = null;
        _selectedFileBytes = null;
        _selectedFileName = null;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Kayıt başarıyla eklendi'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Kayıt ekleme hatası: $e');
      
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
            debugPrint('✅ Dialog dialogContext ile kapatıldı');
            return;
          }
        } catch (e) {
          debugPrint('⚠️ Dialog kapatma hatası (dialogContext): $e');
        }
      }
      
      // Ana context ile kapat
      if (mounted) {
        try {
          final navigator = Navigator.of(context, rootNavigator: true);
          if (navigator.canPop()) {
            navigator.pop();
            debugPrint('✅ Dialog ana context ile kapatıldı');
          } else {
            debugPrint('⚠️ Dialog zaten kapatılmış (canPop false)');
          }
        } catch (e) {
          debugPrint('⚠️ Dialog kapatma hatası (ana context): $e');
        }
      }
    } catch (e) {
      debugPrint('❌ Dialog kapatma genel hatası: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
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
            // Başlık kartı
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: theme.colorScheme.outline.withValues(alpha: 0.1),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      Icons.add_circle_outline,
                      color: theme.colorScheme.primary,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Yeni Harcama Ekle',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.primary,
                            fontSize: 20,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Harcama bilgilerinizi girin',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: spacing),
            // Harcama Kalemi
            TextFormField(
              controller: _descriptionController,
              decoration: InputDecoration(
                labelText: 'Harcama Kalemi',
                hintText: 'Örn: Üretim Maliyeti',
                prefixIcon: Icon(
                  Icons.description_outlined,
                  color: theme.colorScheme.primary,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: theme.colorScheme.outline.withValues(alpha: 0.3),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: theme.colorScheme.outline.withValues(alpha: 0.3),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: theme.colorScheme.primary,
                    width: 2,
                  ),
                ),
                filled: true,
                fillColor: theme.colorScheme.surface,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 20,
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
            SizedBox(height: spacing),
            // Miktar
            TextFormField(
              controller: _amountController,
              decoration: InputDecoration(
                labelText: 'Miktar (₺)',
                hintText: 'Örn: 125.50',
                prefixIcon: Icon(
                  Icons.account_balance_wallet_outlined,
                  color: theme.colorScheme.primary,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: theme.colorScheme.outline.withValues(alpha: 0.3),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: theme.colorScheme.outline.withValues(alpha: 0.3),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: theme.colorScheme.primary,
                    width: 2,
                  ),
                ),
                filled: true,
                fillColor: theme.colorScheme.surface,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 20,
                ),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Lütfen miktar giriniz';
                }
                final cleanedValue = value.trim().replaceAll(',', '.');
                final amount = double.tryParse(cleanedValue);
                if (amount == null) {
                  return 'Geçerli bir sayı giriniz (örn: 125.50)';
                }
                if (amount <= 0) {
                  return 'Miktar 0\'dan büyük olmalıdır';
                }
                if (amount > 999999999) {
                  return 'Miktar çok büyük (maksimum: 999,999,999)';
                }
                return null;
              },
              enabled: !_isUploading,
              textInputAction: TextInputAction.next,
            ),
            SizedBox(height: spacing),
            // Açıklama (Opsiyonel)
            TextFormField(
              controller: _notesController,
              decoration: InputDecoration(
                labelText: 'Açıklama (opsiyonel)',
                hintText: 'Ek bilgi veya notlar',
                prefixIcon: Icon(
                  Icons.note_outlined,
                  color: theme.colorScheme.primary,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: theme.colorScheme.outline.withValues(alpha: 0.3),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: theme.colorScheme.outline.withValues(alpha: 0.3),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: theme.colorScheme.primary,
                    width: 2,
                  ),
                ),
                filled: true,
                fillColor: theme.colorScheme.surface,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 20,
                ),
              ),
              maxLines: 3,
              enabled: !_isUploading,
              textInputAction: TextInputAction.next,
            ),
            SizedBox(height: spacing),
            // Dosya Seç butonu
            OutlinedButton.icon(
              onPressed: _isUploading ? null : _pickFile,
              icon: const Icon(Icons.attach_file),
              label: const Text(
                'Dosya Seç',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 20),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
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

