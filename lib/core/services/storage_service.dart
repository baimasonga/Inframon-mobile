import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path/path.dart' as p;

class StorageService {
  static final SupabaseClient _client = Supabase.instance.client;

  static Future<String?> uploadMedia(File file, String projectId) async {
    try {
      final fileName = p.basename(file.path);
      final filePath = '$projectId/${DateTime.now().millisecondsSinceEpoch}_$fileName';
      
      // Upload to Supabase 'inspections_media' bucket
      await _client.storage.from('inspections_media').upload(filePath, file);
      
      // Return public URL
      return _client.storage.from('inspections_media').getPublicUrl(filePath);
    } catch (e) {
      // In offline-first apps, we'd queue this failure for sync later using the db_helper queue.
      debugPrint('Media upload failed: $e');
      return null;
    }
  }
}
