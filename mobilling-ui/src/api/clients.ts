import api from './axios';

export interface Client {
  id: string;
  name: string;
  email: string | null;
  phone: string | null;
  address: string | null;
  tax_id: string | null;
  created_at: string;
}

export interface ClientFormData {
  name: string;
  email: string;
  phone: string;
  address: string;
  tax_id: string;
}

export const getClients = (params?: { search?: string; page?: number; per_page?: number }) =>
  api.get('/clients', { params });

export const getClient = (id: string) =>
  api.get<{ data: Client }>(`/clients/${id}`);

export const createClient = (data: ClientFormData) =>
  api.post('/clients', data);

export const updateClient = (id: string, data: ClientFormData) =>
  api.put(`/clients/${id}`, data);

export const deleteClient = (id: string) =>
  api.delete(`/clients/${id}`);

export interface ClientProfile {
  client: Client;
  summary: {
    total_invoiced: number;
    total_paid: number;
    balance: number;
    active_subscriptions: number;
    total_subscription_value: number;
  };
  subscriptions: {
    id: string;
    product_service_name: string;
    label: string | null;
    billing_cycle: string;
    quantity: number;
    price: string;
    start_date: string;
    status: string;
    next_bill: string | null;
  }[];
  invoices: {
    id: string;
    document_number: string;
    date: string;
    due_date: string | null;
    total: string;
    status: string;
  }[];
  payments: {
    id: string;
    amount: string;
    payment_date: string;
    payment_method: string;
    reference: string | null;
    document_number: string | null;
  }[];
}

export const getClientProfile = (id: string) =>
  api.get<{ data: ClientProfile }>(`/clients/${id}/profile`);
