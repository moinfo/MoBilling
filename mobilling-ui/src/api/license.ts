import api from './axios';

export interface LicenseStatus {
  license_key: string | null;
  status: 'active' | 'inactive';
  expires_at: string | null;
  last_checked_at: string | null;
}

export const getLicenseStatus = () => api.get<{ data: LicenseStatus }>('/license-status');
