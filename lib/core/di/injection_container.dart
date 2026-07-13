import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/local/models/isar_note_model.dart';
import '../../data/local/note_local_data_source.dart';
import '../../data/remote/cloudinary_service.dart';
import '../../data/remote/note_remote_data_source.dart';
import '../../data/repository/note_repository_impl.dart';
import '../../data/sync/sync_engine.dart';
import '../../domain/repository/note_repository.dart';
import '../../domain/usecases/create_note.dart';
import '../../domain/usecases/delete_account.dart';
import '../../domain/usecases/delete_note.dart';
import '../../domain/usecases/sync_notes.dart';
import '../../domain/usecases/upload_media.dart';
import '../../domain/usecases/watch_notes.dart';
import '../../domain/usecases/update_note.dart';
import '../security/encryption_service.dart';

final sl = GetIt.instance;

Future<void> init({
  required String workerUrl,
  required String cloudinaryCloudName,
  Isar? testingIsar,
}) async {
  // External
  if (!sl.isRegistered<FlutterSecureStorage>()) {
    sl.registerLazySingleton<FlutterSecureStorage>(() => const FlutterSecureStorage());
  }
  if (!sl.isRegistered<firebase_auth.FirebaseAuth>()) {
    sl.registerLazySingleton<firebase_auth.FirebaseAuth>(() => firebase_auth.FirebaseAuth.instance);
  }
  if (!sl.isRegistered<FirebaseFirestore>()) {
    sl.registerLazySingleton<FirebaseFirestore>(() => FirebaseFirestore.instance);
  }
  if (!sl.isRegistered<Connectivity>()) {
    sl.registerLazySingleton<Connectivity>(() => Connectivity());
  }

  // Isar local DB Initialization
  Isar isar;
  if (testingIsar != null) {
    isar = testingIsar;
  } else {
    final dir = await getApplicationDocumentsDirectory();
    isar = await Isar.open(
      [IsarNoteModelSchema],
      directory: dir.path,
    );
  }
  if (!sl.isRegistered<Isar>()) {
    sl.registerSingleton<Isar>(isar);
  }

  // Security
  if (!sl.isRegistered<EncryptionService>()) {
    sl.registerLazySingleton<EncryptionService>(() => EncryptionService(sl()));
  }

  // Data Sources
  if (!sl.isRegistered<NoteLocalDataSource>()) {
    sl.registerLazySingleton<NoteLocalDataSource>(() => NoteLocalDataSource(sl()));
  }
  if (!sl.isRegistered<NoteRemoteDataSource>()) {
    sl.registerLazySingleton<NoteRemoteDataSource>(
      () => NoteRemoteDataSource(sl(), workerUrl),
    );
  }
  if (!sl.isRegistered<CloudinaryService>()) {
    sl.registerLazySingleton<CloudinaryService>(
      () => CloudinaryService(workerUrl, cloudinaryCloudName),
    );
  }

  // Sync Engine
  if (!sl.isRegistered<SyncEngine>()) {
    sl.registerLazySingleton<SyncEngine>(
      () => SyncEngine(
        localDataSource: sl(),
        remoteDataSource: sl(),
        cloudinaryService: sl(),
        encryptionService: sl(),
        firebaseAuth: sl(),
        secureStorage: sl(),
      ),
    );
  }

  // Repository
  if (!sl.isRegistered<NoteRepository>()) {
    final repoImpl = NoteRepositoryImpl(
      localDataSource: sl(),
      remoteDataSource: sl(),
      cloudinaryService: sl(),
      encryptionService: sl(),
      firebaseAuth: sl(),
      connectivity: sl(),
    );
    
    // Wire Repository to SyncEngine to resolve circular dependencies
    repoImpl.syncEngineTrigger = () => sl<SyncEngine>().sync();
    
    sl.registerLazySingleton<NoteRepository>(() => repoImpl);
  }

  // Use Cases
  if (!sl.isRegistered<WatchNotes>()) {
    sl.registerLazySingleton<WatchNotes>(() => WatchNotes(sl()));
  }
  if (!sl.isRegistered<CreateNote>()) {
    sl.registerLazySingleton<CreateNote>(() => CreateNote(sl()));
  }
  if (!sl.isRegistered<UpdateNote>()) {
    sl.registerLazySingleton<UpdateNote>(() => UpdateNote(sl()));
  }
  if (!sl.isRegistered<DeleteNote>()) {
    sl.registerLazySingleton<DeleteNote>(() => DeleteNote(sl()));
  }
  if (!sl.isRegistered<SyncNotes>()) {
    sl.registerLazySingleton<SyncNotes>(() => SyncNotes(sl()));
  }
  if (!sl.isRegistered<UploadMedia>()) {
    sl.registerLazySingleton<UploadMedia>(() => UploadMedia(sl()));
  }
  if (!sl.isRegistered<DeleteAccount>()) {
    sl.registerLazySingleton<DeleteAccount>(() => DeleteAccount(sl()));
  }
}
