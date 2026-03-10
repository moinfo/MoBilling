import api from './axios';

export interface InvoicePaymentInfo {
  invoice: {
    id: string;
    document_number: string;
    date: string;
    due_date: string | null;
    total: number;
    paid_amount: number;
    balance_due: number;
    status: string;
    notes: string | null;
    items: { description: string; quantity: number; unit_price: number; amount: number }[];
    client: { name: string; email: string };
  };
  tenant: {
    name: string;
    currency: string;
    logo_url: string | null;
    pesapal_enabled: boolean;
    bank_name: string | null;
    bank_account_name: string | null;
    bank_account_number: string | null;
    bank_branch: string | null;
    payment_instructions: string | null;
  };
}

export interface CheckoutResponse {
  payment_id: string;
  redirect_url: string;
  order_tracking_id: string;
}

export interface PaymentStatus {
  status: string;
  amount: number;
  confirmation_code: string | null;
  payment_method: string | null;
  completed_at: string | null;
}

export const getInvoiceForPayment = (documentId: string) =>
  api.get<InvoicePaymentInfo>(`/pay/${documentId}`);

export const checkoutInvoice = (documentId: string, amount?: number) =>
  api.post<CheckoutResponse>(`/pay/${documentId}/checkout`, amount ? { amount } : {});

export const getPaymentStatus = (documentId: string, paymentId: string) =>
  api.get<PaymentStatus>(`/pay/${documentId}/status/${paymentId}`);

export const getPaymentStatusByTracking = (trackingId: string) =>
  api.get<PaymentStatus & { document_id: string }>(`/pay/status/by-tracking`, { params: { OrderTrackingId: trackingId } });

// Portal payment (authenticated)
export const portalCheckoutInvoice = (documentId: string, amount?: number) =>
  api.post<CheckoutResponse>(`/portal/documents/${documentId}/pay`, amount ? { amount } : {});
