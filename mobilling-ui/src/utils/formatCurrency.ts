let _tenantCurrency = 'TZS';

export function setTenantCurrency(currency: string) {
  _tenantCurrency = currency || 'TZS';
}

export function getTenantCurrency(): string {
  return _tenantCurrency;
}

export function formatCurrency(amount: number | string, currency?: string): string {
  const cur = currency || _tenantCurrency;
  const num = typeof amount === 'string' ? parseFloat(amount) : amount;
  return `${cur} ${num.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
}
