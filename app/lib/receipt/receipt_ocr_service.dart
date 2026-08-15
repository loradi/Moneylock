import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

class ReceiptOcrService {
  final ImagePicker _picker;
  ReceiptOcrService({ImagePicker? picker})
      : _picker = picker ?? ImagePicker();

  Future<String?> scanReceipt() async {
    final image = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 95,
    );
    if (image == null) return null;
    final text = await const MethodChannel('moneylock/vision_ocr')
        .invokeMethod<String>('recognizeText', {'path': image.path});
    final normalized = text?.trim() ?? '';
    return normalized.isEmpty ? null : normalized;
  }
}
