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
