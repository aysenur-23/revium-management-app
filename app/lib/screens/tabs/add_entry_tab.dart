/// Ekleme sekmesi
/// Yeni harcama kaydı eklemek için form
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cross_file/cross_file.dart';
import '../home_screen.dart';
import '../../services/upload_service.dart';
import '../../services/firestore_service.dart';

import '../../widgets/primary_button.dart';
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
  
  XFile? _selectedFile; 
  Uint8List? _selectedFileBytes; // Web için önizleme ve upload
  String? _selectedFileName;
  
  bool _isUploading = false;
  bool _isPickingFile = false; // Aynı anda tek dosya seçici (already_active hatasını önler)
  String _entryMode = 'expense'; // 'expense', 'income', veya 'tax_deductible'
  String? _selectedPartnerName; // Ortak ödemesi için seçili kişi
  List<String> _ownerNames = []; // Kişi listesi
  bool _isLoadingOwnerNames = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadOwnerNames();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _notesController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _loadOwnerNames() async {
    setState(() {
      _isLoadingOwnerNames = true;
    });
    
    try {
      final names = await FirestoreService.getAllOwnerNames();
      // Ödemeyi yapan ortak olarak kendisini de seçebilsin
      if (widget.currentUser.fullName.isNotEmpty && !names.contains(widget.currentUser.fullName)) {
        names.add(widget.currentUser.fullName);
        names.sort();
      }
      if (mounted) {
        setState(() {
          _ownerNames = names;
          _isLoadingOwnerNames = false;
        });
      }
    } catch (e) {
      AppLogger.error('Kişi listesi yüklenirken hata', e);
      if (mounted) {
        setState(() {
          _isLoadingOwnerNames = false;
        });
      }
    }
  }

  /// Gelir veya Vergiden Düşülecek seçildiğinde onay dialog'u göster
  Future<bool> _confirmEntryModeChange(String targetMode) async {
    final theme = Theme.of(context);
    final title = targetMode == 'income' ? 'Ortak Ödemesi' : 'Vergiden Düşülecek';
    final description = targetMode == 'income' 
        ? 'Bu kaydı ortak ödemesi olarak işaretlemek istediğinize emin misiniz?'
        : 'Bu kaydı vergiden düşülecek olarak işaretlemek istediğinize emin misiniz?\n\nBu seçenek, vergi beyannamesnde gider olarak gösterilecek faturalar içindir.';
    final iconData = targetMode == 'income' ? Icons.group : Icons.assignment_turned_in;
    final color = targetMode == 'income' ? Colors.green : Colors.orange;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(iconData, color: color, size: 24),
            ),
            const SizedBox(width: 12),
            Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
        content: Text(
          description,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: color),
            child: const Text('Evet, Onayla'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _pickFile() async {
    if (_isPickingFile) return;
    _isPickingFile = true;
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
        withData: true, // Web + Android: bytes ile path/URI sorunlarını önler
      );

      if (result != null && result.files.isNotEmpty && mounted) {
        final platformFile = result.files.first;
        final name = platformFile.name;
        if (name.isEmpty) return;

        Uint8List? bytes = platformFile.bytes;
        if (bytes == null && platformFile.path != null) {
          // Mobil: path varsa hemen oku (content URI veya geçici path sonradan okunamayabilir)
          try {
            bytes = await XFile(platformFile.path!).readAsBytes();
          } catch (e) {
            AppLogger.error('Dosya okuma hatası (path)', e);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Dosya okunamadı. Lütfen daha küçük bir dosya veya farklı konum deneyin: $e'),
                  backgroundColor: Colors.red,
                ),
              );
            }
            return;
          }
        }

        if (bytes == null || bytes.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Dosya içeriği alınamadı.')),
            );
          }
          return;
        }

        if (!mounted) return;
        final bytesList = bytes;
        setState(() {
          _selectedFileName = name;
          _selectedFileBytes = bytesList;
          _selectedFile = XFile.fromData(bytesList, name: name, length: bytesList.length);
        });
      }
    } catch (e) {
      AppLogger.error('Dosya seçme hatası', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Dosya seçilirken hata: ${e.toString().replaceAll(RegExp(r'^Exception:?\s*'), '')}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isPickingFile = false);
    }
  }

  Future<void> _saveEntry() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedFile == null && _entryMode == 'expense') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lütfen bir belge (fiş/fatura) ekleyin'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_entryMode == 'income' && _selectedPartnerName == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lütfen ödeme yapan kişiyi seçin'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isUploading = true;
    });

    // Loading dialog göster
    bool dialogShown = true;
    BuildContext? dialogContext;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        dialogContext = ctx;
        return const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Kayıt ekleniyor...'),
                ],
              ),
            ),
          ),
        );
      },
    );

    try {
      // Miktarı parse et (1.234,56 -> 1234.56)
      String amountText = _amountController.text.replaceAll('.', '').replaceAll(',', '.');
      double amount = double.parse(amountText);

      // Upload işlemi
      UploadResult uploadResult;
      
      if (_selectedFile != null) {
        // Dosya varsa yükle
        // UploadService.uploadFile artık XFile veya platforma uygun parametre beklemeli
        // Eğer UploadService File bekliyorsa onu da güncellememiz gerekebilir.
        // Ancak UploadService'in web uyumlu olduğunu önceki adımlarda gördük.
        // XFile -> File dönüşümü web'de çalışmaz. 
        // readAsBytes kullanarak UploadService'e bytes göndermek en garanticisi.
        
        Uint8List? fileBytes = _selectedFileBytes;
        if (fileBytes == null && _selectedFile != null) {
           fileBytes = await _selectedFile!.readAsBytes();
        }

        if (fileBytes == null) throw Exception("Dosya okunamadı");

        uploadResult = await UploadService.uploadFile(
          fileBytes: fileBytes,
          fileName: _selectedFileName!,
          ownerId: widget.currentUser.userId,
          ownerName: widget.currentUser.fullName,
          amount: amount,
          description: _descriptionController.text.trim(),
          notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
          entryType: _entryMode,
        );
      } else {
        // Dosya yoksa (sadece gelir kaydı olabilir veya dosyasız gider)
        // Şu anki mantıkta gider için dosya zorunlu, gelir için opsiyonel olabilir
        // Mock bir result oluşturalım veya logic'i ayıralım. 
        // Şimdilik dosya zorunlu assumption'ı ile devam (kod başında check var expenses için)
         throw Exception("Dosya gerekli"); 
      }

      // MIME type (basit kontrol)
      final extension = _selectedFileName?.toLowerCase().split('.').last ?? 'dat';
      String mimeType = 'application/octet-stream';
      String fileType = 'image';
      
      if (extension == 'pdf') {
        mimeType = 'application/pdf';
        fileType = 'pdf';
      } else if (['jpg', 'jpeg', 'png'].contains(extension)) {
         mimeType = 'image/$extension'; // basitçe
         if (extension == 'jpg') mimeType = 'image/jpeg';
      }

      // Entry oluştur
      final entry = ExpenseEntry(
        ownerId: widget.currentUser.userId,
        ownerName: _entryMode == 'income' ? _selectedPartnerName! : widget.currentUser.fullName, // Gelir ise seçilen kişi
        description: _descriptionController.text.trim(),
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        amount: amount,
        fileUrl: uploadResult.fileUrl,
        fileType: fileType,
        driveFileId: uploadResult.fileId,
        mimeType: mimeType,
        fileName: _selectedFileName,
        entryType: _entryMode, // 'expense', 'income', 'tax_deductible'
      );

      // Firestore kaydı
      await FirestoreService.addEntry(entry);

      // Excel güncellemesi backend Service Account ile yapılır — kullanıcının Drive bağlamasına gerek yok
      // Arka planda Excel güncelleme — kısa gecikme: Firestore yeni kaydı hemen döndürmeyebilir, son eklenenin Excel'de görünmesi için
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) _updateExcelFileInBackground(context, entry);
      });

      // Temizlik
      _descriptionController.clear();
      _notesController.clear();
      _amountController.clear();
      setState(() {
        _selectedFile = null;
        _selectedFileBytes = null;
        _selectedFileName = null;
      });

      if (mounted && dialogShown && dialogContext != null) {
        Navigator.pop(dialogContext!);
        dialogShown = false;
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Kayıt başarıyla eklendi'),
            backgroundColor: Colors.green,
          ),
        );
      }

    } catch (e) {
      AppLogger.error('Kayıt ekleme hatası', e);
      if (mounted && dialogShown && dialogContext != null) {
        Navigator.pop(dialogContext!);
        dialogShown = false;
        
         ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hata: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }
  
  String _getFileType(String? fileName) {
    if (fileName == null) return 'unknown';
    final extension = fileName.split('.').last.toLowerCase();
    if (extension == 'pdf') return 'pdf';
    if (['jpg', 'jpeg', 'png'].contains(extension)) return 'image';
    return 'unknown';
  }

  /// Arka planda Excel dosyalarını günceller
  Future<void> _updateExcelFileInBackground(BuildContext context, ExpenseEntry newEntry) async {
    try {
       // Tüm verileri çek; yeni kayıt henüz listede yoksa 2 sn sonra bir kez daha dene (son eklenenin Excel'de görünmesi için)
       var allEntries = await FirestoreService.getAllEntries();
       final newId = newEntry.id;
       if (newId != null && !allEntries.any((e) => e.id == newId)) {
         await Future.delayed(const Duration(seconds: 2));
         if (!mounted) return;
         allEntries = await FirestoreService.getAllEntries();
       }
       final allEntriesMap = allEntries.map((e) => e.toMap()).toList();

       // 1. "Tum Eklenenler" güncelle
       UploadService.createAllEntriesExcel(allEntriesMap).then(
         (_) => AppLogger.info('Autosync: Tum Eklenenler güncellendi'),
         onError: (e) => AppLogger.error('Autosync: Tum Eklenenler hatası', e)
       );

       // 2. "My Entries" güncelle (eğer ekleyen kişi ise)
       if (newEntry.ownerId == widget.currentUser.userId) {
          final myEntries = allEntries.where((e) => e.ownerId == widget.currentUser.userId).toList();
          UploadService.createMyEntriesExcel(
             myEntries.map((e) => e.toMap()).toList(),
             widget.currentUser.fullName
          ).then(
             (_) => AppLogger.info('Autosync: My Entries güncellendi'),
             onError: (e) => AppLogger.error('Autosync: My Entries hatası', e)
          );
       }

       // 3. "Ortak Gelirleri" güncelle (eğer gelir ise) — sabit Excel'e yazılır
       if (newEntry.entryType == 'income') {
          final incomeEntries = allEntries.where((e) => e.entryType == 'income').toList();
          UploadService.createIncomeEntriesExcel(
             incomeEntries.map((e) => e.toMap()).toList()
          ).then(
             (result) {
               AppLogger.info('Autosync: Ortak Gelirleri güncellendi');
               if (mounted && result != null) {
                 ScaffoldMessenger.of(context).showSnackBar(
                   SnackBar(
                     content: Text('Ortak Gelirleri tablosu güncellendi (${result['rowCount'] ?? 0} kayıt)'),
                     duration: const Duration(seconds: 3),
                     backgroundColor: Colors.green,
                   ),
                 );
               }
             },
             onError: (e) {
               AppLogger.error('Autosync: Ortak Gelirleri hatası', e);
               if (mounted) {
                 ScaffoldMessenger.of(context).showSnackBar(
                   const SnackBar(
                     content: Text(
                       'Ortak Gelirleri tablosu güncellenemedi. Tabloyu Service Account e-postası ile düzenleyici olarak paylaşın.',
                     ),
                     duration: Duration(seconds: 6),
                     backgroundColor: Colors.orange,
                   ),
                 );
               }
             }
          );
       }

       // 4. "Vergiden Düşülecekler" güncelle (eğer vergiden düşülecek ise)
       if (newEntry.entryType == 'tax_deductible') {
          final taxEntries = allEntries.where((e) => e.entryType == 'tax_deductible').toList();
          UploadService.createTaxDeductibleEntriesExcel(
             taxEntries.map((e) => e.toMap()).toList()
          ).then(
             (_) => AppLogger.info('Autosync: Vergiden Düşülecekler güncellendi'),
             onError: (e) => AppLogger.error('Autosync: Vergiden Düşülecekler hatası', e)
          );
       }
    } catch (e) {
       AppLogger.error('Background Excel Sync Failed', e);
    }
  }

  // --- UI ---
  
  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final isSmallScreen = MediaQuery.of(context).size.width < 600;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Kayıt Türü Seçimi - Segmented Button (mobil/ dar ekranda taşmayı önlemek için yatay scroll)
            LayoutBuilder(
              builder: (context, constraints) {
                const minButtonWidth = 280.0;
                final useScroll = constraints.maxWidth < minButtonWidth;
                final child = ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: minButtonWidth),
                  child: SegmentedButton<String>(
                    segments: [
                      ButtonSegment<String>(
                        value: 'expense',
                        label: Text('Gider', style: TextStyle(fontSize: isSmallScreen ? 12 : 14)),
                        icon: Icon(Icons.remove_circle_outline, size: isSmallScreen ? 16 : 20),
                      ),
                      ButtonSegment<String>(
                        value: 'income',
                        label: Text('Gelir', style: TextStyle(fontSize: isSmallScreen ? 12 : 14)),
                        icon: Icon(Icons.add_circle_outline, size: isSmallScreen ? 16 : 20),
                      ),
                      ButtonSegment<String>(
                        value: 'tax_deductible',
                        label: Text('Vergi', style: TextStyle(fontSize: isSmallScreen ? 12 : 14)),
                        icon: Icon(Icons.receipt_long, size: isSmallScreen ? 16 : 20),
                      ),
                    ],
                    selected: {_entryMode},
                    onSelectionChanged: (Set<String> newSelection) async {
                      final newMode = newSelection.first;
                      if (newMode == _entryMode) return;
                      if (newMode == 'expense') {
                        setState(() {
                          _entryMode = 'expense';
                          _selectedPartnerName = null;
                        });
                        return;
                      }
                      final confirmed = await _confirmEntryModeChange(newMode);
                      if (confirmed && mounted) {
                        setState(() {
                          _entryMode = newMode;
                          if (newMode != 'income') _selectedPartnerName = null;
                        });
                      }
                    },
                    style: ButtonStyle(
                      backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
                        if (states.contains(WidgetState.selected)) {
                          if (_entryMode == 'expense') return theme.colorScheme.error.withValues(alpha: 0.15);
                          if (_entryMode == 'income') return Colors.green.withValues(alpha: 0.15);
                          if (_entryMode == 'tax_deductible') return Colors.orange.withValues(alpha: 0.15);
                        }
                        return Colors.transparent;
                      }),
                      foregroundColor: WidgetStateProperty.resolveWith<Color>((states) {
                        if (states.contains(WidgetState.selected)) {
                          if (_entryMode == 'expense') return theme.colorScheme.error;
                          if (_entryMode == 'income') return Colors.green[700]!;
                          if (_entryMode == 'tax_deductible') return Colors.orange[700]!;
                        }
                        return theme.colorScheme.onSurface.withValues(alpha: 0.6);
                      }),
                      side: WidgetStateProperty.resolveWith<BorderSide>((states) {
                        Color borderColor = theme.colorScheme.outline.withValues(alpha: 0.3);
                        if (states.contains(WidgetState.selected)) {
                          if (_entryMode == 'expense') borderColor = theme.colorScheme.error.withValues(alpha: 0.5);
                          if (_entryMode == 'income') borderColor = Colors.green.withValues(alpha: 0.5);
                          if (_entryMode == 'tax_deductible') borderColor = Colors.orange.withValues(alpha: 0.5);
                        }
                        return BorderSide(color: borderColor);
                      }),
                    ),
                  ),
                );
                if (useScroll) {
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: child,
                  );
                }
                return child;
              },
            ),
            
            // Ortak seçimi (sadece income modunda göster)
            if (_entryMode == 'income') ...[
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _isLoadingOwnerNames ? null : _selectedPartnerName,
                decoration: InputDecoration(
                  labelText: _isLoadingOwnerNames ? 'Ödemeyi yapan ortak (yükleniyor...)' : 'Ödemeyi yapan ortak',
                  prefixIcon: const Icon(Icons.person_outline),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                ),
                items: _isLoadingOwnerNames
                    ? [const DropdownMenuItem(value: null, child: Text('Yükleniyor...'))]
                    : _ownerNames.map((name) => DropdownMenuItem(value: name, child: Text(name))).toList(),
                onChanged: _isLoadingOwnerNames ? null : (val) => setState(() => _selectedPartnerName = val),
                validator: (val) => _entryMode == 'income' && val == null ? 'Kişi seçiniz' : null,
              ),
            ],
            
             const SizedBox(height: 16),
             
            // Harcama Kalemi
            TextFormField(
              controller: _descriptionController,
              decoration: InputDecoration(
                labelText: 'Harcama Kalemi',
                hintText: 'Örn: Ofis Kirası',
                prefixIcon: const Icon(Icons.description_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              validator: (val) => (val == null || val.isEmpty) ? 'Gerekli' : null,
            ),
            
            const SizedBox(height: 16),
            
            // Miktar
            TextFormField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [_TurkishNumberInputFormatter()],
              decoration: InputDecoration(
                labelText: 'Miktar (₺)',
                hintText: '0,00',
                prefixIcon: const Icon(Icons.wallet_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
               validator: (val) => (val == null || val.isEmpty) ? 'Gerekli' : null,
            ),
            
            // Açıklama (Partner ödemesinde gizle)
            if (_entryMode != 'income') ...[
              const SizedBox(height: 16),
              TextFormField(
                controller: _notesController,
                decoration: InputDecoration(
                  labelText: 'Notlar (Opsiyonel)',
                  prefixIcon: const Icon(Icons.note_alt_outlined),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
            
            const SizedBox(height: 24),
            
            // Dosya Seçimi
            InkWell(
              onTap: _isPickingFile ? null : _pickFile,
              borderRadius: BorderRadius.circular(12),
              child: Opacity(
                opacity: _isPickingFile ? 0.7 : 1,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.5)),
                    borderRadius: BorderRadius.circular(12),
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _isPickingFile ? Icons.hourglass_empty : Icons.cloud_upload_outlined,
                        size: 32,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isPickingFile ? 'Dosya seçiliyor...' : (_selectedFileName ?? 'Fiş/Fatura Yükle'),
                              style: theme.textTheme.bodyLarge?.copyWith(
                                fontWeight: _selectedFileName != null ? FontWeight.bold : FontWeight.normal,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (_selectedFileName == null && !_isPickingFile)
                              Text(
                                'Dokunarak seçin (Resim veya PDF)',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    if (_selectedFileName != null)
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          setState(() {
                            _selectedFileName = null;
                            _selectedFile = null;
                            _selectedFileBytes = null;
                          });
                        },
                        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                        padding: EdgeInsets.zero,
                      ),
                  ],
                ),
              ),
            ),
            ),
            
            // Önizleme (Web'de çalışacak şekilde)
             if (_selectedFileName != null && _getFileType(_selectedFileName) == 'image') ...[
               const SizedBox(height: 16),
               Center(
                 child: Container(
                   height: 200,
                   decoration: BoxDecoration(
                     borderRadius: BorderRadius.circular(12),
                     border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.2)),
                   ),
                   child: ClipRRect(
                     borderRadius: BorderRadius.circular(12),
                     child: _selectedFileBytes != null 
                        ? Image.memory(_selectedFileBytes!, fit: BoxFit.contain)
                        : _selectedFile != null 
                           ? FutureBuilder<Uint8List>(
                               future: _selectedFile!.readAsBytes(),
                               builder: (context, snapshot) {
                                 if (snapshot.hasData) {
                                   return Image.memory(snapshot.data!, fit: BoxFit.contain);
                                 }
                                 return const Center(child: CircularProgressIndicator());
                               },
                             )
                           : const Icon(Icons.image_not_supported),
                   ),
                 ),
               ),
             ],

             const SizedBox(height: 24),
             
             PrimaryButton(
               text: 'Kaydet',
               onPressed: _isUploading ? null : _saveEntry,
               isLoading: _isUploading,
             ),
             
             const SizedBox(height: 40), // Bottom padding
          ],
        ),
      ),
    );
  }
}

class _TurkishNumberInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue;
    }

    String text = newValue.text.replaceAll(RegExp(r'[^\d.,]'), '');
    final commaCount = text.split(',').length - 1;
    if (commaCount > 1) {
      return oldValue;
    }
    
    if (text.contains(',')) {
      final parts = text.split(',');
      if (parts.length == 2 && parts[1].length > 2) {
        return oldValue;
      }
    }
    
    String formatted = text;
    if (text.contains(',')) {
      final parts = text.split(',');
      final integerPart = parts[0].replaceAll('.', '');
      final decimalPart = parts[1];
      
      String formattedInteger = '';
      for (int i = integerPart.length - 1; i >= 0; i--) {
        formattedInteger = integerPart[i] + formattedInteger;
        if ((integerPart.length - i) % 3 == 0 && i > 0) {
          formattedInteger = '.$formattedInteger';
        }
      }
      formatted = '$formattedInteger,$decimalPart';
    } else {
      final integerPart = text.replaceAll('.', '');
      String formattedInteger = '';
      for (int i = integerPart.length - 1; i >= 0; i--) {
        formattedInteger = integerPart[i] + formattedInteger;
        if ((integerPart.length - i) % 3 == 0 && i > 0) {
          formattedInteger = '.$formattedInteger';
        }
      }
      formatted = formattedInteger;
    }
    
    int cursorPosition = formatted.length;
    if (newValue.selection.baseOffset <= oldValue.text.length) {
      final oldText = oldValue.text;
      final newText = formatted;
      final offset = newValue.selection.baseOffset;
      
      if (offset <= oldText.length) {
        final charsBeforeCursor = oldText.substring(0, offset).replaceAll(RegExp(r'[^\d]'), '').length;
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
