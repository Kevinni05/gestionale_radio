import 'api_http_client.dart';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class OperatorAuthService {
  OperatorAuthService({required this.baseUrl});

  final String baseUrl;

  final FirebaseAuth _auth = FirebaseAuth.instance;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );

    final user = credential.user;

    if (user == null) {
      throw Exception('Login Firebase fallito.');
    }

    final idToken = await user.getIdToken();

    if (idToken == null || idToken.isEmpty) {
      throw Exception('Impossibile ottenere il Firebase ID Token.');
    }

    final response = await ApiHttpClient.instance.post(
      Uri.parse('$baseUrl/api/v1/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'idToken': idToken}),
    );

    final decoded = jsonDecode(response.body);

    if (decoded is! Map<String, dynamic>) {
      throw Exception('Risposta backend non valida.');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(decoded['error'] ?? 'Autenticazione backend fallita.');
    }

    if (decoded['operatorFound'] != true) {
      throw Exception(
        decoded['message'] ??
            'Account Firebase non associato ad alcun operatore.',
      );
    }

    return decoded;
  }

  Future<Map<String, dynamic>?> getCurrentOperatorFromFirestore() async {
    final user = _auth.currentUser;

    if (user == null) {
      return null;
    }

    final claims = await user.getIdTokenResult();
    final tenantId = claims.claims?['tenantId']?.toString();
    if (tenantId == null || tenantId.isEmpty) {
      return null;
    }

    final snapshot = await _firestore
        .collection('operators')
        .where('tenantId', isEqualTo: tenantId)
        .where('firebaseUid', isEqualTo: user.uid)
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) {
      return null;
    }

    final data = snapshot.docs.first.data();

    return {...data, 'id': snapshot.docs.first.id};
  }

  Future<void> logout() async {
    await _auth.signOut();
  }
}
