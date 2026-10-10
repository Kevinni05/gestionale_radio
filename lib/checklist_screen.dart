import 'package:flutter/material.dart';
import 'report_closure_screen.dart';

class ChecklistScreen extends StatefulWidget {
  static const defaultChecklistItems = [
    'Verifica serraggio traliccio',
    'Controllo integrità cavi coassiali',
    'Test valori ROS (TX/RX)',
    'Controllo infiltrazioni quadro elettrico',
  ];

  final List<String> checklistItems;
  final String antennaId;
  final String? taskId;

  const ChecklistScreen({
    this.checklistItems = defaultChecklistItems,
    this.antennaId = 'ANT-987',
    this.taskId,
    super.key,
  });

  @override
  State<ChecklistScreen> createState() => _ChecklistScreenState();
}

class _ChecklistScreenState extends State<ChecklistScreen>
    with SingleTickerProviderStateMixin {
  late final Map<String, bool> _tasks;

  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _tasks = {for (final item in widget.checklistItems) item: false};
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  bool get _allCompleted => _tasks.values.every((element) => element == true);

  void toggleTask(String taskName) {
    setState(() {
      _tasks[taskName] = !_tasks[taskName]!;
    });
  }

  @override
  Widget build(BuildContext context) {
    final allCompleted = _allCompleted;

    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: CustomScrollView(
          slivers: [
            // Custom AppBar
            SliverAppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              pinned: true,
              expandedHeight: 140,
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Theme.of(
                          context,
                        ).colorScheme.secondary.withValues(alpha: 0.15),
                        Theme.of(context).primaryColor.withValues(alpha: 0.1),
                      ],
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "CHECKLIST OPERATIVA",
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2.5,
                          color: Theme.of(context).colorScheme.secondary,
                          shadows: [
                            Shadow(
                              color: Theme.of(
                                context,
                              ).colorScheme.secondary.withValues(alpha: 0.4),
                              blurRadius: 15,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                        child: Text(
                          'Antenna: ${widget.antennaId}',
                          style: TextStyle(
                            color: Colors.grey.withValues(alpha: 0.85),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Content
            SliverPadding(
              padding: const EdgeInsets.all(20),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  Column(
                    children: [
                      // Progress indicator
                      _buildProgressIndicator(context, allCompleted),
                      const SizedBox(height: 30),
                      // Checklist items
                      ..._buildChecklistItems(context, allCompleted),
                      const SizedBox(height: 40),
                      // Action button
                      _buildActionButton(context, allCompleted),
                      const SizedBox(height: 40),
                    ],
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressIndicator(BuildContext context, bool allCompleted) {
    int completedCount = _tasks.values.where((v) => v == true).length;
    double progress = completedCount / _tasks.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              "PROGRESSO",
              style: TextStyle(
                color: Colors.grey.withValues(alpha: 0.7),
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.5,
              ),
            ),
            Text(
              "$completedCount/${_tasks.length}",
              style: TextStyle(
                color: Theme.of(context).colorScheme.secondary,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            backgroundColor: Colors.white.withValues(alpha: 0.1),
            valueColor: AlwaysStoppedAnimation<Color>(
              allCompleted
                  ? Theme.of(context).colorScheme.secondary
                  : Theme.of(context).primaryColor,
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildChecklistItems(BuildContext context, bool allCompleted) {
    List<Widget> items = [];
    int index = 0;

    _tasks.forEach((taskName, isDone) {
      items.add(
        SlideTransition(
          position:
              Tween<Offset>(
                begin: const Offset(-1.0, 0.0),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(
                  parent: _animationController,
                  curve: Interval(
                    0.1 + (index * 0.1),
                    0.9,
                    curve: Curves.easeOut,
                  ),
                ),
              ),
          child: GestureDetector(
            onTap: () {
              setState(() {
                _tasks[taskName] = !isDone;
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDone
                      ? Theme.of(context).colorScheme.secondary
                      : Colors.white.withValues(alpha: 0.1),
                  width: isDone ? 2.0 : 1.5,
                ),
                boxShadow: [
                  if (isDone)
                    BoxShadow(
                      color: Theme.of(
                        context,
                      ).colorScheme.secondary.withValues(alpha: 0.25),
                      blurRadius: 20,
                      spreadRadius: 0,
                      offset: const Offset(0, 8),
                    )
                  else
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 12,
                      spreadRadius: 0,
                    ),
                ],
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    isDone
                        ? Theme.of(
                            context,
                          ).colorScheme.secondary.withValues(alpha: 0.08)
                        : Colors.white.withValues(alpha: 0.03),
                    Colors.white.withValues(alpha: 0.01),
                  ],
                ),
              ),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDone
                          ? Theme.of(
                              context,
                            ).colorScheme.secondary.withValues(alpha: 0.15)
                          : Colors.transparent,
                    ),
                    child: Icon(
                      isDone
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      color: isDone
                          ? Theme.of(context).colorScheme.secondary
                          : Colors.grey.withValues(alpha: 0.5),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      taskName,
                      style: TextStyle(
                        color: isDone
                            ? Colors.white
                            : Colors.grey.withValues(alpha: 0.8),
                        fontWeight: isDone ? FontWeight.w600 : FontWeight.w500,
                        fontSize: 15,
                        letterSpacing: 0.3,
                        decoration: isDone
                            ? TextDecoration.lineThrough
                            : TextDecoration.none,
                        decorationColor: Theme.of(
                          context,
                        ).colorScheme.secondary,
                        decorationThickness: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      items.add(const SizedBox(height: 0));
      index++;
    });

    return items;
  }

  Widget _buildActionButton(BuildContext context, bool allCompleted) {
    return GestureDetector(
      onTap: allCompleted
          ? () {
              Navigator.push(
                context,
                PageRouteBuilder(
                  pageBuilder: (context, animation, secondaryAnimation) =>
                      ReportClosureScreen(
                        checklistResults: _tasks,
                        antennaId: widget.antennaId,
                        taskId: widget.taskId,
                      ),
                  transitionsBuilder:
                      (context, animation, secondaryAnimation, child) {
                        return SlideTransition(
                          position:
                              Tween<Offset>(
                                begin: const Offset(1.0, 0.0),
                                end: Offset.zero,
                              ).animate(
                                CurvedAnimation(
                                  parent: animation,
                                  curve: Curves.easeOut,
                                ),
                              ),
                          child: child,
                        );
                      },
                  transitionDuration: const Duration(milliseconds: 600),
                ),
              );
            }
          : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        width: double.infinity,
        height: 64,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: allCompleted
                ? [
                    Theme.of(context).primaryColor.withValues(alpha: 0.25),
                    Theme.of(context).primaryColor.withValues(alpha: 0.1),
                  ]
                : [
                    Colors.grey.withValues(alpha: 0.08),
                    Colors.grey.withValues(alpha: 0.04),
                  ],
          ),
          border: Border.all(
            color: allCompleted
                ? Theme.of(context).primaryColor.withValues(alpha: 0.6)
                : Colors.transparent,
            width: 2,
          ),
          boxShadow: allCompleted
              ? [
                  BoxShadow(
                    color: Theme.of(
                      context,
                    ).primaryColor.withValues(alpha: 0.15),
                    blurRadius: 20,
                    spreadRadius: 0,
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 8,
                  ),
                ],
        ),
        child: Center(
          child: Text(
            allCompleted ? "PROCEDI ALLA FIRMA" : "COMPLETA I CONTROLLI",
            style: TextStyle(
              fontSize: 16,
              letterSpacing: 1.8,
              fontWeight: FontWeight.w700,
              color: allCompleted
                  ? Theme.of(context).primaryColor
                  : Colors.grey.withValues(alpha: 0.5),
              shadows: allCompleted
                  ? [
                      Shadow(
                        color: Theme.of(
                          context,
                        ).primaryColor.withValues(alpha: 0.3),
                        blurRadius: 10,
                      ),
                    ]
                  : [],
            ),
          ),
        ),
      ),
    );
  }
}
