import api from './axios';

export type ConfigOptionType = 'dropdown' | 'radio' | 'yesno' | 'quantity';

export interface ConfigOptionChoice {
  id?: string;
  label: string;
  price: number;
  sort_order?: number;
}

export interface ConfigOption {
  id?: string;
  name: string;
  option_type: ConfigOptionType;
  unit_price: number | null;
  sort_order?: number;
  choices: ConfigOptionChoice[];
}

export interface ConfigOptionGroup {
  id: string;
  name: string;
  description: string | null;
  is_active: boolean;
  product_service_ids: string[];
  products: { id: string; name: string }[];
  options: ConfigOption[];
}

export interface ConfigOptionGroupFormData {
  name: string;
  description?: string;
  is_active: boolean;
  product_service_ids: string[];
  options: ConfigOption[];
}

export const getConfigOptionGroups = (params?: { search?: string; active_only?: boolean }) =>
  api.get<{ data: ConfigOptionGroup[] }>('/config-option-groups', { params });

export const createConfigOptionGroup = (data: ConfigOptionGroupFormData) =>
  api.post('/config-option-groups', data);

export const updateConfigOptionGroup = (id: string, data: ConfigOptionGroupFormData) =>
  api.put(`/config-option-groups/${id}`, data);

export const deleteConfigOptionGroup = (id: string) =>
  api.delete(`/config-option-groups/${id}`);
