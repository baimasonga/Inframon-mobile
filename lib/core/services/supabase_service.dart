import 'package:supabase_flutter/supabase_flutter.dart';

  class SupabaseService {
    SupabaseService._privateConstructor();
    static final SupabaseService instance = SupabaseService._privateConstructor();

    final SupabaseClient client = Supabase.instance.client;

    Future<void> signIn(String email, String password) async {
      await client.auth.signInWithPassword(email: email, password: password);
    }

    Future<void> signOut() async {
      await client.auth.signOut();
    }

    /// Sends a password-reset email. On success, the user receives a link
    /// they can open in any browser to set a new password.
    Future<void> resetPasswordForEmail(String email) async {
      await client.auth.resetPasswordForEmail(email);
    }

    User? get currentUser => client.auth.currentUser;

    // Additional CRUD operations for Phase 1
    Future<List<Map<String, dynamic>>> getProjects() async {
      return await client.from('projects').select();
    }
  }
  