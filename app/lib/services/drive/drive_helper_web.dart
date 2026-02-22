
import 'dart:typed_data';
import 'package:cross_file/cross_file.dart';
import '../../utils/app_logger.dart';

/// Web implementation for saving file (in-memory XFile)
Future<XFile?> saveFileToTemp(Uint8List bytes, String fileName) async {
  try {
    AppLogger.debug('Dosya oluşturuldu (Web): $fileName');
    return XFile.fromData(bytes, name: fileName);
  } catch (e) {
    AppLogger.error('Dosya kaydetme hatası (Web)', e);
    return null;
  }
}
