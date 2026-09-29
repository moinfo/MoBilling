import { useEffect, useState } from 'react';
import { Modal, Stack, Text, Group, Alert, Button, Center, Loader, Select, Textarea, Paper } from '@mantine/core';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { notifications } from '@mantine/notifications';
import { IconPhoneCall, IconExchange } from '@tabler/icons-react';
import { createFollowup, reassignFollowup, FollowupEntry, FollowupSummary } from '../../api/followups';
import { getAssignableUsers } from '../../api/users';
import { Document } from '../../api/documents';
import { usePermissions } from '../../hooks/usePermissions';
import LogCallForm from '../Collections/LogCallForm';
import ClientFollowupHistory from '../Collections/ClientFollowupHistory';
import ApproveCollectionModal from '../Collections/ApproveCollectionModal';

interface Props {
  opened: boolean;
  onClose: () => void;
  document: Document | null;
  /** The row's current follow-up summary (from the Invoices list), if already known — avoids a refetch. */
  summary?: FollowupSummary | null;
  onLogged?: () => void;
}

/**
 * "Follow-up" flow for an invoice row on the Invoices page: shows the client's recent follow-up
 * history (FollowupController::clientHistory), and reuses LogCallForm to log a call — creating the
 * follow-up first (FollowupController::store) if this invoice doesn't have an active one yet, so it's
 * one click to Follow-up -> log details -> save.
 */
export default function LogFollowupModal({ opened, onClose, document, summary, onLogged }: Props) {
  const qc = useQueryClient();
  const { can } = usePermissions();
  const [followupId, setFollowupId] = useState<string | null | undefined>(undefined);
  const [needsApproval, setNeedsApproval] = useState(false);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);
  const [approveOpen, setApproveOpen] = useState(false);
  const [reassignTo, setReassignTo] = useState<string | null>(null);
  const [reassignNote, setReassignNote] = useState('');

  const { data: usersRes } = useQuery({
    queryKey: ['assignable-users'],
    queryFn: getAssignableUsers,
    enabled: opened && can('documents.approve_collection'),
  });
  const staffOptions = (usersRes?.data?.data ?? []).map((u) => ({ value: u.id, label: u.name }));

  const createMutation = useMutation({
    mutationFn: () => createFollowup({ document_id: document!.id, next_followup: new Date().toISOString().slice(0, 10) }),
    onSuccess: (res) => {
      setFollowupId(res.data.data.id);
      qc.invalidateQueries({ queryKey: ['followup-summary'] });
      qc.invalidateQueries({ queryKey: ['followup-dashboard'] });
      qc.invalidateQueries({ queryKey: ['followups'] });
    },
    onError: (err: any) => {
      const msg: string = err?.response?.data?.message ?? 'Failed to start a follow-up for this invoice.';
      setErrorMsg(msg);
      setNeedsApproval(err?.response?.status === 422 && /not been reviewed|approve/i.test(msg));
    },
  });

  // On open: reuse the row's active follow-up if we already know it, otherwise create one — no extra click.
  useEffect(() => {
    if (!opened || !document) return;
    setErrorMsg(null);
    setNeedsApproval(false);
    setReassignTo(summary?.assigned_user_id ?? null);
    setReassignNote('');
    if (summary?.followup_id) {
      setFollowupId(summary.followup_id);
    } else {
      setFollowupId(null); // null = "resolving"; triggers auto-create below
      createMutation.mutate();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [opened, document?.id]);

  const reassignMutation = useMutation({
    mutationFn: () => reassignFollowup(followupId as string, reassignTo as string, reassignNote.trim() || undefined),
    onSuccess: (res) => {
      notifications.show({ title: 'Reassigned', message: res.data.message, color: 'green' });
      setReassignNote('');
      qc.invalidateQueries({ queryKey: ['followup-summary'] });
      qc.invalidateQueries({ queryKey: ['followup-dashboard'] });
      qc.invalidateQueries({ queryKey: ['followups'] });
    },
    onError: (err: any) => {
      notifications.show({ title: 'Error', message: err?.response?.data?.message ?? 'Failed to reassign.', color: 'red' });
    },
  });

  if (!document) return null;

  // Build the minimal FollowupEntry LogCallForm needs (header display fields) from data we already have.
  const followupEntry: FollowupEntry | null = followupId ? {
    id: followupId,
    document_id: document.id,
    document_number: document.document_number,
    client_id: document.client_id,
    client_name: document.client?.name ?? null,
    client_phone: document.client?.phone ?? null,
    invoice_total: Number(document.total),
    invoice_balance: Number(document.balance_due),
    assigned_to: summary?.assigned_to ?? null,
    user_id: null,
    call_date: null,
    outcome: null,
    notes: null,
    promise_date: null,
    promise_amount: null,
    next_followup: null,
    status: 'pending',
  } : null;

  return (
    <>
      <Modal
        opened={opened}
        onClose={onClose}
        title={
          <Group gap="sm">
            <IconPhoneCall size={20} />
            <Text fw={600}>Follow-up — {document.document_number}</Text>
          </Group>
        }
        size="lg"
      >
        <Stack gap="md">
          {can('documents.approve_collection') && followupId && (
            <Paper withBorder p="sm" radius="sm">
              <Group gap="sm" mb={reassignNote || staffOptions.length ? 6 : 0} wrap="nowrap">
                <IconExchange size={16} style={{ flexShrink: 0 }} />
                <Select
                  size="xs"
                  placeholder="Reassign to..."
                  data={staffOptions}
                  value={reassignTo}
                  onChange={setReassignTo}
                  searchable
                  style={{ flex: 1 }}
                />
                <Button
                  size="xs"
                  variant="light"
                  loading={reassignMutation.isPending}
                  disabled={!reassignTo || reassignTo === summary?.assigned_user_id}
                  onClick={() => reassignMutation.mutate()}
                >
                  Reassign
                </Button>
              </Group>
              <Textarea
                size="xs"
                placeholder="Optional note for the new assignee (e.g. call after 3pm)"
                value={reassignNote}
                onChange={(e) => setReassignNote(e.currentTarget.value)}
                maxLength={1000}
                autosize
                minRows={1}
              />
            </Paper>
          )}

          <ClientFollowupHistory clientId={document.client_id} currentDocumentNumber={document.document_number} />

          {errorMsg ? (
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
          ) : followupEntry ? (
            <LogCallForm
              followup={followupEntry}
              onCancel={onClose}
              onDone={() => { onLogged?.(); onClose(); }}
            />
          ) : (
            <Center py="md"><Loader size="sm" /></Center>
          )}
        </Stack>
      </Modal>
      <ApproveCollectionModal
        opened={approveOpen}
        onClose={() => setApproveOpen(false)}
        documentId={document.id}
        documentNumber={document.document_number}
        onApproved={() => {
          setApproveOpen(false);
          setErrorMsg(null);
          setNeedsApproval(false);
          setFollowupId(null);
          createMutation.mutate();
        }}
      />
    </>
  );
}
