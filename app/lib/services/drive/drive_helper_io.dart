
import 'dart:io';
import 'dart:typed_data';
import 'package:cross_file/cross_file.dart';
import 'package:path_provider/path_provider.dart';
import '../../utils/app_logger.dart';

/// IO implementation for saving file to temp
Future<XFile?> saveFileToTemp(Uint8List bytes, String fileName) async {
  try {
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/$fileName');
    await file.writeAsBytes(bytes);
    AppLogger.debug('Dosya kaydedildi (IO): ${file.path}');
    return XFile(file.path);
  } catch (e) {
    AppLogger.error('Dosya kaydetme hatası (IO)', e);
    return null;
  }
}
