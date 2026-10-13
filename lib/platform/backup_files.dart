import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Backup export/import: the system Save and Open windows, so the user picks
/// where the backup file goes (Downloads, Google Drive, iCloud Drive, a USB
/// stick...). Swappable so widget tests don't open real dialogs.
abstract interface class BackupFiles {
  /// Backup export: asks where to save [bytes] as [fileName]. False if the
  /// user cancelled.
  Future<bool> save(String fileName, List<int> bytes);

  /// Backup import: asks for a file and returns its text, or null if the
  /// user cancelled. Throws [FormatException] for a file that is too large
  /// or not text.
  Future<String?> pickText();
}

/// Backup export/import: real Save / Open windows from `file_picker`.
class SystemBackupFiles implements BackupFiles {
  const SystemBackupFiles();

  /// Backup import: anything bigger can't be a backup (thousands of
  /// entries are well under 1 MB).
  static const int maxBytes = 10 * 1024 * 1024;

  @override
  Future<bool> save(String fileName, List<int> bytes) async {
    // The plugin writes the bytes itself on every platform.
    final uri = await FilePicker.saveFile(
      dialogTitle: 'Save Vaultify backup',
      fileName: fileName,
      bytes: Uint8List.fromList(bytes),
    );
    return uri != null;
  }

  @override
  Future<String?> pickText() async {
    // Any file type: phones don't know the .vaultify extension, so a filter
    // would hide the backup.
    final file = await FilePicker.pickFile(dialogTitle: 'Open Vaultify backup');
    if (file == null) return null;
    final size = await file.length();
    if (size != null && size > maxBytes) {
      throw const FormatException('file too large');
    }
    final bytes = await file.readAsBytes();
    if (bytes.length > maxBytes) throw const FormatException('file too large');
    return utf8.decode(bytes);
  }
}
