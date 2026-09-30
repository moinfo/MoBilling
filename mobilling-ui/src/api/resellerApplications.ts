import api from './axios';
import { ResellerApplicationCategory } from './reseller';

export interface ResellerApplicationStaffRecord {
  id: string;
  requested_domain: string;
  brand_name: string;
  categories: ResellerApplicationCategory[];
  contact_name: string;
  contact_email: string;
  contact_phone: string | null;
  status: 'pending' | 'approved' | 'rejected' | 'provisioned';
  staff_note: string | null;
  decided_at: string | null;
  created_at: string;
  client?: { id: string; name: string; email: string | null; phone: string | null };
  decided_by?: { id: string; name: string } | null;
  provisioned_tenant?: { id: string; name: string; custom_domain: string | null } | null;
}

export const listResellerApplications = (params: { status?: string; page?: number } = {}) =>
  api.get<{ data: ResellerApplicationStaffRecord[]; current_page: number; last_page: number; total: number }>(
    '/reseller-applications', { params }
  );

export const getResellerApplicationDetail = (id: string) =>
  api.get<{ data: ResellerApplicationStaffRecord }>(`/reseller-applications/${id}`);

export const approveResellerApplication = (id: string, staff_note?: string) =>
  api.post<{ data: ResellerApplicationStaffRecord; message: string }>(`/reseller-applications/${id}/approve`, { staff_note });

export const rejectResellerApplication = (id: string, staff_note: string) =>
  api.post<{ data: ResellerApplicationStaffRecord; message: string }>(`/reseller-applications/${id}/reject`, { staff_note });

export interface ProvisionPreview {
  categories: ResellerApplicationCategory[];
  products: { category: string; name: string; retail_price: number; cost_price: number | null; cost_flagged: boolean }[];
  infra: { category: string; label: string }[];
  warnings: string[];
}

export const previewResellerProvision = (id: string) =>
  api.get<{ data: ProvisionPreview }>(`/reseller-applications/${id}/provision`);

export const provisionResellerApplication = (id: string, admin_password?: string) =>
  api.post<{ data: { tenant_id: string; tenant_name: string; custom_domain: string; admin_email: string }; message: string }>(
    `/reseller-applications/${id}/provision`, { admin_password }
  );
