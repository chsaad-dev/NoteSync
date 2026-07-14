import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

class CloudinaryService {
  final String _workerUrl;
  final String _cloudName;

  CloudinaryService(this._workerUrl, this._cloudName);

  String? _extractPublicId(String url) {
    try {
      final uploadIndex = url.indexOf('/upload/');
      if (uploadIndex == -1) return null;

      final afterUpload = url.substring(uploadIndex + 8);
      
      String pathWithoutVersion = afterUpload;
      final firstSlash = afterUpload.indexOf('/');
      if (firstSlash != -1) {
        final versionSegment = afterUpload.substring(0, firstSlash);
        if (versionSegment.startsWith('v')) {
          pathWithoutVersion = afterUpload.substring(firstSlash + 1);
        }
      }

      final dotIndex = pathWithoutVersion.lastIndexOf('.');
      if (dotIndex != -1) {
        pathWithoutVersion = pathWithoutVersion.substring(0, dotIndex);
      }

      return pathWithoutVersion;
    } catch (_) {
      return null;
    }
  }

  Future<String> uploadMedia(String filePath, String idToken) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('File does not exist at $filePath');
    }

    final signResponse = await http.post(
      Uri.parse('$_workerUrl/sign-upload'),
      headers: {
        'Authorization': 'Bearer $idToken',
        'Content-Type': 'application/json',
      },
    );

    if (signResponse.statusCode != 200) {
      throw Exception('Failed to obtain signature: ${signResponse.body}');
    }

    final signData = json.decode(signResponse.body) as Map<String, dynamic>;
    final signature = signData['signature'] as String;
    final timestamp = signData['timestamp'].toString();
    final apiKey = signData['apiKey'] as String?;
    final cloudName = signData['cloudName'] as String?;
    final folder = signData['folder'] as String;

    if (apiKey == null || apiKey.isEmpty || cloudName == null || cloudName.isEmpty) {
      throw Exception(
        'Cloudinary credentials are not configured on the Cloudflare Worker. '
        'Please run: \n'
        '  wrangler secret put CLOUDINARY_API_KEY\n'
        '  wrangler secret put CLOUDINARY_CLOUD_NAME\n'
        'on your backend as described in the README.',
      );
    }

    final ext = p.extension(filePath).toLowerCase();
    String resourceType = 'image';
    if (ext == '.mp4' || ext == '.mov' || ext == '.avi' || ext == '.mkv') {
      resourceType = 'video';
    }

    final uploadUri = Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/$resourceType/upload');
    final request = http.MultipartRequest('POST', uploadUri);
    
    request.fields['api_key'] = apiKey;
    request.fields['timestamp'] = timestamp;
    request.fields['signature'] = signature;
    request.fields['folder'] = folder;
    
    request.files.add(await http.MultipartFile.fromPath('file', filePath));

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 200) {
      throw Exception('Cloudinary upload failed: ${response.body}');
    }

    final responseData = json.decode(response.body) as Map<String, dynamic>;
    return responseData['secure_url'] as String;
  }

  Future<void> deleteMedia(String mediaUrl, String idToken) async {
    final publicId = _extractPublicId(mediaUrl);
    if (publicId == null) {
      throw Exception('Invalid Cloudinary URL structure');
    }

    final deleteResponse = await http.post(
      Uri.parse('$_workerUrl/delete-media'),
      headers: {
        'Authorization': 'Bearer $idToken',
        'Content-Type': 'application/json',
      },
      body: json.encode({
        'public_id': publicId,
      }),
    );

    if (deleteResponse.statusCode != 200) {
      throw Exception('Failed to delete media asset: ${deleteResponse.body}');
    }
  }
}
