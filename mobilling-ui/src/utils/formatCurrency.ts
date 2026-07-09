let _tenantCurrency = 'TZS';

export function setTenantCurrency(currency: string) {
  _tenantCurrency = currency || 'TZS';
}

export function getTenantCurrency(): string {
  return _tenantCurrency;
}

export function formatCurrency(amount: number | string | null | undefined, currency?: string): string {
  const cur = currency || _tenantCurrency;
  const parsed = typeof amount === 'string' ? parseFloat(amount) : amount;
  // Never throw on null/undefined/NaN (e.g. permission-withheld dashboard fields).
  const num = Number.isFinite(parsed as number) ? (parsed as number) : 0;
  return `${cur} ${num.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
}
