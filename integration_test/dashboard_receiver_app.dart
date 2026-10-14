import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:gestionale_radio/firebase_options.dart';
import 'package:gestionale_radio/main.dart' as application;
import 'package:gestionale_radio/services/app_navigation.dart';
import 'package:gestionale_radio/services/api_service.dart';
import 'package:gestionale_radio/services/local_operational_store.dart';
import 'package:gestionale_radio/services/notification_service.dart';
import 'package:gestionale_radio/services/session_service.dart';
import 'package:gestionale_radio/services/report_draft_store.dart';
import 'package:gestionale_radio/services/local_report_attachment_store.dart';
import 'package:gestionale_radio/services/maintenance_report_pdf.dart';

/// The normal application, with a synthetic receiver and metadata-only QA probe.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('radiotech/updates');
  final identity = await channel.invokeMapMethod<String, dynamic>(
    'installedApp',
  );
  if (kReleaseMode ||
      identity?['applicationId'] != 'com.example.gestionale_radio.qa') {
    throw StateError('An isolated debug QA installation is required.');
  }
  const email = String.fromEnvironment('QA_EMAIL');
  const password = String.fromEnvironment('QA_PASSWORD');
  const uid = String.fromEnvironment('QA_UID');
  const tenant = String.fromEnvironment('QA_TENANT_ID');
  if (!uid.startsWith('qa-dashboard-') ||
      email != '$uid@example.test' ||
      tenant.isEmpty) {
    throw StateError('An owned synthetic receiver is required.');
  }
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // The app also has direct Firestore readers. Isolate these together with
  // the API; retain real Auth/FCM and the separate encrypted draft archive.
  final firestore = FirebaseFirestore.instance;
  firestore.settings = const Settings(persistenceEnabled: false);
  firestore.useFirestoreEmulator(
    '127.0.0.1',
    18882,
    automaticHostMapping: false,
  );
  // Configure before the first native call: FlutterFire caches its settings
  // when creating the Pigeon app, including for clearPersistence().
  await firestore.clearPersistence();
  await ApiService.initializeEndpoint();
  final directory = await getApplicationDocumentsDirectory();
  final evidence = File('${directory.path}/qa-dashboard.json');
  final phase = await channel.invokeMethod<String>('qaRecoveryPhase');
  if (phase == 'cleanup') {
    if (FirebaseAuth.instance.currentUser?.uid == uid) {
      await NotificationService.instance.clearDeviceToken();
      await FirebaseAuth.instance.signOut();
    }
    await evidence.writeAsString(jsonEncode({'phase': 'cleaned'}), flush: true);
    runApp(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: Text('QA terminata')),
      ),
    );
    return;
  }
  try {
    if (phase == 'fresh-login' &&
        FirebaseAuth.instance.currentUser?.uid == uid) {
      await FirebaseAuth.instance.signOut();
    }
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    }
  } on FirebaseAuthException catch (error) {
    await evidence.writeAsString(
      jsonEncode({'phase': 'login_failed', 'code': error.code}),
      flush: true,
    );
    rethrow;
  }
  final openedNotices = <String>[], openedTasks = <String>[];
  if (phase == 'field-gps') {
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 30),
      ),
    );
    // Explicit QA phase only. Private coordinates calibrate the synthetic
    // emulator antenna for the physical geofence test; never publish them.
    await File('${directory.path}/qa-field-position.json').writeAsString(
      jsonEncode({
        'uid': uid,
        'tenantId': tenant,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
        'observedAt': position.timestamp.toUtc().toIso8601String(),
      }),
      flush: true,
    );
  }
  AppNavigation.requestedNotification.addListener(() {
    final id = AppNavigation.requestedNotification.value;
    if (id != null && !openedNotices.contains(id)) openedNotices.add(id);
  });
  AppNavigation.requestedTask.addListener(() {
    final id = AppNavigation.requestedTask.value;
    if (id != null && !openedTasks.contains(id)) openedTasks.add(id);
  });
  await application.main();
  var sampling = false;
  var photoChecked = false;
  Timer.periodic(const Duration(seconds: 2), (_) async {
    if (sampling) return;
    sampling = true;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user?.uid != uid) {
        await evidence.writeAsString(
          jsonEncode({'phase': 'different_account'}),
          flush: true,
        );
        return;
      }
      final claims = (await user!.getIdTokenResult()).claims ?? {};
      final token = await user.getIdToken();
      final validation = await http
          .get(
            Uri.parse(ApiService.apiV1Url('/auth/me')),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 15));
      final owner = await LocalOperationalStore.instance.read(
        'notification_device_owner',
      );
      final registered = owner == jsonEncode([uid, tenant]);
      final scoped =
          SessionService.instance.tenantId == tenant &&
          SessionService.instance.role == 'OPERATOR';
      String sdkAccess;
      int? sdkAntennaCount;
      try {
        final antennas = await firestore
            .collection('antennas')
            .where('tenantId', isEqualTo: tenant)
            .get()
            .timeout(const Duration(seconds: 10));
        sdkAccess = 'allowed';
        sdkAntennaCount = antennas.size;
      } on FirebaseException catch (error) {
        sdkAccess = error.code == 'permission-denied'
            ? 'denied'
            : 'unavailable';
      } catch (_) {
        sdkAccess = 'unavailable';
      }
      if (scoped && !photoChecked) {
        final draft = await ReportDraftStore().load(
          ReportDraftStore.storageKey(
            tenantId: tenant,
            operatorUid: uid,
            taskScope: 'qa-antenna-${uid.substring('qa-dashboard-'.length)}',
          ),
        );
        final attachments = draft?['attachments'];
        if (attachments is List && attachments.isNotEmpty) {
          photoChecked = true;
          final proof = File('${directory.path}/qa-photo-proof.json');
          final store = LocalReportAttachmentStore();
          List<Map<String, String>> staged = [];
          try {
            final source = Map<String, dynamic>.from(attachments.first as Map);
            final file = await store.resolve(source);
            final ciphertext = await file.readAsBytes();
            final bytes = await store.readBytes(source);
            final pdf = await MaintenanceReportPdf.build(
              antennaId: 'QA',
              antennaName: 'QA antenna sintetica',
              operatorName: 'QA Samsung',
              submittedAt: DateTime.now(),
              notes: 'Verifica locale della foto cifrata.',
              photos: [ReportPhoto('QA foto', bytes)],
            );
            await File(
              '${directory.path}/qa-photo-report.pdf',
            ).writeAsBytes(pdf, flush: true);
            staged = await store.stage(
              requestKey:
                  'qa-photo-verification-${DateTime.now().microsecondsSinceEpoch}',
              files: [file],
            );
            final restored = await store.readBytes(staged.single);
            final copy = await File(staged.single['path']!).readAsBytes();
            await proof.writeAsString(
              jsonEncode({
                'phase': 'passed',
                'photoCount': attachments.length,
                'sourceEncryptedAtRest':
                    ascii.decode(ciphertext.take(8).toList()) == 'RTENC001',
                'pdfGenerated': ascii.decode(pdf.take(4).toList()) == '%PDF',
                'restagedEncrypted':
                    ascii.decode(copy.take(8).toList()) == 'RTENC001',
                'sourceUnchanged': listEquals(
                  ciphertext,
                  await file.readAsBytes(),
                ),
                'restagedReadable': listEquals(bytes, restored),
              }),
              flush: true,
            );
          } catch (error) {
            await proof.writeAsString(
              jsonEncode({
                'phase': 'failed',
                'type': error.runtimeType.toString(),
              }),
              flush: true,
            );
          } finally {
            await store.remove(staged);
          }
        }
      }
      Future<List<dynamic>> receipts(String kind) async {
        final key =
            'notification_receipts_${base64Url.encode(utf8.encode('$tenant:$uid:$kind'))}';
        final raw = await LocalOperationalStore.instance.read(key);
        return raw == null ? [] : jsonDecode(raw) as List<dynamic>;
      }

      await evidence.writeAsString(
        jsonEncode({
          'phase':
              registered &&
                  scoped &&
                  validation.statusCode == 200 &&
                  sdkAccess == 'allowed' &&
                  claims['radioDeviceId'] is String
              ? 'ready'
              : 'starting',
          'apiRegistrationVerified': registered,
          'approvedScope': scoped,
          'sdkFirestoreAccess': sdkAccess,
          'sdkAntennaCount': sdkAntennaCount,
          'deviceId': claims['radioDeviceId'],
          'role': claims['role'],
          'provider': (claims['firebase'] as Map?)?['sign_in_provider'],
          'validationStatus': validation.statusCode,
          'validationMessage': validation.statusCode == 200
              ? null
              : (jsonDecode(validation.body) as Map)['message'],
          'showReceipts': await receipts('show'),
          'openReceipts': await receipts('open'),
          'requestedNotifications': openedNotices,
          'requestedTasks': openedTasks,
          'observedAt': DateTime.now().toUtc().toIso8601String(),
        }),
        flush: true,
      );
    } catch (error) {
      await evidence.writeAsString(
        jsonEncode({
          'phase': 'probe_error',
          'type': error.runtimeType.toString(),
        }),
        flush: true,
      );
    } finally {
      sampling = false;
    }
  });
}
