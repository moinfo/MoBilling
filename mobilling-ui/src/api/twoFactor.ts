import api from './axios';
import { AuthResponse } from './auth';

export interface TwoFactorStatus {
  enabled: boolean;
  recovery_codes_remaining: number | null;
}

export const getTwoFactorStatus = () =>
  api.get<TwoFactorStatus>('/auth/2fa/status');

export const enableTwoFactor = () =>
  api.post<{ data: { secret: string; otpauth_url: string } }>('/auth/2fa/enable');

export const confirmTwoFactor = (code: string) =>
  api.post<{ message: string; recovery_codes: string[] }>('/auth/2fa/confirm', { code });

export const disableTwoFactor = (password: string) =>
  api.post<{ message: string }>('/auth/2fa/disable', { password });

export const regenerateTwoFactorRecoveryCodes = (password: string) =>
  api.post<{ recovery_codes: string[] }>('/auth/2fa/recovery-codes/regenerate', { password });

// Login-time verification (public — no auth header needed/available yet)
export const verifyTwoFactorLogin = (challengeId: string, codeOrRecovery: { code?: string; recovery_code?: string }) =>
  api.post<AuthResponse>('/auth/2fa/verify-login', { challenge_id: challengeId, ...codeOrRecovery });
