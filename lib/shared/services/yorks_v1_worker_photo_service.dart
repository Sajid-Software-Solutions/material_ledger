import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:image/image.dart' as img;

/// Side length of a stored worker photo, in pixels.
const yorksV1WorkerPhotoSize = 512;

/// Turns any picked image into the stored form: upright, centre-cropped to a
/// square, [yorksV1WorkerPhotoSize] pixels, JPEG. Returns null when the bytes
/// are not a readable image. Re-encoding also drops embedded metadata such as
/// the GPS position a phone camera writes.
Uint8List? yorksV1PrepareWorkerPhoto(Uint8List bytes) {
  // Choose the decoder from the file signature. Only the three accepted
  // formats are linked into the app, which keeps the web download small.
  bool startsWith(List<int> signature, [int offset = 0]) {
    if (bytes.length < offset + signature.length) return false;
    for (var index = 0; index < signature.length; index++) {
      if (bytes[offset + index] != signature[index]) return false;
    }
    return true;
  }

  final img.Image? decoded;
  try {
    if (startsWith(const [0xFF, 0xD8])) {
      decoded = img.decodeJpg(bytes);
    } else if (startsWith(const [0x89, 0x50, 0x4E, 0x47])) {
      decoded = img.decodePng(bytes);
    } else if (startsWith(const [0x52, 0x49, 0x46, 0x46]) &&
        startsWith(const [0x57, 0x45, 0x42, 0x50], 8)) {
      decoded = img.decodeWebP(bytes);
    } else {
      return null;
    }
  } catch (_) {
    return null;
  }
  if (decoded == null) return null;
  final upright = img.bakeOrientation(decoded);
  final square = img.copyResizeCropSquare(
    upright,
    size: yorksV1WorkerPhotoSize,
  );
  return Uint8List.fromList(img.encodeJpg(square, quality: 85));
}

/// Lets the user choose a photo and returns it prepared for upload.
/// `picked == false` means the user cancelled; `bytes == null` with
/// `picked == true` means the file could not be read as an image.
typedef YorksV1PickedWorkerPhoto = ({bool picked, Uint8List? bytes});

typedef YorksV1WorkerPhotoPicker = Future<YorksV1PickedWorkerPhoto> Function();

Future<YorksV1PickedWorkerPhoto> yorksV1PickWorkerPhoto() async {
  final file = await openFile(
    acceptedTypeGroups: const [
      XTypeGroup(
        label: 'Images',
        extensions: ['jpg', 'jpeg', 'png', 'webp'],
        mimeTypes: ['image/jpeg', 'image/png', 'image/webp'],
        uniformTypeIdentifiers: ['public.image'],
      ),
    ],
  );
  if (file == null) return (picked: false, bytes: null);
  return (
    picked: true,
    bytes: yorksV1PrepareWorkerPhoto(await file.readAsBytes()),
  );
}
