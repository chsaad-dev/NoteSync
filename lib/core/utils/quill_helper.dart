import 'dart:convert';

class QuillHelper {
  static String toPlainText(String quillJson) {
    if (quillJson.isEmpty) return '';
    final trimmed = quillJson.trim();
    if (!trimmed.startsWith('[')) {
      return quillJson;
    }

    try {
      final List<dynamic> delta = json.decode(trimmed);
      final StringBuffer buffer = StringBuffer();
      for (final op in delta) {
        if (op is Map<String, dynamic> && op.containsKey('insert')) {
          final insert = op['insert'];
          if (insert is String) {
            buffer.write(insert);
          }
        }
      }
      return buffer.toString().trim();
    } catch (_) {
      return quillJson;
    }
  }
}
