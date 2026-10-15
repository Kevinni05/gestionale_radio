import '../../antenna_dossier_screen.dart';
import '../../attendance_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'home_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../calculator_screen.dart';
import '../../widgets/radiotech_action_tile.dart';
import '../../models/task_summary.dart';
import '../../add_antenna_screen.dart';
import '../../antenna_dashboard.dart';
import '../../incidents_screen.dart';
import '../../report_closure_screen.dart';
import '../../telco_tools_screen.dart';
import '../../profile_screen.dart';
import '../../services/api_service.dart';
import '../../services/offline_sync_service.dart';
import '../../services/session_service.dart';
import '../../widgets/offline_sync_status_panel.dart';
import '../../widgets/api_connection_badge.dart';
import '../../widgets/android_update_button.dart';
import '../../tasks_screen.dart';
import '../../services/app_navigation.dart';
import '../../ai_hub_screen.dart';
import '../../workforce_screen.dart';
import '../../pro_suite_screen.dart';
import '../../agenda_screen.dart';
import '../../notifications_screen.dart';
import '../../calendar_screen.dart';
import '../../new_report_screen.dart';
import '../../report_history_screen.dart';
import '../../widgets/radiotech_clock.dart';

String _operatorNameFromAuth() {
  final user = FirebaseAuth.instance.currentUser;

  if (user == null) return 'Operatore';

  if (user.displayName != null && user.displayName!.isNotEmpty) {
    return user.displayName!;
  }

  if (user.email != null && user.email!.isNotEmpty) {
    return user.email!.split('@').first;
  }

  return user.uid.substring(0, 6).toUpperCase();
}

// ============================================================
// DESIGN SYSTEM
// ============================================================

class AppColors {
  static const background = Color(0xFF08090D);
  static const surface = Color(0xFF191A24);
  static const surfaceLight = Color(0xFF20212B);

  static const cyan = Color(0xFFE6E6E6);
  static const blue = Color(0xFF63A1FF);
  static const green = Color(0xFF35E59A);
  static const orange = Color(0xFFFFB547);
  static const red = Color(0xFFFF5570);

  static const textPrimary = Color(0xFFF5F5F7);
  static const textSecondary = Color(0xFFAAAAB4);
  static const border = Color(0x1AFFFFFF);
}

class CustomBackButton extends StatelessWidget {
  const CustomBackButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: IconButton(
        icon: const Icon(
          Icons.arrow_back_rounded,
          color: Colors.white,
          size: 20,
        ),
        onPressed: () => Navigator.of(context).pop(),
        tooltip: 'Indietro',
      ),
    );
  }
}

// ============================================================
// HOME
// ============================================================

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  static const routeName = '/home';
  @override
  Widget build(BuildContext context) =>
      const ProviderScope(child: _HomeFeature());
}

class _HomeFeature extends ConsumerStatefulWidget {
  const _HomeFeature();

  @override
  ConsumerState<_HomeFeature> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<_HomeFeature>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _pulseController;
  late final Animation<double> _pulse;
  int _syncRefreshToken = 0;
  late Future<List<Map<String, dynamic>>> _tasks;
  late Future<int> _reports;

  void _refreshTasks() {
    if (mounted) {
      setState(() {
        _tasks = ref.refresh(homeTasksProvider.future);
        _reports = ref.refresh(homeReportsProvider.future);
      });
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tasks = ref.refresh(homeTasksProvider.future);
    _reports = ref.refresh(homeReportsProvider.future);
    AppNavigation.requestedTask.addListener(_openRequestedTask);
    AppNavigation.tasksRevision.addListener(_refreshTasks);
    WidgetsBinding.instance.addPostFrameCallback((_) => _openRequestedTask());

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    _pulse = Tween<double>(begin: 0.94, end: 1.06).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _pulseController.stop();
    } else if (!_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshTasks();
      if (!MediaQuery.disableAnimationsOf(context)) {
        _pulseController.repeat(reverse: true);
      }
    } else {
      _pulseController.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AppNavigation.requestedTask.removeListener(_openRequestedTask);
    AppNavigation.tasksRevision.removeListener(_refreshTasks);
    _pulseController.dispose();
    super.dispose();
  }

  void _openRequestedTask() async {
    final id = AppNavigation.requestedTask.value;
    if (id == null || !mounted) return;
    AppNavigation.requestedTask.value = null;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => TasksScreen(highlightTaskId: id)),
    );
    _refreshTasks();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          _buildBackground(),

          SafeArea(
            child: RefreshIndicator(
              color: AppColors.green,
              backgroundColor: AppColors.surface,
              onRefresh: () async {
                await Future.delayed(const Duration(milliseconds: 500));
                await OfflineSyncService.instance.retryPending();
                if (mounted) {
                  setState(() => _syncRefreshToken++);
                  _refreshTasks();
                }
              },
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHeader(context),
                        const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: RadioTechClock(),
                        ),

                        OfflineSyncStatusPanel(refreshToken: _syncRefreshToken),
                        const AndroidUpdateButton(),

                        const SizedBox(height: 24),

                        _buildHero(context),

                        const SizedBox(height: 24),

                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            key: const ValueKey('open-calendar'),
                            icon: const Icon(Icons.calendar_month_outlined),
                            label: const Text('Calendario'),
                            onPressed: () async {
                              await Navigator.of(context).push<void>(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      CalendarScreen(initialTasks: _tasks),
                                ),
                              );
                              if (mounted) _refreshTasks();
                            },
                          ),
                        ),
                        const SizedBox(height: 24),

                        _buildSectionHeader(
                          context,
                          title: 'Azioni operative',
                          subtitle: 'Le funzioni che usi più spesso',
                        ),

                        const SizedBox(height: 14),

                        _buildActionGrid(context),

                        const SizedBox(height: 28),

                        _buildSectionHeader(
                          context,
                          title: 'Interventi da gestire',
                          subtitle: 'Attività assegnate alla tua operatività',
                          trailing: 'IN TEMPO REALE',
                        ),

                        const SizedBox(height: 14),

                        _buildRealFollowUps(context),

                        const SizedBox(height: 28),

                        const SizedBox(height: 24),
                        const Text(
                          '© 2026 Kevin Cagnazzo e Anthony Piccinonno. Tutti i diritti riservati.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // BACKGROUND
  // ==========================================================

  Widget _buildBackground() => const SizedBox.expand();

  // ==========================================================
  // HEADER
  // ==========================================================

  Widget _buildHeader(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    final tenantId = SessionService.instance.tenantId;

    return StreamBuilder<QuerySnapshot>(
      stream: userId == null || tenantId == null
          ? null
          : FirebaseFirestore.instance
                .collection('operators')
                .where('tenantId', isEqualTo: tenantId)
                .where('firebaseUid', isEqualTo: userId)
                .snapshots(),
      builder: (context, snapshot) {
        String operatorName = _operatorNameFromAuth();

        if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
          final raw = snapshot.data!.docs.first.data();

          if (raw is Map<String, dynamic>) {
            final fullName = raw['fullName'] ?? raw['full_name'];

            if (fullName != null && fullName.toString().trim().isNotEmpty) {
              operatorName = fullName.toString().trim();
            }
          }
        }

        final firstName = operatorName.split(' ').first;

        return Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Image.asset(
                'assets/brand/radiotech-symbol-v1.png',
                width: 38,
                height: 38,
                semanticLabel: 'Logo RadioTech',
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CENTRO OPERATIVO',
                    style: const TextStyle(
                      color: AppColors.cyan,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.8,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    'Bentornato, $firstName',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 25,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 3),
                  const Text(
                    'Pronto per il prossimo intervento?',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 12),

            _buildNotificationButton(context),

            const SizedBox(width: 8),

            _buildHeaderButton(
              context,
              icon: Icons.person_outline_rounded,
              accent: AppColors.cyan,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ProfileScreen()),
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildNotificationButton(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _loadUnreadAlertCount(),
      builder: (context, snapshot) {
        final count = snapshot.data is Map && snapshot.data!['count'] != null
            ? int.tryParse(snapshot.data!['count'].toString()) ?? 0
            : 0;

        final badge = count > 0
            ? Positioned(
                top: 4,
                right: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 17,
                    minHeight: 17,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.red,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppColors.background, width: 2),
                  ),
                  child: Text(
                    count > 9 ? '9+' : count.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : const SizedBox.shrink();

        return Stack(
          clipBehavior: Clip.none,
          children: [
            _buildHeaderButton(
              context,
              icon: Icons.notifications_none_rounded,
              accent: AppColors.cyan,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const NotificationsScreen(),
                  ),
                );
              },
            ),
            badge,
          ],
        );
      },
    );
  }

  Future<Map<String, dynamic>> _loadUnreadAlertCount() async {
    try {
      return await ApiService.instance.getUnreadAlertCount();
    } catch (_) {
      return {'count': 0};
    }
  }

  Widget _buildHeaderButton(
    BuildContext context, {
    required IconData icon,
    required Color accent,
    required VoidCallback onTap,
  }) {
    return ScaleTransition(
      scale: icon == Icons.notifications_none_rounded
          ? _pulse
          : const AlwaysStoppedAnimation(1),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(15),
          child: Container(
            width: 45,
            height: 45,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.055),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
            ),
            child: Icon(icon, color: accent, size: 21),
          ),
        ),
      ),
    );
  }

  // ==========================================================
  // HERO
  // ==========================================================

  Widget _buildHero(BuildContext context) {
    return FutureBuilder<int>(
      future: _reports,
      builder: (context, reportSnapshot) {
        final completedReports = reportSnapshot.hasData
            ? reportSnapshot.data!.toString()
            : '—';

        return FutureBuilder<List<Map<String, dynamic>>>(
          future: _tasks,
          builder: (context, taskSnapshot) {
            final assignedTasks = (taskSnapshot.data ?? [])
                .map(TaskSummary.new)
                .where((t) => !t.archived && !t.awaitingReview)
                .length;

            return Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF232332),
                    Color(0xFF181922),
                    Color(0xFF12131D),
                  ],
                ),
                border: Border.all(
                  color: AppColors.cyan.withValues(alpha: 0.20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.cyan.withValues(alpha: 0.07),
                    blurRadius: 35,
                    spreadRadius: -10,
                    offset: const Offset(0, 15),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFFFF806D), Color(0xFFA079E7)],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFFFF806D,
                              ).withValues(alpha: 0.15),
                              blurRadius: 20,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.bolt_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'OPERATIVITÀ',
                              style: TextStyle(
                                color: AppColors.cyan,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.5,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Sistema operativo',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _onlineBadge(),
                    ],
                  ),

                  const SizedBox(height: 24),

                  const Text(
                    'Tutto sotto controllo.',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                    ),
                  ),

                  const SizedBox(height: 7),

                  Text(
                    'Monitora interventi, antenne e attività direttamente dal tuo centro operativo.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.58),
                      fontSize: 12,
                      height: 1.45,
                    ),
                  ),

                  const SizedBox(height: 22),

                  Row(
                    children: [
                      Expanded(
                        child: _buildKpi(
                          value: completedReports.toString(),
                          label: 'REPORT',
                          icon: Icons.assignment_turned_in_rounded,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildKpi(
                          value: assignedTasks.toString(),
                          label: 'ATTIVITÀ',
                          icon: Icons.task_alt_rounded,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: _buildAntennaKpi()),
                    ],
                  ),

                  const SizedBox(height: 18),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ScanAntennaScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.qr_code_scanner_rounded, size: 20),
                      label: const Text(
                        'SCANSIONA ANTENNA',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
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
          },
        );
      },
    );
  }

  Widget _onlineBadge() {
    return const ApiConnectionBadge();
  }

  Widget _buildKpi({
    required String value,
    required String label,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.cyan, size: 17),
          const SizedBox(height: 9),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 8,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAntennaKpi() {
    final tenantId = SessionService.instance.tenantId;
    return StreamBuilder<QuerySnapshot>(
      stream: tenantId == null
          ? null
          : FirebaseFirestore.instance
                .collection('antennas')
                .where('tenantId', isEqualTo: tenantId)
                .snapshots(),
      builder: (context, snapshot) {
        final count = snapshot.hasData ? snapshot.data!.docs.length : 0;

        return _buildKpi(
          value: count.toString(),
          label: 'ANTENNE',
          icon: Icons.cell_tower_rounded,
        );
      },
    );
  }

  // ==========================================================
  // SECTION HEADER
  // ==========================================================

  Widget _buildSectionHeader(
    BuildContext context, {
    required String title,
    required String subtitle,
    String? trailing,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.green.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'LIVE',
              style: TextStyle(
                color: AppColors.green,
                fontSize: 8,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
          ),
      ],
    );
  }

  // ==========================================================
  // ACTION GRID
  // ==========================================================

  Widget _buildActionGrid(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 850
            ? 4
            : constraints.maxWidth >= 550
            ? 3
            : MediaQuery.textScalerOf(context).scale(14) > 20 ||
                  constraints.maxWidth < 340
            ? 1
            : 2;
        final width = (constraints.maxWidth - 12 * (columns - 1)) / columns;

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: width,
              child: _buildLargeAction(
                context,
                title: 'Enterprise Pro',
                subtitle: 'Gestione e consuntivi',
                icon: Icons.business_center_outlined,
                accent: AppColors.blue,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ProSuiteScreen(),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: width,
              child: _buildLargeAction(
                context,
                title: 'Incarichi',
                subtitle: 'Priorità e scadenze',
                icon: Icons.assignment_outlined,
                accent: AppColors.cyan,
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const TasksScreen(),
                    ),
                  );
                  _refreshTasks();
                },
              ),
            ),
            SizedBox(
              width: width,
              child: _buildLargeAction(
                context,
                title: 'Pianificazione preventiva',
                subtitle: 'Scadenze e priorità operative',
                icon: Icons.auto_awesome,
                accent: AppColors.blue,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const AiHubScreen()),
                ),
              ),
            ),
            SizedBox(
              width: width,
              child: _buildLargeAction(
                context,
                title: 'Fascicoli offline',
                subtitle: 'Impianti, documenti e fotografie scaricati',
                icon: Icons.folder_open_outlined,
                accent: AppColors.blue,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const OfflineDossiersScreen(),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: width,
              child: _buildLargeAction(
                context,
                title: 'Presenze e turni',
                subtitle: 'Badge, entrata / uscita e calendario personale',
                icon: Icons.badge_outlined,
                accent: AppColors.blue,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AttendanceScreen(),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: width,
              child: _buildLargeAction(
                context,
                title: 'Squadra e sicurezza',
                subtitle: 'Turni, pause e supporto',
                icon: Icons.health_and_safety_outlined,
                accent: AppColors.green,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const WorkforceScreen(),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: width,
              child: _buildLargeAction(
                context,
                title: 'Scansiona',
                subtitle: 'QR antenna',
                icon: Icons.qr_code_scanner_rounded,
                accent: AppColors.cyan,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ScanAntennaScreen(),
                    ),
                  );
                },
              ),
            ),
            SizedBox(
              width: width,
              child: _buildLargeAction(
                context,
                title: 'Nuovo report',
                subtitle: 'Registra intervento',
                icon: Icons.note_add_rounded,
                accent: AppColors.blue,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const NewReportScreen()),
                  );
                },
              ),
            ),
            SizedBox(
              width: width,
              child: _buildLargeAction(
                context,
                title: 'Mappa antenne',
                subtitle: 'Postazioni e rete',
                icon: Icons.map_rounded,
                accent: AppColors.blue,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AntennaMapScreen()),
                ),
              ),
            ),
            if (SessionService.instance.canManage)
              SizedBox(
                width: width,
                child: _buildLargeAction(
                  context,
                  title: 'Nuova antenna',
                  subtitle: 'Registra postazione',
                  icon: Icons.add_business_rounded,
                  accent: AppColors.green,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const AddAntennaScreen(),
                      ),
                    );
                  },
                ),
              ),
            SizedBox(
              width: width,
              child: _buildLargeAction(
                context,
                title: 'Storico',
                subtitle: 'Interventi eseguiti',
                icon: Icons.history_rounded,
                accent: AppColors.orange,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const OperatorHistoryScreen(),
                    ),
                  );
                },
              ),
            ),
            SizedBox(
              width: width,
              child: _buildLargeAction(
                context,
                title: 'Incidenti',
                subtitle: 'Stato e severità',
                icon: Icons.crisis_alert_rounded,
                accent: AppColors.red,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const IncidentsScreen()),
                  );
                },
              ),
            ),
            SizedBox(
              width: width,
              child: _buildLargeAction(
                context,
                title: 'Agenda interventi',
                subtitle: 'Scadenze e pianificazione',
                icon: Icons.calendar_month_rounded,
                accent: AppColors.blue,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AgendaScreen()),
                  );
                },
              ),
            ),
            SizedBox(
              width: width,
              child: _buildLargeAction(
                context,
                title: 'Calcolatrice',
                subtitle: 'Calcoli rapidi',
                icon: Icons.calculate_rounded,
                accent: AppColors.cyan,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const CalculatorScreen()),
                  );
                },
              ),
            ),
            SizedBox(
              width: width,
              child: _buildLargeAction(
                context,
                title: 'TelcoTools',
                subtitle: 'Strumenti tecnici telecom',
                icon: Icons.settings_input_antenna_rounded,
                accent: AppColors.cyan,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const TelcoToolsScreen()),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget telcoToolsButton(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const TelcoToolsScreen()),
          );
        },
        child: Ink(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF191A24),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFFE6E6E6).withValues(alpha: 0.18),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFE6E6E6).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.settings_input_antenna_rounded,
                  color: Color(0xFFE6E6E6),
                  size: 25,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TELCO TOOLS',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Strumenti per operatori telecom',
                      style: TextStyle(color: Color(0xFFAAAAB4), fontSize: 11),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: Color(0xFFAAAAB4),
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLargeAction(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accent,
    required VoidCallback onTap,
  }) => RadioTechActionTile(
    title: title,
    subtitle: subtitle,
    icon: icon,
    onTap: onTap,
  );

  // ==========================================================
  // FOLLOW UPS
  // ==========================================================

  Widget _buildRealFollowUps(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _tasks,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Column(
            children: [
              _errorCard(
                'Impossibile caricare gli incarichi. Verifica il server e la connessione.',
              ),
              TextButton.icon(
                onPressed: _refreshTasks,
                icon: const Icon(Icons.refresh),
                label: const Text('Riprova'),
              ),
            ],
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _loadingCard();
        }
        final tasks = TaskSummary.ordered(
          (snapshot.data ?? []).map(TaskSummary.new),
          DateTime.now(),
        ).where((t) => !t.archived && !t.awaitingReview).take(5).toList();
        if (tasks.isEmpty) {
          return _emptyCard(
            icon: Icons.check_circle_outline_rounded,
            text: 'Nessun intervento assegnato al momento.',
          );
        }
        return Column(
          children: tasks
              .map(
                (task) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _buildTaskCard(
                    context,
                    title: task.title,
                    taskId: task.id,
                    antennaId: task.antennaId,
                    description: task.data['description']?.toString() ?? '',
                    priority: task.priority,
                    status: task.status,
                    dueAt: task.data['dueAt']?.toString(),
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _buildTaskCard(
    BuildContext context, {
    required String taskId,
    String? antennaId,
    required String title,
    required String description,
    required String priority,
    required String status,
    String? dueAt,
  }) {
    final priorityColor = _priorityColor(priority);
    final dueDate = dueAt == null ? null : DateTime.tryParse(dueAt);
    final isOverdue =
        dueDate != null &&
        dueDate.isBefore(DateTime.now()) &&
        status != 'COMPLETED' &&
        status != 'COMPLETATO';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: priorityColor.withValues(alpha: 0.16)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 4,
            height: 64,
            decoration: BoxDecoration(
              color: priorityColor,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: priorityColor.withValues(alpha: 0.35),
                  blurRadius: 10,
                ),
              ],
            ),
          ),

          const SizedBox(width: 13),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: priorityColor,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ),
                    _statusPill(status),
                  ],
                ),

                const SizedBox(height: 7),

                Text(
                  description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),

                const SizedBox(height: 9),

                Row(
                  children: [
                    Icon(
                      Icons.priority_high_rounded,
                      color: priorityColor,
                      size: 13,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Priorità $priority',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 10,
                      ),
                    ),
                    if (dueDate != null) ...[
                      const SizedBox(width: 12),
                      Icon(
                        Icons.schedule_rounded,
                        color: isOverdue
                            ? AppColors.red
                            : AppColors.textSecondary,
                        size: 13,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isOverdue
                            ? 'SCADUTO'
                            : 'Scade ${dueDate.day.toString().padLeft(2, '0')}/${dueDate.month.toString().padLeft(2, '0')}',
                        style: TextStyle(
                          color: isOverdue
                              ? AppColors.red
                              : AppColors.textSecondary,
                          fontSize: 10,
                          fontWeight: isOverdue
                              ? FontWeight.w800
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ],
                ),

                const SizedBox(height: 12),
                _buildTaskAction(context, taskId, antennaId, status),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskAction(
    BuildContext context,
    String taskId,
    String? antennaId,
    String status,
  ) {
    final normalized = status.toUpperCase();
    final String? nextStatus;
    final String actionLabel;
    switch (normalized) {
      case 'ASSIGNED':
      case 'PENDENTE':
        nextStatus = 'ACCEPTED';
        actionLabel = 'ACCETTA INCARICO';
      case 'ACCEPTED':
        nextStatus = 'EN_ROUTE';
        actionLabel = 'INIZIA TRASFERIMENTO';
      case 'EN_ROUTE':
        nextStatus = 'CHECKED_IN';
        actionLabel = 'CHECK-IN';
      case 'CHECKED_IN':
        nextStatus = 'IN_PROGRESS';
        actionLabel = 'INIZIA LAVORO';
      case 'IN_PROGRESS':
      case 'WAITING':
      case 'COMPLETED':
        nextStatus = null;
        actionLabel = 'COMPILA RAPPORTO';
      default:
        return const SizedBox.shrink();
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        icon: Icon(
          nextStatus == null
              ? Icons.assignment_rounded
              : Icons.play_arrow_rounded,
          size: 16,
        ),
        label: Text(actionLabel),
        onPressed: () async {
          if (nextStatus != null) {
            try {
              if (nextStatus == 'CHECKED_IN') {
                final position = await _positionForCheckIn();
                await ApiService.instance.checkInTask(
                  taskId,
                  latitude: position.latitude,
                  longitude: position.longitude,
                  accuracy: position.accuracy,
                );
              } else {
                await ApiService.instance.updateTaskStatus(taskId, nextStatus);
              }
              if (mounted) _refreshTasks();
            } catch (error) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Avvio non riuscito: $error')),
                );
              }
            }
            return;
          }
          if (!mounted) return;
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ReportClosureScreen(
                checklistResults: const {},
                antennaId: antennaId ?? 'GENERICO',
                taskId: taskId,
              ),
            ),
          );
        },
      ),
    );
  }

  Future<Position> _positionForCheckIn() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw StateError('Attiva la localizzazione per eseguire il check-in.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw StateError('Permesso GPS obbligatorio per il check-in.');
    }
    return Geolocator.getCurrentPosition().timeout(const Duration(seconds: 15));
  }

  Color _priorityColor(String priority) {
    switch (priority.toUpperCase()) {
      case 'ALTA':
      case 'URGENTE':
      case 'HIGH':
        return AppColors.red;

      case 'BASSA':
      case 'LOW':
        return AppColors.green;

      default:
        return AppColors.orange;
    }
  }

  Widget _statusPill(String status) {
    final isCompleted =
        status == 'COMPLETATO' || status == 'COMPLETED' || status == 'CHIUSO';

    final color = isCompleted ? AppColors.green : AppColors.orange;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: color,
          fontSize: 8,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _loadingCard() {
    return Container(
      height: 90,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.cyan,
          ),
        ),
      ),
    );
  }

  Widget _emptyCard({required IconData icon, required String text}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.green, size: 24),
          const SizedBox(width: 13),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorCard(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.red.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.red.withValues(alpha: 0.18)),
      ),
      child: Text(
        text,
        style: const TextStyle(color: AppColors.red, fontSize: 11),
      ),
    );
  }

  // ==========================================================
  // TOOLS
  // ==========================================================
}

// ============================================================

class AntennaMapScreen extends StatelessWidget {
  const AntennaMapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tenantId = SessionService.instance.tenantId;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Mappa antenne'),
        leading: const CustomBackButton(),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: tenantId == null
            ? null
            : FirebaseFirestore.instance
                  .collection('antennas')
                  .where('tenantId', isEqualTo: tenantId)
                  .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.cyan),
            );
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Text(
                'Nessuna antenna registrata nel database.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            );
          }

          final docs = snapshot.data!.docs;

          final List<Marker> markers = [];

          LatLng mapCenter = const LatLng(41.9028, 12.4964);

          for (final doc in docs) {
            final data = doc.data();

            if (data is! Map<String, dynamic>) continue;

            final antennaId = data['antenna_id']?.toString() ?? doc.id;

            final dynamic latRaw = data['lat'] ?? data['latitude'];

            final dynamic lngRaw = data['lng'] ?? data['longitude'];

            final lat = latRaw is num
                ? latRaw.toDouble()
                : double.tryParse(latRaw?.toString() ?? '');

            final lng = lngRaw is num
                ? lngRaw.toDouble()
                : double.tryParse(lngRaw?.toString() ?? '');

            if (lat != null && lng != null) {
              mapCenter = LatLng(lat, lng);

              markers.add(
                Marker(
                  point: LatLng(lat, lng),
                  width: 44,
                  height: 44,
                  child: GestureDetector(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              AntennaDashboardScreen(antennaId: antennaId),
                        ),
                      );
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF16A34A),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.green.withValues(alpha: 0.40),
                            blurRadius: 14,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.cell_tower_rounded,
                        color: Colors.white,
                        size: 21,
                      ),
                    ),
                  ),
                ),
              );
            }
          }

          if (markers.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Trovate ${docs.length} antenne nel database, ma nessuna possiede coordinate GPS valide.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                ),
              ),
            );
          }

          return Column(
            children: [
              Expanded(
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: mapCenter,
                    initialZoom: 13,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.gestionale_radio',
                    ),
                    MarkerLayer(markers: markers),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ============================================================
// STORICO INTERVENTI
// ============================================================

// ============================================================
// SCANNER
// ============================================================

class ScanAntennaScreen extends StatefulWidget {
  const ScanAntennaScreen({super.key});

  @override
  State<ScanAntennaScreen> createState() => _ScanAntennaScreenState();
}

class _ScanAntennaScreenState extends State<ScanAntennaScreen> {
  final MobileScannerController _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
  );

  final TextEditingController _manualController = TextEditingController();

  bool _isScanning = true;

  String _statusMessage =
      'Inquadra il codice QR oppure inserisci manualmente l’ID.';

  void _navigateToAntenna(String antennaId) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => AntennaActionChoiceScreen(antennaId: antennaId),
          ),
        )
        .then((_) {
          if (!mounted) return;

          setState(() {
            _isScanning = true;
            _statusMessage =
                'Inquadra il codice QR oppure inserisci manualmente l’ID.';
          });

          _scannerController.start();
        });
  }

  void _handleDetection(BarcodeCapture capture) {
    if (!_isScanning) return;

    if (capture.barcodes.isEmpty) return;

    final barcode = capture.barcodes.first;
    final rawValue = barcode.rawValue;

    if (rawValue == null || rawValue.isEmpty) return;

    setState(() {
      _isScanning = false;
      _statusMessage = 'Antenna trovata: $rawValue';
    });

    _scannerController.stop();

    Future.microtask(() => _navigateToAntenna(rawValue));
  }

  void _submitManualId() {
    final antennaId = _manualController.text.trim();

    if (antennaId.isEmpty) {
      setState(() {
        _statusMessage = 'Inserisci un ID antenna valido.';
      });
      return;
    }

    setState(() {
      _isScanning = false;
      _statusMessage = 'ID antenna: $antennaId';
    });

    _scannerController.stop();

    _navigateToAntenna(antennaId);
  }

  @override
  void dispose() {
    _scannerController.dispose();
    _manualController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Scansiona antenna'),
        leading: const CustomBackButton(),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
              ),
              child: Text(
                _statusMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ),

            const SizedBox(height: 14),

            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(25),
                child: MobileScanner(
                  controller: _scannerController,
                  onDetect: _handleDetection,
                ),
              ),
            ),

            const SizedBox(height: 14),

            TextField(
              controller: _manualController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Inserisci ID antenna',
                hintStyle: const TextStyle(color: AppColors.textSecondary),
                filled: true,
                fillColor: AppColors.surface,
                prefixIcon: const Icon(
                  Icons.cell_tower_rounded,
                  color: AppColors.cyan,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(17),
                  borderSide: BorderSide.none,
                ),
              ),
            ),

            const SizedBox(height: 10),

            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _submitManualId,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.cyan,
                      foregroundColor: const Color(0xFF151518),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      'USA ID MANUALE',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: IconButton(
                    onPressed: () => _scannerController.toggleTorch(),
                    icon: const Icon(
                      Icons.flashlight_on_rounded,
                      color: AppColors.cyan,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// ANTENNA ACTION CHOICE
// ============================================================

class AntennaActionChoiceScreen extends StatelessWidget {
  final String antennaId;

  const AntennaActionChoiceScreen({required this.antennaId, super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Antenna individuata'),
        leading: const CustomBackButton(),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.cyan.withValues(alpha: 0.10),
                    AppColors.blue.withValues(alpha: 0.06),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.cyan.withValues(alpha: 0.16),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'POSTAZIONE',
                    style: TextStyle(
                      color: AppColors.cyan,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    antennaId,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 7),
                  const Text(
                    'Seleziona l’operazione da eseguire.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            _buildChoiceCard(
              context,
              title: 'Dettagli tecnici',
              subtitle: 'Scheda tecnica e storico della postazione.',
              icon: Icons.dashboard_customize_rounded,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        AntennaDashboardScreen(antennaId: antennaId),
                  ),
                );
              },
            ),

            const SizedBox(height: 12),

            _buildChoiceCard(
              context,
              title: 'Nuovo report manutenzione',
              subtitle: 'Segnala anomalie, carica foto e chiudi.',
              icon: Icons.report_problem_rounded,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ReportClosureScreen(
                      checklistResults: const <String, bool>{},
                      antennaId: antennaId,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChoiceCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(17),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
          ),
          child: Row(
            children: [
              Container(
                width: 49,
                height: 49,
                decoration: BoxDecoration(
                  color: AppColors.cyan.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(icon, color: AppColors.cyan, size: 23),
              ),
              const SizedBox(width: 14),
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
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 10,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// RIPARAZIONI
// ============================================================
