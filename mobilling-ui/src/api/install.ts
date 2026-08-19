import api from './axios';

export interface InstallRequirements {
  php_version: string;
  php_ok: boolean;
  extensions: { name: string; loaded: boolean }[];
  writable: { path: string; writable: boolean }[];
  env_writable: boolean;
  all_ok: boolean;
}

export interface DatabaseFormData {
  host: string;
  port: number | string;
  database: string;
  username: string;
  password?: string;
}

export interface TenantFormData {
  license_key: string;
  company_name: string;
  company_email: string;
  currency?: string;
  admin_name: string;
  admin_email: string;
  admin_password: string;
  license_agreement_accepted: boolean;
}

export interface LicenseAgreement {
  version: string;
  effective_date: string;
  content: string;
}

export const getInstallStatus = () => api.get<{ installed: boolean }>('/install/status');
export const getInstallRequirements = () => api.get<InstallRequirements>('/install/requirements');
export const testInstallDatabase = (data: DatabaseFormData) => api.post<{ message: string }>('/install/database', data);
export const runInstallMigrations = () => api.post<{ message: string }>('/install/migrate');
export const checkInstallLicense = (license_key: string) =>
  api.post<{ data: { valid: boolean; product: string; expires_at: string | null } }>('/install/license', { license_key });
export const createInstallTenant = (data: TenantFormData) =>
  api.post<{ message: string; data: { tenant_id: string; admin_email: string } }>('/install/tenant', data);
export const getLicenseAgreement = () => api.get<{ data: LicenseAgreement }>('/license-agreement');
