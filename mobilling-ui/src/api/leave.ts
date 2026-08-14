import api from './axios';

export interface LeaveType {
  id: string;
  name: string;
  days_per_year: number;
  is_paid: boolean;
  is_active: boolean;
  color: string | null;
}

export interface LeaveTypeFormData {
  name: string;
  days_per_year: number;
  is_paid?: boolean;
  is_active?: boolean;
  color?: string;
}

export interface LeaveBalance {
  id: string;
  user_id: string;
  leave_type_id: string;
  year: number;
  allocated_days: number;
  leave_type?: LeaveType;
}

export interface MyLeaveBalanceRow {
  leave_type: LeaveType;
  allocated_days: number;
  used_days: number;
  remaining_days: number;
}

export interface LeaveRequest {
  id: string;
  user_id: string;
  leave_type_id: string;
  start_date: string;
  end_date: string;
  days: number;
  reason: string | null;
  status: 'pending' | 'approved' | 'rejected' | 'cancelled';
  reviewed_by: string | null;
  reviewed_at: string | null;
  review_note: string | null;
  created_at: string;
  user?: { id: string; name: string };
  leave_type?: LeaveType;
  reviewer?: { id: string; name: string } | null;
}

export const getLeaveTypes = () =>
  api.get<{ data: LeaveType[] }>('/leave-types');

export const createLeaveType = (data: LeaveTypeFormData) =>
  api.post<{ data: LeaveType }>('/leave-types', data);

export const updateLeaveType = (id: string, data: LeaveTypeFormData) =>
  api.put<{ data: LeaveType }>(`/leave-types/${id}`, data);

export const deleteLeaveType = (id: string) =>
  api.delete(`/leave-types/${id}`);

export const getLeaveBalances = (year?: number) =>
  api.get<{ data: { year: number; users: { id: string; name: string }[]; balances: LeaveBalance[] } }>('/leave-balances', { params: { year } });

export const setLeaveBalance = (data: { user_id: string; leave_type_id: string; year: number; allocated_days: number }) =>
  api.post<{ data: LeaveBalance }>('/leave-balances', data);

export const getLeaveRequests = (params?: { status?: string; user_id?: string }) =>
  api.get<{ data: LeaveRequest[] }>('/leave-requests', { params });

export const createLeaveRequest = (data: { leave_type_id: string; start_date: string; end_date: string; reason?: string }) =>
  api.post<{ data: LeaveRequest }>('/leave-requests', data);

export const cancelLeaveRequest = (id: string) =>
  api.post<{ data: LeaveRequest }>(`/leave-requests/${id}/cancel`);

export const reviewLeaveRequest = (id: string, decision: 'approved' | 'rejected', reviewNote?: string) =>
  api.post<{ data: LeaveRequest }>(`/leave-requests/${id}/review`, { decision, review_note: reviewNote });

export const getMyLeaveBalance = (year?: number) =>
  api.get<{ data: MyLeaveBalanceRow[] }>('/leave-requests/my-balance', { params: { year } });
