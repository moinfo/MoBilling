import api from './axios';

export interface LicenseStatus {
  license_key: string | null;
  status: 'active' | 'inactive';
  expires_at: string | null;
  last_checked_at: string | null;
  app_version: string | null;
}

export interface LatestRelease {
  version: string;
  changelog: string | null;
  download_url: string | null;
  released_at: string;
}

export const getLicenseStatus = () => api.get<{ data: LicenseStatus }>('/license-status');
export const getLatestRelease = () => api.get<{ data: LatestRelease | null }>('/releases/latest');
