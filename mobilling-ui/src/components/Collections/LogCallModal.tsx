import { useEffect, useState } from 'react';
import { Modal, Group, Text, Stack, Paper, Select, Textarea, NumberInput, Button } from '@mantine/core';
import { DateInput } from '@mantine/dates';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { notifications } from '@mantine/notifications';
import { IconPhoneCall, IconCheck } from '@tabler/icons-react';
import { logCall, FollowupEntry } from '../../api/followups';
import { formatCurrency } from '../../utils/formatCurrency';

// Backend validates promise_date / next_followup_override as `after:today`.
const startOfTomorrow = () => {
  const d = new Date();
  d.setHours(0, 0, 0, 0);
  d.setDate(d.getDate() + 1);
  return d;
};

interface Props {
  followup: FollowupEntry | null;
  onClose: () => void;
  onLogged?: () => void;
}

/** Log a collection call against a follow-up (rules mirror FollowupController::logCall). */
export default function LogCallModal({ followup, onClose, onLogged }: Props) {
  const qc = useQueryClient();
  const [outcome, setOutcome] = useState<string>('');
  const [notes, setNotes] = useState('');
  const [promiseDate, setPromiseDate] = useState<string | null>(null);
  const [promiseAmount, setPromiseAmount] = useState<number | undefined>(undefined);
  const [nextOverride, setNextOverride] = useState<string | null>(null);

  useEffect(() => {
    if (followup) {
      setOutcome(''); setNotes(''); setPromiseDate(null); setPromiseAmount(undefined); setNextOverride(null);
    }
  }, [followup]);

  const mutation = useMutation({
    mutationFn: (data: Parameters<typeof logCall>[1]) => logCall(followup!.id, data),
    onSuccess: (res) => {
      notifications.show({
        title: 'Call Logged',
        message: res.data.message,
        color: res.data.escalated ? 'orange' : 'green',
      });
      qc.invalidateQueries({ queryKey: ['followup-dashboard'] });
      qc.invalidateQueries({ queryKey: ['followups'] });
      qc.invalidateQueries({ queryKey: ['my-followups'] });
      qc.invalidateQueries({ queryKey: ['collection-dashboard'] });
      onLogged?.();
      onClose();
    },
    onError: (err: any) => {
      notifications.show({
        title: 'Error',
        message: err?.response?.data?.message ?? 'Failed to log call.',
        color: 'red',
      });
    },
  });

  const handleOutcomeChange = (v: string) => {
    setOutcome(v);
    if (v !== 'promised' && v !== 'partial_payment') {
      setPromiseDate(null);
      setPromiseAmount(undefined);
    }
  };

  // Mirror the backend required_if rules: a promise needs a date + amount; a partial payment needs an amount.
  const promiseDetailsMissing =
    (outcome === 'promised' && (!promiseDate || !promiseAmount)) ||
    (outcome === 'partial_payment' && !promiseAmount);

  const handleLogCall = () => {
    if (!followup || !outcome || !notes) return;
    if (promiseDetailsMissing) {
      notifications.show({
        title: 'Missing details',
        message: outcome === 'promised'
          ? 'Enter the promise date and amount for a "Promised to Pay" outcome.'
          : 'Enter the partial payment amount.',
        color: 'red',
      });
      return;
    }
    mutation.mutate({
      outcome,
      notes,
      promise_date: promiseDate || undefined,
      promise_amount: promiseAmount,
      next_followup_override: nextOverride || undefined,
    });
  };

  return (
    <Modal
      opened={!!followup}
      onClose={onClose}
      title={
        <Group gap="sm">
          <IconPhoneCall size={20} />
          <Text fw={600}>Log Call</Text>
        </Group>
      }
      size="lg"
    >
      {followup && (
        <Stack gap="md">
          <Paper p="sm" radius="sm" bg="var(--mantine-color-default)">
            <Group justify="space-between">
              <div>
                <Text size="xs" c="dimmed">Client</Text>
                <Text fw={600} tt="uppercase">{followup.client_name}</Text>
              </div>
              <div>
                <Text size="xs" c="dimmed">Phone</Text>
                <Text fw={600}>{followup.client_phone || 'No phone'}</Text>
              </div>
              <div>
                <Text size="xs" c="dimmed">Invoice</Text>
                <Text fw={600}>{followup.document_number}</Text>
              </div>
              <div>
                <Text size="xs" c="dimmed">Balance</Text>
                <Text fw={700} c="red">{formatCurrency(followup.invoice_balance)}</Text>
              </div>
            </Group>
          </Paper>

          <Select
            label="Call Outcome"
            placeholder="What happened?"
            required
            value={outcome}
            onChange={(v) => handleOutcomeChange(v || '')}
            data={[
              { value: 'promised', label: 'Promised to Pay' },
              { value: 'no_answer', label: 'No Answer' },
              { value: 'declined', label: 'Declined / Refused' },
              { value: 'disputed', label: 'Disputed Invoice' },
              { value: 'partial_payment', label: 'Will Make Partial Payment' },
            ]}
          />

          <Textarea
            label="Call Notes"
            placeholder="What did the client say? Record the conversation details..."
            required
            minRows={3}
            value={notes}
            onChange={(e) => setNotes(e.currentTarget.value)}
          />

          {(outcome === 'promised' || outcome === 'partial_payment') && (
            <Group grow>
              <DateInput
                label="Promise Date"
                placeholder="When will they pay?"
                required={outcome === 'promised'}
                value={promiseDate}
                onChange={setPromiseDate}
                minDate={startOfTomorrow()}
              />
              <NumberInput
                label="Promise Amount"
                placeholder="How much?"
                required
                value={promiseAmount}
                onChange={(v) => setPromiseAmount(v as number)}
                min={0.01}
                decimalScale={2}
              />
            </Group>
          )}

          <DateInput
            label="Override Next Follow-up Date (optional)"
            description="Leave blank to use auto-scheduling rules"
            placeholder="Custom date"
            value={nextOverride}
            onChange={setNextOverride}
            minDate={startOfTomorrow()}
            clearable
          />

          <Group justify="flex-end" mt="sm">
            <Button variant="default" onClick={onClose}>Cancel</Button>
            <Button
              color="green"
              leftSection={<IconCheck size={16} />}
              onClick={handleLogCall}
              loading={mutation.isPending}
              disabled={!outcome || !notes || promiseDetailsMissing}
            >
              Log Call
            </Button>
          </Group>
        </Stack>
      )}
    </Modal>
  );
}
