import 'services/italian_labels.dart';
import 'services/auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'backend_settings_screen.dart';
import 'widgets/personal_badge.dart';

import 'home_screen.dart';
import 'services/api_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  static const routeName = '/profile';

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _birthDateController = TextEditingController();
  final TextEditingController _shiftController = TextEditingController();

  bool _isEditing = false;
  bool _isLoading = false;
  bool _loadingProfile = true;
  bool _initialized = false;

  String _operatorId = '';
  String _role = 'Operatore';
  String _phone = '';
  String _company = '';
  String _specialization = '';

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _birthDateController.dispose();
    _shiftController.dispose();
    super.dispose();
  }

  // ============================================================
  // CARICAMENTO PROFILO
  // ============================================================

  Future<void> _loadProfile() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      if (mounted) {
        setState(() => _loadingProfile = false);
      }
      return;
    }

    _operatorId = user.uid;

    try {
      final data = await ApiService.instance.getMyOperatorProfile();
      _initializeFromFirestore(data);

      // Email Firebase come fallback, senza obbligare il campo.
      if (_emailController.text.trim().isEmpty &&
          user.email != null &&
          user.email!.isNotEmpty) {
        _emailController.text = user.email!;
      }

      if (_nameController.text.trim().isEmpty &&
          user.displayName != null &&
          user.displayName!.isNotEmpty) {
        _nameController.text = user.displayName!;
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Impossibile caricare il profilo.', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _loadingProfile = false);
      }
    }
  }

  void _initializeFromFirestore(Map<String, dynamic> data) {
    if (_initialized) return;

    _nameController.text = data['fullName']?.toString() ?? '';
    _emailController.text = data['email']?.toString() ?? '';
    _birthDateController.text = data['birthDate']?.toString() ?? '';
    _shiftController.text = data['shift']?.toString() ?? '';

    _operatorId = data['id']?.toString() ?? _operatorId;
    _role = italianLabel(data['role'] ?? 'OPERATOR');
    _phone = data['phone']?.toString() ?? '';
    _company = data['company']?.toString() ?? '';
    _specialization = data['specialization']?.toString() ?? '';

    _initialized = true;
  }

  // ============================================================
  // SALVATAGGIO
  // ============================================================

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      _showSnackBar('Utente non autenticato.', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      await ApiService.instance.updateMyOperatorProfile({
        'fullName': _nameController.text.trim(),
        'phone': _phone,
        'birthDate': _birthDateController.text.trim(),
        'company': _company,
        'specialization': _specialization,
        'shift': _shiftController.text.trim(),
      });

      if (!mounted) return;

      setState(() {
        _isEditing = false;
      });

      _showSnackBar('Profilo aggiornato correttamente.');
    } catch (e) {
      if (!mounted) return;

      _showSnackBar('Errore durante il salvataggio.', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ============================================================
  // DATA
  // ============================================================

  Future<void> _selectBirthDate() async {
    DateTime initialDate = DateTime.now();

    final current = _birthDateController.text.trim();

    if (current.isNotEmpty) {
      final parts = current.split('/');

      if (parts.length == 3) {
        final day = int.tryParse(parts[0]);
        final month = int.tryParse(parts[1]);
        final year = int.tryParse(parts[2]);

        if (day != null && month != null && year != null) {
          final parsed = DateTime.tryParse(
            '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}',
          );

          if (parsed != null) {
            initialDate = parsed;
          }
        }
      }
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(1940),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.cyan,
              surface: AppColors.surface,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked == null || !mounted) return;

    setState(() {
      _birthDateController.text =
          '${picked.day.toString().padLeft(2, '0')}/'
          '${picked.month.toString().padLeft(2, '0')}/'
          '${picked.year}';
    });
  }

  // ============================================================
  // UI
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: const CustomBackButton(),
        title: const Text(
          'Profilo',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        actions: [
          if (!kReleaseMode)
            IconButton(
              tooltip: 'Connessione al server',
              icon: const Icon(Icons.dns_outlined),
              onPressed: () => Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => const BackendSettingsScreen(),
                ),
              ),
            ),
          if (!_loadingProfile)
            IconButton(
              tooltip: _isEditing ? 'Annulla' : 'Modifica profilo',
              onPressed: () {
                setState(() {
                  _isEditing = !_isEditing;
                });
              },
              icon: Icon(
                _isEditing ? Icons.close_rounded : Icons.edit_rounded,
                color: AppColors.cyan,
              ),
            ),
        ],
      ),
      body: _loadingProfile
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.cyan),
            )
          : RefreshIndicator(
              color: AppColors.cyan,
              backgroundColor: AppColors.surface,
              onRefresh: _loadProfile,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 35),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      _buildProfileHero(),

                      const SizedBox(height: 18),

                      _buildStatusCard(),

                      const SizedBox(height: 18),

                      _isEditing
                          ? _buildEditSection()
                          : _buildReadOnlySection(),

                      const SizedBox(height: 18),

                      _buildOperatorQr(),

                      const SizedBox(height: 18),

                      _buildAccountSection(),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  // ============================================================
  // HERO
  // ============================================================

  Widget _buildProfileHero() {
    final name = _nameController.text.trim().isEmpty
        ? 'Operatore'
        : _nameController.text.trim();

    final firstLetter = name.isNotEmpty
        ? name.substring(0, 1).toUpperCase()
        : 'O';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF232332), Color(0xFF181922), Color(0xFF12131D)],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.cyan.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: AppColors.cyan.withValues(alpha: 0.06),
            blurRadius: 30,
            spreadRadius: -8,
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.cyan, AppColors.blue],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.cyan.withValues(alpha: 0.22),
                      blurRadius: 22,
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    firstLetter,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 29,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 16),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'PROFILO OPERATORE',
                      style: TextStyle(
                        color: AppColors.cyan,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _role,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          Row(
            children: [
              Expanded(
                child: _buildMiniStat(
                  Icons.badge_outlined,
                  'ID OPERATORE',
                  _shortId(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMiniStat(
                  Icons.work_outline_rounded,
                  'RUOLO',
                  _role,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStat(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.cyan, size: 17),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 7,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.7,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _shortId() {
    if (_operatorId.isEmpty) return 'N/D';

    return _operatorId.substring(
      0,
      _operatorId.length > 8 ? 8 : _operatorId.length,
    );
  }

  // ============================================================
  // STATUS
  // ============================================================

  Widget _buildStatusCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      decoration: BoxDecoration(
        color: AppColors.green.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: AppColors.green.withValues(alpha: 0.14)),
      ),
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.green,
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Account operativo',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            _isEditing ? 'MODIFICA' : 'ONLINE',
            style: TextStyle(
              color: _isEditing ? AppColors.orange : AppColors.green,
              fontSize: 8,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // READ ONLY
  // ============================================================

  Widget _buildReadOnlySection() {
    return _buildSectionCard(
      title: 'Informazioni personali',
      subtitle: 'Dati associati al tuo profilo operativo.',
      icon: Icons.person_outline_rounded,
      child: Column(
        children: [
          _buildInfoRow(
            'Nome e cognome',
            _nameController.text,
            Icons.person_outline_rounded,
          ),
          _buildInfoRow('Email', _emailController.text, Icons.email_outlined),
          _buildInfoRow(
            'Data di nascita',
            _birthDateController.text,
            Icons.calendar_today_outlined,
          ),
          _buildInfoRow('Turno', _shiftController.text, Icons.schedule_rounded),
          _buildInfoRow('Telefono', _phone, Icons.phone_outlined),
          _buildInfoRow('Azienda', _company, Icons.business_outlined),
          _buildInfoRow(
            'Specializzazione',
            _specialization,
            Icons.settings_input_antenna_rounded,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon) {
    final hasValue = value.trim().isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.025),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.cyan, size: 18),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 9,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  hasValue ? value : 'Non impostato',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: hasValue ? Colors.white : AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // EDIT
  // ============================================================

  Widget _buildEditSection() {
    return _buildSectionCard(
      title: 'Modifica profilo',
      subtitle: 'Aggiorna le informazioni dell’operatore.',
      icon: Icons.edit_note_rounded,
      child: Column(
        children: [
          _buildInput(
            controller: _nameController,
            label: 'Nome e cognome',
            hint: 'Inserisci nome e cognome',
            icon: Icons.person_outline_rounded,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Inserisci il nome';
              }

              return null;
            },
          ),

          const SizedBox(height: 11),

          _buildInput(
            controller: _emailController,
            label: 'Email',
            hint: 'Inserisci email',
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
          ),

          const SizedBox(height: 11),

          GestureDetector(
            onTap: _selectBirthDate,
            child: AbsorbPointer(
              child: _buildInput(
                controller: _birthDateController,
                label: 'Data di nascita',
                hint: 'Seleziona data',
                icon: Icons.calendar_today_outlined,
              ),
            ),
          ),

          const SizedBox(height: 11),

          _buildInput(
            controller: _shiftController,
            label: 'Turno',
            hint: 'Es. mattina, pomeriggio, notte',
            icon: Icons.schedule_rounded,
          ),

          const SizedBox(height: 18),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _saveProfile,
              icon: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF151518),
                      ),
                    )
                  : const Icon(Icons.save_rounded),
              label: Text(_isLoading ? 'SALVATAGGIO...' : 'SALVA MODIFICHE'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.cyan,
                foregroundColor: const Color(0xFF151518),
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(17),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInput({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        hintStyle: TextStyle(
          color: AppColors.textSecondary.withValues(alpha: 0.65),
          fontSize: 12,
        ),
        prefixIcon: Icon(icon, color: AppColors.cyan, size: 19),
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 15,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.cyan, width: 1),
        ),
      ),
    );
  }

  // ============================================================
  // QR OPERATORE
  // ============================================================

  Widget _buildOperatorQr() => _buildSectionCard(
    title: 'Badge personale',
    subtitle: 'Lo stesso badge di accesso della web app.',
    icon: Icons.qr_code_2_rounded,
    child: PersonalBadge(operatorId: _operatorId.isEmpty ? null : _operatorId),
  );

  // ============================================================
  // ACCOUNT
  // ============================================================

  Widget _buildAccountSection() {
    final user = FirebaseAuth.instance.currentUser;

    return _buildSectionCard(
      title: 'Accesso personale',
      subtitle: 'Informazioni e gestione dell’accesso.',
      icon: Icons.security_rounded,
      child: Column(
        children: [
          _buildInfoRow(
            'UID Firebase',
            user?.uid ?? '',
            Icons.fingerprint_rounded,
          ),

          const SizedBox(height: 8),

          _buildAccountAction(
            icon: Icons.logout_rounded,
            title: 'Disconnetti',
            subtitle: 'Esci dall’account operativo',
            color: AppColors.red,
            onTap: _confirmLogout,
          ),
        ],
      ),
    );
  }

  Widget _buildAccountAction({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.12)),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: color.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // SECTION CARD
  // ============================================================

  Widget _buildSectionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.065)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.cyan.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: AppColors.cyan, size: 19),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 15),

          child,
        ],
      ),
    );
  }

  // ============================================================
  // LOGOUT
  // ============================================================

  Future<void> _confirmLogout() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: const Text(
            'Disconnettere l’account?',
            style: TextStyle(color: Colors.white),
          ),
          content: const Text(
            'Dovrai effettuare nuovamente l’accesso per utilizzare l’app.',
            style: TextStyle(color: AppColors.textSecondary, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text(
                'ANNULLA',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text(
                'DISCONNETTI',
                style: TextStyle(color: AppColors.red),
              ),
            ),
          ],
        );
      },
    );

    if (result != true) return;

    await AuthService.instance.signOut();

    if (!mounted) return;

    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  // ============================================================
  // SNACKBAR
  // ============================================================

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: isError ? AppColors.red : AppColors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        content: Text(
          message,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
