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

  static String toHtml(String quillJson) {
    if (quillJson.isEmpty) return '';
    final trimmed = quillJson.trim();
    if (!trimmed.startsWith('[')) {
      return '<p>${trimmed.replaceAll('\n', '<br/>')}</p>';
    }

    try {
      final List<dynamic> delta = json.decode(trimmed);
      final StringBuffer buffer = StringBuffer();
      
      for (final op in delta) {
        if (op is Map<String, dynamic> && op.containsKey('insert')) {
          final insert = op['insert'];
          if (insert is String) {
            String text = insert
                .replaceAll('&', '&amp;')
                .replaceAll('<', '&lt;')
                .replaceAll('>', '&gt;')
                .replaceAll('\n', '<br/>');
                                
            final attributes = op['attributes'] as Map<String, dynamic>?;
            if (attributes != null) {
              if (attributes['bold'] == true) {
                text = '<strong>$text</strong>';
              }
              if (attributes['italic'] == true) {
                text = '<em>$text</em>';
              }
              if (attributes['underline'] == true) {
                text = '<u>$text</u>';
              }
              if (attributes['strike'] == true) {
                text = '<del>$text</del>';
              }
            }
            buffer.write(text);
          }
        }
      }
      
      final lines = buffer.toString().split('<br/>');
      final wrapped = lines.map((line) => line.trim().isEmpty ? '<br/>' : '<p>$line</p>').join('');
      return wrapped;
    } catch (_) {
      return '<p>${quillJson.replaceAll('\n', '<br/>')}</p>';
    }
  }
}
