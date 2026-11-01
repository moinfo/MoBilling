/// Employee of the Month: `EmployeeOfMonthController` endpoints.
library;

import '../api_client.dart';
import '../json.dart';
import 'eotm_models.dart';

class EmployeeOfMonthService {
  const EmployeeOfMonthService(this._api);
  final ApiClient _api;

  /// GET /employee-of-month/current — null means the tenant hasn't enabled
  /// this feature yet, or no cycle exists (e.g. before the 1st rolls around).
  Future<EotmCurrent?> current() async {
    final body = await _api.get<Map<String, dynamic>>('/employee-of-month/current');
    final data = body.object('data');
    return data == null ? null : EotmCurrent.fromJson(data);
  }

  /// POST /employee-of-month/vote — throws [ApiException] (already voted,
  /// window closed, voting for yourself, etc.) with a ready-to-show message.
  Future<void> vote({
    required String cycleId,
    required String candidateId,
    required String reason,
  }) =>
      _api.post<dynamic>('/employee-of-month/vote', body: {
        'cycle_id': cycleId,
        'candidate_id': candidateId,
        'reason': reason,
      });
}
