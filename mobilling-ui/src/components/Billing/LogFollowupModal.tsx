import { useEffect, useState } from 'react';
import { Modal, Stack, Text, Group, Paper, Badge, Alert, Button, Divider, Center, Loader, ScrollArea } from '@mantine/core';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { IconPhoneCall } from '@tabler/icons-react';
import { createFollowup, getClientFollowups, FollowupEntry, FollowupSummary } from '../../api/followups';
import { Document } from '../../api/documents';
import { usePermissions } from '../../hooks/usePermissions';
import { formatDate } from '../../utils/formatDate';
import { outcomeColors, outcomeLabels, statusColors } from '../../utils/followupColors';
import LogCallForm from '../Collections/LogCallForm';
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

  const { data: historyRes, isLoading: historyLoading } = useQuery({
    queryKey: ['client-followups', document?.client_id],
    queryFn: () => getClientFollowups(document!.client_id),
    enabled: opened && !!document?.client_id,
  });
  const history = historyRes?.data?.data ?? [];

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
    if (summary?.followup_id) {
      setFollowupId(summary.followup_id);
    } else {
      setFollowupId(null); // null = "resolving"; triggers auto-create below
      createMutation.mutate();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [opened, document?.id]);

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
          {history.length > 0 && (
            <Paper withBorder p="sm" radius="sm">
              <Text size="xs" fw={600} c="dimmed" tt="uppercase" mb="xs">Previous follow-ups for this client</Text>
              <ScrollArea.Autosize mah={180}>
                <Stack gap={6}>
                  {history.map((h) => (
                    <Group key={h.id} justify="space-between" wrap="nowrap" gap="xs"
                      opacity={h.document_number === document.document_number ? 1 : 0.65}>
                      <div style={{ minWidth: 0 }}>
                        <Group gap={6}>
                          <Text size="xs" c="dimmed">{h.call_date ? formatDate(h.call_date) : (h.created_at ? formatDate(h.created_at) : '—')}</Text>
                          <Text size="xs" fw={500}>{h.document_number}</Text>
                          {h.outcome && (
                            <Badge color={outcomeColors[h.outcome] || 'gray'} size="xs" variant="light">
                              {outcomeLabels[h.outcome] || h.outcome}
                            </Badge>
                          )}
                          <Badge color={statusColors[h.status] || 'gray'} size="xs">{h.status}</Badge>
                        </Group>
                        {h.notes && <Text size="xs" c="dimmed" truncate>{h.notes}</Text>}
                      </div>
                      <Text size="xs" c="dimmed" style={{ whiteSpace: 'nowrap' }}>{h.assigned_to || '—'}</Text>
                    </Group>
                  ))}
                </Stack>
              </ScrollArea.Autosize>
              <Divider mt="sm" />
            </Paper>
          )}
          {historyLoading && !history.length && (
            <Center py="xs"><Loader size="xs" /></Center>
          )}

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
