import '../../core/constants.dart';
import '../../core/supabase_client.dart';
import '../../models/enums.dart';
import '../../models/report.dart';
import '../../models/user_profile.dart';
import '../../models/worker_application.dart';
import '../../models/worker_progress_note.dart';

/// Data access for the municipal staff side: listing field workers, resolving
/// assignee names, a worker's own task list, and the two assignment RPCs.
///
/// Assignment and worker status changes go through SECURITY DEFINER RPCs
/// (`admin_assign_report`, `worker_set_report_status`) — the server enforces
/// that only an official can assign and only the assigned worker can advance.
class WorkerRepo {
  const WorkerRepo._();

  /// All active field workers (not resigned), department first then name.
  /// Officials pick from this list when assigning. RLS lets admins read
  /// every profile. Workers on leave are included but flagged.
  static Future<List<UserProfile>> listWorkers() async {
    final rows = await supabase
        .from(kTableProfiles)
        .select()
        .eq('role', UserRole.worker.wire)
        .isFilter('resigned_at', null)
        .order('department')
        .order('worker_number')
        .order('display_name');
    return rows.map<UserProfile>((r) => UserProfile.fromMap(r)).toList();
  }

  /// Workers for a specific department — used in the assign sheet so admin
  /// sees category-relevant workers first.
  static Future<List<UserProfile>> listWorkersByDepartment(
    AdminDepartment dept,
  ) async {
    final rows = await supabase
        .from(kTableProfiles)
        .select()
        .eq('role', UserRole.worker.wire)
        .eq('department', dept.wire)
        .isFilter('resigned_at', null)
        .order('worker_number')
        .order('display_name');
    return rows.map<UserProfile>((r) => UserProfile.fromMap(r)).toList();
  }

  /// Every user profile, newest first. Superadmins use this in Manage Staff to
  /// promote citizens or reassign roles. RLS lets admins read every profile.
  static Future<List<UserProfile>> listAllProfiles() async {
    final rows = await supabase
        .from(kTableProfiles)
        .select()
        .order('created_at', ascending: false);
    return rows.map<UserProfile>((r) => UserProfile.fromMap(r)).toList();
  }

  /// Superadmin-only role change. Wraps the `set_user_role` SECURITY DEFINER
  /// RPC — the server re-checks `is_superadmin(auth.uid())` and raises if not.
  /// [department]/[city]/[ward] are cleared when null (e.g. demoting to citizen).
  /// Returns the updated profile.
  static Future<UserProfile> setUserRole({
    required String userId,
    required UserRole role,
    AdminDepartment? department,
    String? city,
    String? ward,
  }) async {
    final res = await supabase.rpc(
      'set_user_role',
      params: {
        'p_user_id': userId,
        'p_role': role.wire,
        'p_department': ?department?.wire,
        'p_city': ?city,
        'p_ward': ?ward,
      },
    );
    final row = res is List ? res.first : res;
    return UserProfile.fromMap(row as Map<String, dynamic>);
  }

  /// Display names for a set of user ids (e.g. to label an assignee).
  static Future<Map<String, String>> displayNamesByIds(
    Iterable<String> ids,
  ) async {
    final list = ids.toSet().toList();
    if (list.isEmpty) return {};
    final rows = await supabase
        .from(kTableProfiles)
        .select('id, display_name')
        .inFilter('id', list);
    return {
      for (final r in rows)
        r['id'] as String: (r['display_name'] as String?) ?? 'Worker',
    };
  }

  /// The tasks assigned to a worker, newest first. The dashboard also
  /// subscribes for live updates; this is the initial pull.
  static Future<List<Report>> myTasks(String uid) async {
    final rows = await supabase
        .from(kTableReports)
        .select()
        .eq('assigned_to', uid)
        .order('created_at', ascending: false);
    return rows.map<Report>((r) => Report.fromMap(r)).toList();
  }

  /// Official hands a report to a worker. Returns the updated report.
  static Future<Report> assignReport({
    required String reportId,
    required String workerId,
    String? note,
  }) async {
    final res = await supabase.rpc(
      'admin_assign_report',
      params: {
        'p_report_id': reportId,
        'p_worker_id': workerId,
        if (note != null && note.trim().isNotEmpty) 'p_note': note.trim(),
      },
    );
    final row = res is List ? res.first : res;
    return Report.fromMap(row as Map<String, dynamic>);
  }

  /// Assigned worker advances their task (IN_PROGRESS or RESOLVED), optionally
  /// attaching a resolution note and a proof photo URL. Returns the updated row.
  static Future<Report> workerSetStatus({
    required String reportId,
    required ReportStatus status,
    String? note,
    String? photoUrl,
  }) async {
    final res = await supabase.rpc(
      'worker_set_report_status',
      params: {
        'p_report_id': reportId,
        'p_new_status': status.wire,
        if (note != null && note.trim().isNotEmpty) 'p_note': note.trim(),
        'p_photo_url': ?photoUrl,
      },
    );
    final row = res is List ? res.first : res;
    return Report.fromMap(row as Map<String, dynamic>);
  }

  // ────────── Progress tracking ──────────────────────────────────────────────

  /// Admin asks for a progress update on an in-flight task.
  static Future<Report> requestProgress(String reportId) async {
    final res = await supabase.rpc(
      'admin_request_progress',
      params: {'p_report_id': reportId},
    );
    final row = res is List ? res.first : res;
    return Report.fromMap(row as Map<String, dynamic>);
  }

  /// Worker sends a custom progress update (note + optional photo).
  static Future<WorkerProgressNote> sendProgress({
    required String reportId,
    String? note,
    String? photoUrl,
  }) async {
    final res = await supabase.rpc(
      'worker_send_progress',
      params: {
        'p_report_id': reportId,
        if (note != null && note.trim().isNotEmpty) 'p_note': note.trim(),
        'p_photo_url': ?photoUrl,
      },
    );
    final row = res is List ? res.first : res;
    return WorkerProgressNote.fromMap(row as Map<String, dynamic>);
  }

  /// Fetch all progress notes for a report (admin or assigned worker).
  static Future<List<WorkerProgressNote>> fetchProgressNotes(
    String reportId,
  ) async {
    final rows = await supabase
        .from('worker_progress_notes')
        .select()
        .eq('report_id', reportId)
        .order('created_at');
    return rows
        .map<WorkerProgressNote>((r) => WorkerProgressNote.fromMap(r))
        .toList();
  }

  // ────────── Worker status ──────────────────────────────────────────────────

  /// Worker marks themselves on leave — admin cannot assign them.
  static Future<UserProfile> goOnLeave() async {
    final res = await supabase.rpc('worker_go_on_leave');
    final row = res is List ? res.first : res;
    return UserProfile.fromMap(row as Map<String, dynamic>);
  }

  /// Worker marks themselves available again.
  static Future<UserProfile> markAvailable() async {
    final res = await supabase.rpc('worker_mark_available');
    final row = res is List ? res.first : res;
    return UserProfile.fromMap(row as Map<String, dynamic>);
  }

  /// Worker resigns — converts them back to citizen role.
  static Future<UserProfile> resign() async {
    final res = await supabase.rpc('worker_resign');
    final row = res is List ? res.first : res;
    return UserProfile.fromMap(row as Map<String, dynamic>);
  }

  // ────────── Admin worker management ───────────────────────────────────────

  /// Admin soft-removes a worker (reverts to citizen, sets resigned_at).
  static Future<void> removeWorker(String workerId) async {
    await supabase.rpc(
      'admin_remove_worker',
      params: {'p_worker_id': workerId},
    );
  }

  // ────────── Worker applications ───────────────────────────────────────────

  /// Citizen submits a "Work with Nivara" application.
  static Future<WorkerApplication> submitApplication({String? message}) async {
    final res = await supabase.rpc(
      'submit_worker_application',
      params: {'p_message': ?message},
    );
    final row = res is List ? res.first : res;
    return WorkerApplication.fromMap(row as Map<String, dynamic>);
  }

  /// Admin fetches all worker applications, newest first.
  static Future<List<WorkerApplication>> listApplications() async {
    final rows = await supabase
        .from('worker_applications')
        .select()
        .order('created_at', ascending: false);
    return rows
        .map<WorkerApplication>((r) => WorkerApplication.fromMap(r))
        .toList();
  }

  /// Admin approves or rejects an application.
  static Future<WorkerApplication> reviewApplication({
    required String applicationId,
    required String status, // 'APPROVED' or 'REJECTED'
  }) async {
    final res = await supabase.rpc(
      'admin_review_application',
      params: {
        'p_application_id': applicationId,
        'p_status': status,
      },
    );
    final row = res is List ? res.first : res;
    return WorkerApplication.fromMap(row as Map<String, dynamic>);
  }

  /// Admin approves an application and immediately assigns the user's role & department,
  /// adding them directly to the active workforce list.
  static Future<void> approveWorkerWithAssignment({
    required String applicationId,
    required String applicantId,
    required UserRole role,
    required AdminDepartment department,
  }) async {
    // 1. Mark application as APPROVED
    try {
      await reviewApplication(applicationId: applicationId, status: 'APPROVED');
    } catch (_) {
      // Fallback direct table update
      await supabase
          .from('worker_applications')
          .update({
            'status': 'APPROVED',
            'reviewed_by': supabase.auth.currentUser?.id,
            'reviewed_at': DateTime.now().toIso8601String(),
          })
          .eq('id', applicationId);
    }

    // 2. Update user profile to the assigned role and department, clearing resigned_at
    try {
      await supabase.from(kTableProfiles).update({
        'role': role.wire,
        'department': department.wire,
        'resigned_at': null,
        'on_leave': false,
      }).eq('id', applicantId);
    } catch (_) {
      // Try set_user_role RPC if superadmin policy requires RPC
      await setUserRole(
        userId: applicantId,
        role: role,
        department: department,
      );
    }
  }

  /// Admin deletes a community post.
  static Future<void> deleteCommunityPost(String postId) async {
    await supabase.rpc(
      'admin_delete_community_post',
      params: {'p_post_id': postId},
    );
  }
}
