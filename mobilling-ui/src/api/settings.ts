import api from './axios';
import { User } from './auth';

export interface CompanyData {
  name: string;
  email: string;
  phone?: string | null;
  address?: string | null;
  tax_id?: string | null;
  currency: string;
  website?: string | null;
  bank_name?: string | null;
  bank_account_name?: string | null;
  bank_account_number?: string | null;
  bank_branch?: string | null;
  payment_instructions?: string | null;
}

export interface ProfileData {
  name: string;
  email: string;
  phone?: string | null;
  current_password?: string;
  password?: string;
  password_confirmation?: string;
}

export const updateCompany = (data: CompanyData) =>
  api.put<{ tenant: User['tenant'] }>('/settings/company', data);

export const updateProfile = (data: ProfileData) =>
  api.put<{ user: User }>('/settings/profile', data);

export const uploadLogo = (file: File) => {
  const formData = new FormData();
  formData.append('logo', file);
  return api.post<{ logo_url: string; message: string }>('/settings/logo', formData, {
    headers: { 'Content-Type': 'multipart/form-data' },
  });
};

// --- Email Settings ---

export interface EmailSettings {
  email_enabled: boolean;
  smtp_host: string | null;
  smtp_port: number | null;
  smtp_username: string | null;
  smtp_encryption: string | null;
  smtp_from_email: string | null;
  smtp_from_name: string | null;
  has_password: boolean;
}

export interface EmailSettingsFormData {
  smtp_host: string;
  smtp_port: number | string;
  smtp_username: string;
  smtp_password: string;
  smtp_encryption: string;
  smtp_from_email: string;
  smtp_from_name: string;
}

export const getEmailSettings = () =>
  api.get<{ data: EmailSettings }>('/settings/email');

export const updateEmailSettings = (data: Partial<EmailSettingsFormData>) =>
  api.put<{ data: EmailSettings }>('/settings/email', data);

export const testEmailSettings = () =>
  api.post<{ message: string }>('/settings/email/test');

// --- Reminder Settings (switches only) ---

export interface ReminderSettings {
  reminder_sms_enabled: boolean;
  reminder_email_enabled: boolean;
}

export const getReminderSettings = () =>
  api.get<{ data: ReminderSettings }>('/settings/reminders');

export const updateReminderSettings = (data: ReminderSettings) =>
  api.put<{ data: ReminderSettings; message: string }>('/settings/reminders', data);

// --- Template Settings ---

export interface TemplateSettings {
  reminder_email_subject: string | null;
  reminder_email_body: string | null;
  overdue_email_subject: string | null;
  overdue_email_body: string | null;
  reminder_sms_body: string | null;
  overdue_sms_body: string | null;
  invoice_email_subject: string | null;
  invoice_email_body: string | null;
  email_footer_text: string | null;
}

export const getTemplates = () =>
  api.get<{ data: TemplateSettings }>('/settings/templates');

export const updateTemplates = (data: Partial<TemplateSettings>) =>
  api.put<{ data: TemplateSettings; message: string }>('/settings/templates', data);
