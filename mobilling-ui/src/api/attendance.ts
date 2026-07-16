import api from './axios';

export interface AttendanceDay {
  id?: string;
  date: string;
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
  settings: { check_in_time: string; check_out_time: string; penalties_enabled: boolean };
  today: AttendanceDay | null;
  month_label: string;
  present_days: number;
  month_records: AttendanceDay[];
  deduction_total: number;
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

export const recordAttendance = (payload: { user_id: string; date: string; check_in?: string | null; check_out?: string | null }) =>
  api.post<{ data: AttendanceRow }>('/attendance/record', payload);

export const getAttendanceSettings = () => api.get<{ data: AttendanceSettings }>('/attendance/settings');
export const updateAttendanceSettings = (data: AttendanceSettings) =>
  api.put<{ data: AttendanceSettings }>('/attendance/settings', data);
