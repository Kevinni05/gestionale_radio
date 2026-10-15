import 'antenna_dossier_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'asset_history_screen.dart';
import 'checklist_screen.dart';
import 'report_closure_screen.dart';
import 'models/antenna.dart';
import 'providers/antenna_provider.dart';
import 'services/api_service.dart';

class AntennaDashboardScreen extends ConsumerStatefulWidget {
  final String antennaId;

  const AntennaDashboardScreen({this.antennaId = 'ANT-987', super.key});

  @override
  ConsumerState<AntennaDashboardScreen> createState() =>
      _AntennaDashboardScreenState();
}

class _AntennaDashboardScreenState extends ConsumerState<AntennaDashboardScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animationController;
  late Future<Map<String, dynamic>> _notes;
  final _noteInput = TextEditingController();
  bool _saving = false;
  Future<Map<String, dynamic>> _fetchNotes() =>
      ApiService.instance.getAntennaNotes(widget.antennaId);
  Future<void> _saveNote() async {
    if (_saving || _noteInput.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      await ApiService.instance.addAntennaNote(
        widget.antennaId,
        _noteInput.text.trim(),
      );
      _noteInput.clear();
      if (mounted) setState(() => _notes = _fetchNotes());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Salvataggio non riuscito: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _notes = _fetchNotes();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _noteInput.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final antennaAsync = ref.watch(antennaDocumentProvider(widget.antennaId));

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: antennaAsync.when(
          data: (antenna) => _buildDashboard(context, antenna),
          loading: () => _buildLoading(context),
          error: (error, stack) => _buildError(context, error.toString()),
        ),
      ),
    );
  }

  Widget _buildDashboard(BuildContext context, Antenna antenna) {
    final specCards = antenna.specs.entries.toList();

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          pinned: true,
          expandedHeight: 170,
          flexibleSpace: FlexibleSpaceBar(
            background: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Theme.of(context).primaryColor.withValues(alpha: 0.14),
                    Theme.of(
                      context,
                    ).colorScheme.secondary.withValues(alpha: 0.1),
                  ],
                ),
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      antenna.name,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                        color: Theme.of(context).primaryColor,
                        shadows: [
                          Shadow(
                            color: Theme.of(
                              context,
                            ).primaryColor.withValues(alpha: 0.35),
                            blurRadius: 16,
                          ),
                        ],
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Theme.of(
                            context,
                          ).colorScheme.secondary.withValues(alpha: 0.55),
                        ),
                        gradient: LinearGradient(
                          colors: [
                            Theme.of(
                              context,
                            ).colorScheme.secondary.withValues(alpha: 0.18),
                            Theme.of(
                              context,
                            ).colorScheme.secondary.withValues(alpha: 0.06),
                          ],
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Theme.of(context).colorScheme.secondary,
                              boxShadow: [
                                BoxShadow(
                                  color: Theme.of(context).colorScheme.secondary
                                      .withValues(alpha: 0.6),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'ANTENNA ID: ${antenna.id}',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.secondary,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.all(20),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              _buildSectionTitle(context, 'Posizione antenna'),
              _buildInfoRow(
                context,
                'Latitudine',
                antenna.latitude.toStringAsFixed(5),
              ),
              const SizedBox(height: 8),
              _buildInfoRow(
                context,
                'Longitudine',
                antenna.longitude.toStringAsFixed(5),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ReportClosureScreen(
                      antennaId: antenna.id,
                      checklistResults: {
                        for (final item in antenna.checklistTemplate)
                          item: false,
                      },
                    ),
                  ),
                ),
                icon: const Icon(Icons.note_add_outlined),
                label: const Text('Crea nuovo report'),
              ),
              const SizedBox(height: 24),
              _buildSectionTitle(context, 'Note condivise'),
              FutureBuilder<Map<String, dynamic>>(
                future: _notes,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Text(
                      'Note non disponibili: servizio da configurare.',
                    );
                  }
                  if (!snapshot.hasData) return const LinearProgressIndicator();
                  final notes = snapshot.data!['notes'];
                  final items = notes is List ? notes : const [];
                  return Column(
                    children: [
                      for (final note in items)
                        if (note is Map)
                          Card(
                            child: ListTile(
                              title: Text((note['text'] ?? '').toString()),
                              subtitle: Text(
                                (note['createdAt'] ?? '').toString(),
                              ),
                            ),
                          ),
                      TextField(
                        controller: _noteInput,
                        maxLines: 3,
                        maxLength: 2000,
                        decoration: const InputDecoration(
                          labelText: 'Nota condivisa',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          onPressed: _saving ? null : _saveNote,
                          icon: const Icon(Icons.save_outlined),
                          label: const Text('Salva nota'),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),
              _buildSectionTitle(context, 'Controlli obbligatori'),
              const SizedBox(height: 12),
              _buildChecklistSummary(context, antenna.checklistTemplate),
              const SizedBox(height: 28),
              _buildSectionTitle(context, 'Specifiche tecniche'),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) => GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: constraints.maxWidth >= 650
                        ? 3
                        : constraints.maxWidth < 340
                        ? 1
                        : 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    mainAxisExtent: 144,
                  ),
                  itemCount: specCards.length,
                  itemBuilder: (context, index) {
                    final entry = specCards[index];
                    return _buildEnhancedTechCard(
                      context,
                      entry.key,
                      entry.value.toString(),
                      index,
                    );
                  },
                ),
              ),
              const SizedBox(height: 34),
              _buildActionButton(context, antenna),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => AssetHistoryScreen(
                        assetId: antenna.id,
                        assetName: antenna.name,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.history),
                label: const Text('STORIA ASSET'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AntennaDossierScreen(antennaId: antenna.id),
                  ),
                ),
                icon: const Icon(Icons.folder_open_outlined),
                label: const Text('FASCICOLO IMPIANTO'),
              ),
              const SizedBox(height: 30),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _buildLoading(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Theme.of(context).primaryColor),
            const SizedBox(height: 18),
            Text(
              'Caricamento dati antenna...',
              style: TextStyle(
                color: Colors.grey.withValues(alpha: 0.85),
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError(BuildContext context, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.wifi_off,
              size: 60,
              color: Theme.of(context).colorScheme.secondary,
            ),
            const SizedBox(height: 20),
            Text(
              'Errore caricamento antenna',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: TextStyle(
                color: Colors.grey.withValues(alpha: 0.82),
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: TextStyle(
        color: Colors.grey.withValues(alpha: 0.7),
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.6,
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.grey.withValues(alpha: 0.75),
            fontSize: 14,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildChecklistSummary(BuildContext context, List<String> checklist) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: checklist.take(4).map((item) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Icon(
                Icons.check_circle,
                size: 18,
                color: Theme.of(context).colorScheme.secondary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildEnhancedTechCard(
    BuildContext context,
    String title,
    String value,
    int index,
  ) {
    return SlideTransition(
      position:
          Tween<Offset>(
            begin: Offset(0.2, 0.2 * (index % 2 == 0 ? 1 : -1)),
            end: Offset.zero,
          ).animate(
            CurvedAnimation(
              parent: _animationController,
              curve: Interval(0.1 + (index * 0.1), 0.9, curve: Curves.easeOut),
            ),
          ),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.28),
              blurRadius: 20,
              spreadRadius: 0,
              offset: const Offset(0, 8),
            ),
          ],
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withValues(alpha: 0.05),
              Colors.white.withValues(alpha: 0.02),
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.signal_cellular_alt,
                  color: Theme.of(context).primaryColor,
                  size: 20,
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: Colors.grey.withValues(alpha: 0.7),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    value,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton(BuildContext context, Antenna antenna) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          Navigator.push(
            context,
            PageRouteBuilder(
              pageBuilder: (context, animation, secondaryAnimation) =>
                  ChecklistScreen(
                    checklistItems: antenna.checklistTemplate,
                    antennaId: antenna.id,
                  ),
              transitionsBuilder:
                  (context, animation, secondaryAnimation, child) {
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position:
                            Tween<Offset>(
                              begin: const Offset(0.35, 0.0),
                              end: Offset.zero,
                            ).animate(
                              CurvedAnimation(
                                parent: animation,
                                curve: Curves.easeOut,
                              ),
                            ),
                        child: child,
                      ),
                    );
                  },
              transitionDuration: const Duration(milliseconds: 650),
            ),
          );
        },
        child: Container(
          width: double.infinity,
          height: 64,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Theme.of(context).primaryColor.withValues(alpha: 0.28),
                Theme.of(context).primaryColor.withValues(alpha: 0.12),
              ],
            ),
            border: Border.all(
              color: Theme.of(context).primaryColor.withValues(alpha: 0.7),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).primaryColor.withValues(alpha: 0.18),
                blurRadius: 24,
                spreadRadius: 0,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.play_circle_fill,
                  color: Theme.of(context).primaryColor,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Text(
                  'AVVIA CHECKLIST',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2.0,
                    color: Theme.of(context).primaryColor,
                    shadows: [
                      Shadow(
                        color: Theme.of(
                          context,
                        ).primaryColor.withValues(alpha: 0.3),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
