import { useQuery } from '@tanstack/react-query';
import { getPaymentMethods, PaymentMethod } from '../api/settings';

const DEFAULT_METHODS: PaymentMethod[] = [
  { value: 'bank', label: 'Bank Transfer', details: [] },
  { value: 'mpesa', label: 'M-Pesa', details: [] },
  { value: 'cash', label: 'Cash', details: [] },
  { value: 'card', label: 'Card', details: [] },
  { value: 'cheque', label: 'Cheque', details: [] },
];

export function usePaymentMethods() {
  const { data, isLoading } = useQuery({
    queryKey: ['payment-methods'],
    queryFn: getPaymentMethods,
    staleTime: 5 * 60 * 1000, // cache for 5 minutes
  });

  const methods: PaymentMethod[] = data?.data?.data ?? DEFAULT_METHODS;

  // Get details for a specific payment method value
  const getMethodDetails = (value: string) => {
    const method = methods.find((m) => m.value === value);
    return method?.details?.filter((d) => d.value.trim()) || [];
  };

  return { methods, isLoading, getMethodDetails };
}
