import api from './axios';

export type ExcusedStatus = 'leave' | 'sick' | 'field';

export interface AttendanceDay {
  id?: string;
  date: string;
  status: ExcusedStatus | null;
  status_note: string | null;
  check_in_at: string | null;
  check_out_at: string | null;
  absent: boolean;
  late: boolean;
  left_early: boolean;
  no_checkout: boolean;
}

export interface AttendanceDeduction {
  id: string;
  date: string;
  penalty_type: 'absent' | 'late' | 'left_early' | 'no_checkout';
  amount: number;
  notes: string | null;
}

export interface MyAttendance {
  settings: {
    check_in_time: string; check_out_time: string; penalties_enabled: boolean;
    penalty_absent: number; penalty_late: number; penalty_left_early: number; penalty_no_checkout: number;
  };
  today: AttendanceDay | null;
  month_label: string;
  present_days: number;
  month_records: AttendanceDay[];
  deduction_total: number;
  deduction_by_type?: { absent: number; late: number; left_early: number; no_checkout: number };
  deductions: AttendanceDeduction[];
}

export interface AttendanceRow extends AttendanceDay {
  user: { id: string; name: string };
}
export interface AttendanceDayResponse {
  date: string;
  check_in_time: string;
  check_out_time: string;
  staff: AttendanceRow[];
}

export interface AttendanceSettings {
  check_in_time: string;
  check_out_time: string;
  penalties_enabled: boolean;
  penalty_absent: number;
  penalty_late: number;
  penalty_left_early: number;
  penalty_no_checkout: number;
  working_days?: number[];
}

export const getMyAttendance = () => api.get<{ data: MyAttendance }>('/attendance/mine');

export const getAttendanceDay = (date: string) =>
  api.get<{ data: AttendanceDayResponse }>('/attendance/day', { params: { date } });

export const recordAttendance = (payload: { user_id: string; date: string; status?: ExcusedStatus | null; status_note?: string | null; check_in?: string | null; check_out?: string | null }) =>
  api.post<{ data: AttendanceRow }>('/attendance/record', payload);

export const getAttendanceSettings = () => api.get<{ data: AttendanceSettings }>('/attendance/settings');
export const updateAttendanceSettings = (data: AttendanceSettings) =>
  api.put<{ data: AttendanceSettings }>('/attendance/settings', data);

export interface AttnDeductionItem {
  id: string; date: string; penalty_type: 'absent'|'late'|'left_early'|'no_checkout';
  amount: number; notes: string | null; waived: boolean; waive_reason: string | null;
}
export interface AttnStaffDeductions {
  user: { id: string; name: string };
  total: number;
  by_type: { absent: number; late: number; left_early: number; no_checkout: number };
  items: AttnDeductionItem[];
}
export interface AttnDeductionsResponse { month_label: string; grand_total: number; staff: AttnStaffDeductions[] }

export const getAttendancePenalties = (month: number, year: number) =>
  api.get<{ data: AttnDeductionsResponse }>('/attendance/penalties', { params: { month, year } });
export const waiveAttendancePenalty = (id: string, reason?: string) =>
  api.post(`/attendance/penalties/${id}/waive`, { reason });
export const unwaiveAttendancePenalty = (id: string) =>
  api.post(`/attendance/penalties/${id}/unwaive`);

export interface AttendanceOverview {
  today: { total: number; present: number; late: number; left_early: number; excused: number; not_recorded: number };
  month_label: string;
  working_days_so_far: number;
  deduction_total: number;
  by_type: { absent: number; late: number; left_early: number; no_checkout: number };
  staff: { user: { id: string; name: string }; present_days: number; deductions: number }[];
}
export const getAttendanceDashboard = () =>
  api.get<{ data: AttendanceOverview }>('/attendance/dashboard');

export interface DeviceConfig {
  name: string;
  is_active: boolean;
  last_event_at: string | null;
  webhook_url: string;
}
export interface DeviceEvent {
  id: string;
  content_type: string | null;
  employee_no: string | null;
  event_time: string | null;
  parsed: Record<string, unknown> | null;
  payload: string | null;
  created_at: string;
}
export const getDeviceConfig = () => api.get<{ data: DeviceConfig }>('/attendance/device-config');
export const getDeviceEvents = () => api.get<{ data: DeviceEvent[] }>('/attendance/device-events');
export const regenerateDeviceToken = () =>
  api.post<{ data: { webhook_url: string } }>('/attendance/device-regenerate');

export interface DeviceMappingStaff { id: string; name: string; device_employee_no: string | null }
export interface DeviceMappings { staff: DeviceMappingStaff[]; unlinked: string[] }
export interface ImportResult { matched: number; unmatched: number; days: number }

export const getDeviceMappings = () => api.get<{ data: DeviceMappings }>('/attendance/device-mappings');
export const saveDeviceMapping = (user_id: string, device_employee_no: string | null) =>
  api.post<{ message: string; import: ImportResult }>('/attendance/device-mappings', { user_id, device_employee_no });
export const importDeviceEvents = () => api.post<{ data: ImportResult }>('/attendance/device-import');

// ── Monthly per-staff check-in/out report ──────────────────────────────────
export interface ReportDay {
  date: string;
  weekday: string;
  working: boolean;
  holiday: boolean;
  status: ExcusedStatus | null;
  check_in_at: string | null;
  check_out_at: string | null;
  late: boolean;
  left_early: boolean;
  no_checkout: boolean;
  absent: boolean;
  deduction: number;
}
export interface AttendanceReport {
  user: { id: string; name: string };
  month_label: string;
  check_in_time: string;
  check_out_time: string;
  days: ReportDay[];
  totals: { present: number; late: number; left_early: number; no_checkout: number; absent: number; excused: number; deduction_total: number };
}
export const getAttendanceReport = (user_id: string, month: number, year: number) =>
  api.get<{ data: AttendanceReport }>('/attendance/report', { params: { user_id, month, year } });

export const getMyAttendanceReport = (month: number, year: number) =>
  api.get<{ data: AttendanceReport }>('/attendance/my-report', { params: { month, year } });

export const exportAttendanceReport = (user_id: string, month: number, year: number, format: 'pdf' | 'csv') =>
  api.get('/attendance/report/export', { params: { user_id, month, year, format }, responseType: 'blob' });

// ── iVMS-4200 CSV export → upload ──────────────────────────────────────────
export interface SheetMapping {
  match_by: 'name' | 'employee_no';
  identity_col: number;
  date_col: number | null;
  time_mode: 'single' | 'inout';
  in_col: number | null;
  out_col: number | null;
  time_col: number | null;
  employee_no_col?: number | null;
}
export interface SheetPreview {
  headers: string[];
  rows: string[][];
  total: number;
  guess: SheetMapping;
}
export interface SheetImportResult {
  days: number;
  matched_rows: number;
  unmatched: Record<string, number>;
  skipped: number;
  linked?: number;
}

export const previewAttendanceSheet = (file: File) => {
  const fd = new FormData();
  fd.append('file', file);
  return api.post<{ data: SheetPreview }>('/attendance/import/preview', fd, {
    headers: { 'Content-Type': 'multipart/form-data' },
  });
};
export const commitAttendanceSheet = (file: File, map: SheetMapping) => {
  const fd = new FormData();
  fd.append('file', file);
  fd.append('match_by', map.match_by);
  fd.append('identity_col', String(map.identity_col));
  if (map.date_col !== null) fd.append('date_col', String(map.date_col));
  fd.append('time_mode', map.time_mode);
  if (map.time_col !== null) fd.append('time_col', String(map.time_col));
  if (map.in_col !== null) fd.append('in_col', String(map.in_col));
  if (map.out_col !== null) fd.append('out_col', String(map.out_col));
  if (map.employee_no_col !== null && map.employee_no_col !== undefined) fd.append('employee_no_col', String(map.employee_no_col));
  return api.post<{ data: SheetImportResult }>('/attendance/import/commit', fd, {
    headers: { 'Content-Type': 'multipart/form-data' },
  });
};
