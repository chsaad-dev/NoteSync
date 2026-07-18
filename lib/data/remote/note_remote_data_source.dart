import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import '../models/firestore_note_model.dart';

class NoteRemoteDataSource {
  final FirebaseFirestore _firestore;
  final String _workerUrl;

  String get _normalizedWorkerUrl => _workerUrl.endsWith('/') 
      ? _workerUrl.substring(0, _workerUrl.length - 1) 
      : _workerUrl;

  NoteRemoteDataSource(this._firestore, this._workerUrl);

  CollectionReference<Map<String, dynamic>> _notesRef(String uid) {
    return _firestore.collection('users').doc(uid).collection('notes');
  }

  Future<List<FirestoreNoteModel>> getNotesModifiedSince(
    String uid,
    DateTime lastSync,
  ) async {
    final snapshot = await _notesRef(uid)
        .where('updatedAt', isGreaterThan: Timestamp.fromDate(lastSync))
        .get();

    return snapshot.docs
        .map((doc) => FirestoreNoteModel.fromJson(doc.data(), doc.id))
        .toList();
  }

  Future<void> saveNote(String uid, FirestoreNoteModel note) async {
    await _notesRef(uid).doc(note.noteId).set(note.toJson());
  }

  Future<void> deleteNote(String uid, String noteId) async {
    await _notesRef(uid).doc(noteId).delete();
  }

  Future<void> deleteAccountOnWorker(String idToken) async {
    final response = await http.post(
      Uri.parse('$_normalizedWorkerUrl/delete-account'),
      headers: {
        'Authorization': 'Bearer $idToken',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to purge account data: ${response.body}');
    }
  }
}
