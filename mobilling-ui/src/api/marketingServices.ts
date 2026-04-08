import api from './axios';

export interface MarketingService {
  id: string;
  name: string;
  sort_order: number;
  created_at: string;
}

export const getServices = () =>
  api.get<MarketingService[]>('/marketing-services');

export const createService = (name: string) =>
  api.post<MarketingService>('/marketing-services', { name });

export const updateService = (id: string, name: string) =>
  api.put<MarketingService>(`/marketing-services/${id}`, { name });

export const deleteService = (id: string) =>
  api.delete(`/marketing-services/${id}`);

export const reorderServices = (ids: string[]) =>
  api.post('/marketing-services/reorder', { ids });
