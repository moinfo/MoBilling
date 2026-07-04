import api from './axios';

// Attachment + multipart-reply helpers for the client portal. Kept separate
// from portal.ts (the existing JSON-only reply endpoint there still works).

export interface PortalTicketAttachment {
  id: string;
  original_name: string;
  mime: string | null;
  size: number;
  download_url: string;
}

export interface PortalTicketReply {
  id: string;
  author_type: 'staff' | 'client';
  author_name: string;
  message: string;
  created_at: string;
  attachments?: PortalTicketAttachment[];
}

// Reply to a portal ticket, optionally with file attachments (multipart).
export const replyPortalTicketWithFiles = (id: string, message: string, files: File[] = []) => {
  if (files.length === 0) {
    return api.post(`/portal/tickets/${id}/reply`, { message });
  }
  const fd = new FormData();
  fd.append('message', message);
  files.forEach((f) => fd.append('attachments[]', f));
  return api.post(`/portal/tickets/${id}/reply`, fd, {
    headers: { 'Content-Type': 'multipart/form-data' },
  });
};

// Streams an attachment through the authenticated endpoint and triggers a download.
export const downloadPortalTicketAttachment = async (att: PortalTicketAttachment) => {
  const res = await api.get(att.download_url, { responseType: 'blob' });
  const url = window.URL.createObjectURL(new Blob([res.data], { type: att.mime || 'application/octet-stream' }));
  const link = document.createElement('a');
  link.href = url;
  link.setAttribute('download', att.original_name);
  document.body.appendChild(link);
  link.click();
  link.remove();
  window.URL.revokeObjectURL(url);
};
