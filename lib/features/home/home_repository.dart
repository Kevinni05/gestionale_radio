import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/api_service.dart';

class HomeRepository {
  HomeRepository(this.api);
  final ApiService api;
  Future<List<Map<String, dynamic>>> tasks() => api.getMyTasks();
  Future<int> reports() => api.getMyReportCount();
}

final homeRepositoryProvider = Provider<HomeRepository>(
  (ref) => HomeRepository(ApiService.instance),
);
final homeTasksProvider = FutureProvider<List<Map<String, dynamic>>>(
  (ref) => ref.watch(homeRepositoryProvider).tasks(),
);
final homeReportsProvider = FutureProvider<int>(
  (ref) => ref.watch(homeRepositoryProvider).reports(),
);
