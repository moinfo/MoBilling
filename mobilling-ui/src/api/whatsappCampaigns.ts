import api from './axios';

export interface WhatsappCampaign {
  id: string;
  name: string;
  start_date: string;
  end_date: string | null;
  budget: number;
  notes: string | null;
  leads_count: number;
  converted_count: number;
  created_at: string;
}

export const getCampaigns = () =>
  api.get<WhatsappCampaign[]>('/whatsapp-campaigns');

export const createCampaign = (data: Partial<WhatsappCampaign>) =>
  api.post<WhatsappCampaign>('/whatsapp-campaigns', data);

export const updateCampaign = (id: string, data: Partial<WhatsappCampaign>) =>
  api.put<WhatsappCampaign>(`/whatsapp-campaigns/${id}`, data);

export const deleteCampaign = (id: string) =>
  api.delete(`/whatsapp-campaigns/${id}`);
