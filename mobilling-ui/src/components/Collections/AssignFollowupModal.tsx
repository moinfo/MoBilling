import { useEffect, useState } from 'react';
import { Modal, Stack, Text, Select, Textarea, Group, Button, Alert } from '@mantine/core';
import { DateInput } from '@mantine/dates';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { notifications } from '@mantine/notifications';
import { createFollowup } from '../../api/followups';
import { getAssignableUsers } from '../../api/users';
import { usePermissions } from '../../hooks/usePermissions';
import { useAuth } from '../../context/AuthContext';
import { formatCurrency } from '../../utils/formatCurrency';
import ApproveCollectionModal from './ApproveCollectionModal';

interface Props {
  opened: boolean;
  onClose: () => void;
  documentId: string;
  documentNumber: string;
  clientName?: string | null;
  balance?: number;
  onDone?: () => void;
}

const startOfToday = () => { const d = new Date(); d.setHours(0, 0, 0, 0); return d; };

/** Assign an invoice to a staff member for follow-up (POST /followups). */
export default function AssignFollowupModal({ opened, onClose, documentId, documentNumber, clientName, balance, onDone }: Props) {
  const qc = useQueryClient();
  const { can } = usePermissions();
  const { user } = useAuth();
  const [staffId, setStaffId] = useState<string | null>(null);
  const [date, setDate] = useState<string | null>(null);
  const [notes, setNotes] = useState('');
  const [needsApproval, setNeedsApproval] = useState(false);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);
  const [approveOpen, setApproveOpen] = useState(false);

  const { data: usersRes } = useQuery({
    queryKey: ['assignable-users'],
    queryFn: getAssignableUsers,
    enabled: opened,
  });
  const staffOptions = (usersRes?.data?.data ?? []).map((u) => ({ value: u.id, label: u.name }));

  useEffect(() => {
    if (opened) {
      setStaffId(user?.id ?? null);
      setDate(null);
      setNotes('');
      setNeedsApproval(false);
      setErrorMsg(null);
    }
  }, [opened, user?.id]);

  const mutation = useMutation({
    mutationFn: () => createFollowup({
      document_id: documentId,
      next_followup: date as string,
      user_id: staffId || undefined,
      notes: notes.trim() || undefined,
    }),
    onSuccess: (res) => {
      notifications.show({ title: 'Assigned', message: res.data.message ?? 'Follow-up scheduled.', color: 'green' });
      qc.invalidateQueries({ queryKey: ['followup-dashboard'] });
      qc.invalidateQueries({ queryKey: ['followups'] });
      qc.invalidateQueries({ queryKey: ['my-followups'] });
      onDone?.();
      onClose();
    },
    onError: (err: any) => {
      const msg: string = err?.response?.data?.message ?? 'Failed to assign follow-up.';
      setErrorMsg(msg);
      setNeedsApproval(err?.response?.status === 422 && /not been reviewed|approve/i.test(msg));
    },
  });

  return (
    <>
      <Modal opened={opened} onClose={onClose} title={`Assign ${documentNumber} to staff`} size="md" centered>
        <Stack>
          <Text size="sm" c="dimmed">
            {clientName ? `${clientName} · ` : ''}{balance !== undefined ? `Balance ${formatCurrency(balance)}` : ''}
          </Text>
          {errorMsg && (
            <Alert color={needsApproval ? 'orange' : 'red'} title={needsApproval ? 'Approval required' : 'Error'}>
              <Stack gap="xs">
                <Text size="sm">{errorMsg}</Text>
                {needsApproval && can('documents.approve_collection') && (
                  <Button size="xs" color="green" variant="light" w="fit-content" onClick={() => setApproveOpen(true)}>
                    Approve for Collection now
                  </Button>
                )}
              </Stack>
            </Alert>
          )}
          <Select label="Assign to" placeholder="Select staff" searchable required
            data={staffOptions} value={staffId} onChange={setStaffId} />
          <DateInput label="Next follow-up date" placeholder="When should the first call happen?" required
            minDate={startOfToday()} value={date} onChange={setDate} />
          <Textarea label="Notes (optional)" minRows={2} maxLength={1000}
            value={notes} onChange={(e) => setNotes(e.currentTarget.value)} />
          <Group justify="flex-end">
            <Button variant="default" onClick={onClose}>Cancel</Button>
            <Button onClick={() => { setErrorMsg(null); setNeedsApproval(false); mutation.mutate(); }}
              loading={mutation.isPending} disabled={!staffId || !date}>
              Assign
            </Button>
          </Group>
        </Stack>
      </Modal>
      <ApproveCollectionModal
        opened={approveOpen}
        onClose={() => setApproveOpen(false)}
        documentId={documentId}
        documentNumber={documentNumber}
        onApproved={() => { setErrorMsg(null); setNeedsApproval(false); onDone?.(); }}
      />
    </>
  );
}
