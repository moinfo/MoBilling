import api from './axios';

export interface WorkLocation {
  id: string;
  name: string;
  latitude: number;
  longitude: number;
  radius_meters: number;
  is_active: boolean;
  staff_count?: number;
  created_at: string;
}

export interface WorkLocationPayload {
  name: string;
  latitude: number;
  longitude: number;
  radius_meters?: number;
  is_active?: boolean;
}

export const getWorkLocations = (params?: { search?: string; page?: number; per_page?: number }) =>
  api.get('/work-locations', { params });

export const createWorkLocation = (data: WorkLocationPayload) =>
  api.post('/work-locations', data);

export const updateWorkLocation = (id: string, data: WorkLocationPayload) =>
  api.put(`/work-locations/${id}`, data);

export const deleteWorkLocation = (id: string) =>
  api.delete(`/work-locations/${id}`);

export interface StaffWorkLocation {
  id: string;
  name: string;
  work_location: { id: string; name: string } | null;
}

export const getWorkLocationStaffAssignments = () =>
  api.get<{ data: StaffWorkLocation[] }>('/work-locations-staff');

export const assignStaffWorkLocation = (userId: string, workLocationId: string | null) =>
  api.put<{ data: StaffWorkLocation }>(`/work-locations-staff/${userId}`, { work_location_id: workLocationId });
