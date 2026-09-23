import { useEffect, useState } from 'react';
import { Modal, Stack, Text, Select, Textarea, Group, Button, Alert, NumberInput, Table, Divider, Anchor } from '@mantine/core';
import { DateInput } from '@mantine/dates';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { notifications } from '@mantine/notifications';
import { createFollowup, bulkAssignFollowups, BulkAssignResult, CommissionType, previewCommission } from '../../api/followups';
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
  /** When set, assigns all these invoices in one go (POST /followups/bulk-assign) instead of the single invoice. */
  bulkDocuments?: { id: string; number: string; balance?: number }[];
  clientName?: string | null;
  balance?: number;
  onDone?: () => void;
}

const startOfToday = () => { const d = new Date(); d.setHours(0, 0, 0, 0); return d; };

/** Assign an invoice to a staff member for follow-up (POST /followups). */
export default function AssignFollowupModal({ opened, onClose, documentId, documentNumber, bulkDocuments, clientName, balance, onDone }: Props) {
  const qc = useQueryClient();
  const { can } = usePermissions();
  const { user } = useAuth();
  const [staffId, setStaffId] = useState<string | null>(null);
  const [date, setDate] = useState<string | null>(null);
  const [notes, setNotes] = useState('');
  const [needsApproval, setNeedsApproval] = useState(false);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);
  const [approveOpen, setApproveOpen] = useState(false);
  const [bulkResult, setBulkResult] = useState<BulkAssignResult | null>(null);
  const isBulk = !!bulkDocuments?.length;
  const [target, setTarget] = useState<number | string>('');
  const [commType, setCommType] = useState<CommissionType>('none');
  const [commValue, setCommValue] = useState<number | string>('');
  const [overrides, setOverrides] = useState<Record<string, number | string>>({});
  const [showOverrides, setShowOverrides] = useState(false);

  const singleBalance = balance ?? 0;
  const numVal = Number(commValue) || 0;
  // Effective targets: single = target field; bulk = override or that invoice's own balance
  const effectiveTargets: { id: string; label: string; balance: number; target: number }[] = isBulk
    ? bulkDocuments!.map((d) => {
      const o = overrides[d.id];
      return { id: d.id, label: d.number, balance: d.balance ?? 0, target: o !== undefined && o !== '' ? Number(o) : (d.balance ?? 0) };
    })
    : [{ id: documentId, label: documentNumber, balance: singleBalance, target: Number(target) || 0 }];
  const targetErrors = effectiveTargets.filter((t) => (isBulk ? t.balance > 0 || overrides[t.id] !== undefined : true)
    && (t.target <= 0 || (t.balance > 0 && t.target > t.balance + 0.005)));
  const commError = commType === 'none' ? null
    : numVal <= 0 ? 'Commission value must be greater than 0.'
      : commType === 'percentage' && numVal > 100 ? 'Percentage cannot exceed 100.' : null;
  const previewTarget = effectiveTargets.reduce((s, t) => s + t.target, 0);
  const previewCommissionTotal = effectiveTargets.reduce((s, t) => s + previewCommission(commType, numVal, t.target, t.target), 0);
  const formInvalid = (!isBulk && balance !== undefined && targetErrors.length > 0) || (isBulk && targetErrors.length > 0) || !!commError;

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
      setBulkResult(null);
      setTarget(balance ?? '');
      setCommType('none');
      setCommValue('');
      setOverrides({});
      setShowOverrides(false);
    }
  }, [opened, user?.id]); // eslint-disable-line react-hooks/exhaustive-deps

  const mutation = useMutation({
    mutationFn: async () => isBulk
      ? bulkAssignFollowups({
        document_ids: bulkDocuments!.map((d) => d.id),
        user_id: staffId as string,
        next_followup: date as string,
        notes: notes.trim() || undefined,
        commission_type: commType,
        commission_value: commType === 'none' ? undefined : numVal,
        targets: Object.fromEntries(Object.entries(overrides).filter(([, v]) => v !== '' && v !== undefined).map(([k, v]) => [k, Number(v)])),
      })
      : createFollowup({
      target_amount: Number(target) > 0 ? Number(target) : undefined,
      commission_type: commType,
      commission_value: commType === 'none' ? undefined : numVal,
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
      qc.invalidateQueries({ queryKey: ['unassigned-invoices'] });
      onDone?.();
      if (isBulk) {
        const result = res.data as BulkAssignResult;
        if (result.skipped?.length) { setBulkResult(result); return; }
      }
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
      <Modal opened={opened} onClose={onClose} title={isBulk ? `Assign ${bulkDocuments!.length} invoices to staff` : `Assign ${documentNumber} to staff`} size="md" centered>
        <Stack>
          {bulkResult && (
            <Alert color="orange" title={bulkResult.message}>
              <Stack gap={4}>
                {bulkResult.skipped.map((s) => (
                  <Text key={s.document_id} size="sm"><b>{s.document_number ?? s.document_id}</b>: {s.reason}</Text>
                ))}
                <Button size="xs" w="fit-content" mt="xs" onClick={onClose}>Close</Button>
              </Stack>
            </Alert>
          )}
          <Text size="sm" c="dimmed">
            {isBulk ? bulkDocuments!.map((d) => d.number).join(', ') : null}
            {!isBulk && clientName ? `${clientName} · ` : ''}{balance !== undefined ? `Balance ${formatCurrency(balance)}` : ''}
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
          <Divider label="Target & commission (Lengo na commission)" labelPosition="left" />
          {isBulk ? (
            <Stack gap={4}>
              <Text size="sm">Total target: <b>{formatCurrency(previewTarget)}</b> <Text span size="xs" c="dimmed">(each invoice's own balance is used unless overridden)</Text></Text>
              <Anchor size="xs" onClick={() => setShowOverrides((v) => !v)}>{showOverrides ? 'Hide' : 'Edit'} per-invoice targets</Anchor>
              {showOverrides && (
                <Table.ScrollContainer minWidth={300} mah={220}>
                  <Table withTableBorder>
                    <Table.Thead><Table.Tr><Table.Th>Invoice</Table.Th><Table.Th>Balance</Table.Th><Table.Th>Target</Table.Th></Table.Tr></Table.Thead>
                    <Table.Tbody>
                      {effectiveTargets.map((t) => (
                        <Table.Tr key={t.id}>
                          <Table.Td>{t.label}</Table.Td>
                          <Table.Td>{formatCurrency(t.balance)}</Table.Td>
                          <Table.Td>
                            <NumberInput size="xs" min={0} max={t.balance || undefined} hideControls thousandSeparator=","
                              placeholder={String(t.balance)} value={overrides[t.id] ?? ''}
                              onChange={(v) => setOverrides((o) => ({ ...o, [t.id]: v }))} />
                          </Table.Td>
                        </Table.Tr>
                      ))}
                    </Table.Tbody>
                  </Table>
                </Table.ScrollContainer>
              )}
            </Stack>
          ) : (
            <NumberInput label="Collection target (amount to collect on this invoice)" min={0} max={balance || undefined}
              thousandSeparator="," value={target} onChange={setTarget}
              error={balance !== undefined && targetErrors.length ? `Must be > 0 and not more than the balance (${formatCurrency(singleBalance)})` : undefined} />
          )}
          {isBulk && targetErrors.length > 0 && (
            <Text size="xs" c="red">Invalid target on: {targetErrors.map((t) => t.label).join(', ')} (must be &gt; 0 and not above the balance).</Text>
          )}
          <Group grow align="flex-start">
            <Select label="Commission" allowDeselect={false} value={commType} onChange={(v) => setCommType((v as CommissionType) || 'none')}
              data={[{ value: 'none', label: 'None' }, { value: 'percentage', label: 'Percentage (%)' }, { value: 'fixed', label: 'Fixed (TZS)' }]} />
            {commType !== 'none' && (
              <NumberInput label={commType === 'percentage' ? 'Percent (%)' : 'Amount (TZS)'} min={0} max={commType === 'percentage' ? 100 : undefined}
                thousandSeparator="," value={commValue} onChange={setCommValue} error={commError ?? undefined} />
            )}
          </Group>
          {commType !== 'none' && !commError && previewTarget > 0 && (
            <Text size="xs" c="teal">
              Ukikusanya {formatCurrency(previewTarget)}: commission = {formatCurrency(previewCommissionTotal)}
              {commType === 'fixed' ? ' (paid only when the full target is collected)' : ' (pro-rata on what is collected, up to the target)'}
            </Text>
          )}
          <Textarea label="Notes (optional)" minRows={2} maxLength={1000}
            value={notes} onChange={(e) => setNotes(e.currentTarget.value)} />
          <Group justify="flex-end">
            <Button variant="default" onClick={onClose}>Cancel</Button>
            <Button onClick={() => { setErrorMsg(null); setNeedsApproval(false); mutation.mutate(); }}
              loading={mutation.isPending} disabled={!staffId || !date || !!bulkResult || formInvalid}>
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
