class TaskSummary {
  TaskSummary(this.data);
  final Map<String, dynamic> data;
  String get id => data['id']?.toString() ?? '';
  String get title => data['title']?.toString() ?? 'Intervento';
  String get status {
    final raw =
        data['status']?.toString().trim().toUpperCase().replaceAll(' ', '_') ??
        'ASSIGNED';
    return const {
          'PENDENTE': 'ASSIGNED',
          'ACCETTATO': 'ACCEPTED',
          'IN_TRANSITO': 'EN_ROUTE',
          'ROUTE': 'EN_ROUTE',
          'CHECK_IN': 'CHECKED_IN',
          'CHECKEDIN': 'CHECKED_IN',
          'IN_CORSO': 'IN_PROGRESS',
          'IN_LAVORAZIONE': 'IN_PROGRESS',
          'IN_ATTESA': 'WAITING',
          'COMPLETATO': 'COMPLETED',
          'REPORT': 'REPORT_SUBMITTED',
          'SUBMITTED': 'REPORT_SUBMITTED',
          'APPROVATO': 'APPROVED',
          'CHIUSO': 'CLOSED',
          'ANNULLATO': 'CANCELLED',
          'CANCELED': 'CANCELLED',
        }[raw] ??
        raw;
  }

  String get priority => data['priority']?.toString().toUpperCase() ?? 'MEDIUM';
  String? get antennaId => data['antennaId']?.toString();
  DateTime? get dueAt =>
      DateTime.tryParse(data['dueAt']?.toString() ?? '')?.toLocal();
  bool get archived => {'CLOSED', 'CANCELLED', 'APPROVED'}.contains(status);
  bool get awaitingReview => status == 'REPORT_SUBMITTED';
  bool overdueAt(DateTime now) =>
      !archived &&
      !awaitingReview &&
      status != 'COMPLETED' &&
      dueAt != null &&
      dueAt!.isBefore(now);
  bool matches(String query) => [
    title,
    id,
    antennaId,
    priority,
    status,
    data['description'],
  ].join(' ').toLowerCase().contains(query.trim().toLowerCase());
  String? get nextAction => switch (status) {
    'ASSIGNED' || 'PENDENTE' => 'ACCEPTED',
    'ACCEPTED' => 'CHECKED_IN',
    'EN_ROUTE' => 'CHECKED_IN',
    'CHECKED_IN' => 'REPORT',
    'IN_PROGRESS' || 'WAITING' || 'COMPLETED' || 'REJECTED' => 'REPORT',
    _ => null,
  };
  String get statusLabel =>
      const {
        'CREATED': 'Da assegnare',
        'ASSIGNED': 'Da accettare',
        'ACCEPTED': 'Accettato',
        'EN_ROUTE': 'In trasferimento',
        'CHECKED_IN': 'Sul posto',
        'IN_PROGRESS': 'In lavorazione',
        'WAITING': 'In attesa',
        'COMPLETED': 'Rapporto da inviare',
        'REPORT_SUBMITTED': 'In revisione',
        'APPROVED': 'Approvato',
        'REJECTED': 'Da correggere',
        'CLOSED': 'Chiuso',
        'CANCELLED': 'Annullato',
      }[status] ??
      status.replaceAll('_', ' ');
  String get priorityLabel =>
      const {
        'CRITICAL': 'Critica',
        'HIGH': 'Alta',
        'MEDIUM': 'Media',
        'LOW': 'Bassa',
      }[priority] ??
      priority;
  static List<TaskSummary> ordered(Iterable<TaskSummary> tasks, DateTime now) {
    return tasks.toList()..sort((a, b) {
      if (a.archived != b.archived) return a.archived ? 1 : -1;
      if (a.overdueAt(now) != b.overdueAt(now)) {
        return a.overdueAt(now) ? -1 : 1;
      }
      const rank = {'CRITICAL': 0, 'HIGH': 1, 'MEDIUM': 2, 'LOW': 3};
      final severity = (rank[a.priority] ?? 2).compareTo(rank[b.priority] ?? 2);
      if (severity != 0) return severity;
      if (a.dueAt == null && b.dueAt != null) return 1;
      if (b.dueAt == null && a.dueAt != null) return -1;
      return a.dueAt?.compareTo(b.dueAt ?? a.dueAt!) ?? a.id.compareTo(b.id);
    });
  }
}
