import 'package:flutter_test/flutter_test.dart';
import 'package:gestionale_radio/models/task_summary.dart';

void main() {
  test('approved reports leave the review queue', () {
    expect(TaskSummary({'status': 'APPROVED'}).awaitingReview, isFalse);
    expect(TaskSummary({'status': 'REPORT_SUBMITTED'}).awaitingReview, isTrue);
  });
  test(
    'reviewed and archived tasks do not count as missed field deadlines',
    () {
      final now = DateTime.utc(2026, 10, 3);
      for (final status in [
        'COMPLETED',
        'CLOSED',
        'CANCELLED',
        'APPROVED',
        'REPORT_SUBMITTED',
      ]) {
        expect(
          TaskSummary({
            'status': status,
            'dueAt': '2026-01-01T00:00:00Z',
          }).overdueAt(now),
          isFalse,
        );
      }
      expect(
        TaskSummary({
          'status': 'IN_PROGRESS',
          'dueAt': '2026-01-01T00:00:00Z',
        }).overdueAt(now),
        isTrue,
      );
    },
  );
  test(
    'orders overdue work, priority and archives without inventing deadlines',
    () {
      final tasks = [
        TaskSummary({
          'id': 'archive',
          'status': 'CLOSED',
          'priority': 'CRITICAL',
        }),
        TaskSummary({'id': 'urgent', 'priority': 'CRITICAL'}),
        TaskSummary({
          'id': 'overdue',
          'priority': 'LOW',
          'dueAt': '2026-01-01T00:00:00Z',
        }),
      ];
      expect(
        TaskSummary.ordered(tasks, DateTime.utc(2026, 10, 3)).map((t) => t.id),
        ['overdue', 'urgent', 'archive'],
      );
      expect(tasks[1].dueAt, isNull);
    },
  );
}
