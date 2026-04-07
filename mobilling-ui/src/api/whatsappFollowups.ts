import api from './axios';

export type FollowupOutcome =
  | 'answered'
  | 'no_answer'
  | 'callback'
  | 'interested'
  | 'not_interested'
  | 'converted';

export interface WhatsappFollowup {
  id: string;
  whatsapp_contact_id: string;
  user_id: string | null;
  user: { id: string; name: string } | null;
  call_date: string;
  outcome: FollowupOutcome;
  notes: string | null;
  next_followup_date: string | null;
  created_at: string;
}

export const OUTCOME_META: Record<FollowupOutcome, { label: string; color: string }> = {
  answered:      { label: 'Answered',      color: 'green' },
  no_answer:     { label: 'No Answer',     color: 'red' },
  callback:      { label: 'Callback',      color: 'orange' },
  interested:    { label: 'Interested',    color: 'teal' },
  not_interested:{ label: 'Not Interested',color: 'gray' },
  converted:     { label: 'Converted',     color: 'violet' },
};

export const getFollowups = (contactId: string) =>
  api.get<WhatsappFollowup[]>(`/whatsapp-contacts/${contactId}/followups`);

export const createFollowup = (contactId: string, data: Partial<WhatsappFollowup>) =>
  api.post<WhatsappFollowup>(`/whatsapp-contacts/${contactId}/followups`, data);

export const deleteFollowup = (contactId: string, followupId: string) =>
  api.delete(`/whatsapp-contacts/${contactId}/followups/${followupId}`);
