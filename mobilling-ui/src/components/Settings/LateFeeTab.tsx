import { useEffect, useState } from 'react';
import {
  Switch, NumberInput, Button, Stack, Text, Alert, Group, Paper,
  Divider, Modal, Badge,
} from '@mantine/core';
import { useDisclosure } from '@mantine/hooks';
import { useForm } from '@mantine/form';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { notifications } from '@mantine/notifications';
import { IconAlertCircle, IconCheck, IconTrash } from '@tabler/icons-react';
import {
  getLateFeeSettings, updateLateFeeSettings,
  getLateFeeCount, revertLateFees,
  type LateFeeSettings,
} from '../../api/settings';

export default function LateFeeTab({ isAdmin }: { isAdmin: boolean }) {
  const queryClient = useQueryClient();
  const [revertModal, { open: openRevert, close: closeRevert }] = useDisclosure(false);
  const [updateTotals, setUpdateTotals] = useState(true);

  const { data, isLoading } = useQuery({
    queryKey: ['settings-late-fee'],
    queryFn: getLateFeeSettings,
  });

  const { data: countData, refetch: refetchCount } = useQuery({
    queryKey: ['settings-late-fee-count'],
    queryFn: getLateFeeCount,
    enabled: isAdmin,
  });
  const affectedCount = countData?.data?.count ?? 0;

  const form = useForm<LateFeeSettings>({
    initialValues: { late_fee_enabled: false, late_fee_percent: 10, late_fee_days: 1 },
  });

  useEffect(() => {
    const s = data?.data?.data;
    if (s) {
      form.setValues({
        late_fee_enabled: s.late_fee_enabled,
        late_fee_percent: Number(s.late_fee_percent),
        late_fee_days: Number(s.late_fee_days),
      });
      form.resetDirty();
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [data]);

  const saveMutation = useMutation({
    mutationFn: updateLateFeeSettings,
    onSuccess: (res) => {
      queryClient.invalidateQueries({ queryKey: ['settings-late-fee'] });
      form.resetDirty(res.data.data);
      notifications.show({ message: res.data.message, color: 'green', icon: <IconCheck size={16} /> });
    },
    onError: () => {
      notifications.show({ message: 'Failed to save late fee settings.', color: 'red' });
    },
  });

  const revertMutation = useMutation({
    mutationFn: revertLateFees,
    onSuccess: (res) => {
      closeRevert();
      refetchCount();
      notifications.show({ message: res.data.message, color: 'green', icon: <IconCheck size={16} /> });
    },
    onError: () => {
      notifications.show({ message: 'Failed to remove late fees.', color: 'red' });
    },
  });

  const { late_fee_enabled, late_fee_percent, late_fee_days } = form.values;

  return (
    <>
      <Paper withBorder p="md" radius="md">
        <Stack gap="md">
          <div>
            <Text fw={600} size="sm">Late Fee Automation</Text>
            <Text size="xs" c="dimmed" mt={2}>
              When enabled, a late fee line item is automatically added to overdue invoices by the nightly automation.
            </Text>
          </div>

          <Divider />

          <form onSubmit={form.onSubmit((v) => saveMutation.mutate(v))}>
            <Stack gap="lg">
              <Switch
                label="Enable late fees"
                description="Automatically charge a fee on unpaid invoices past their due date"
                disabled={!isAdmin}
                {...form.getInputProps('late_fee_enabled', { type: 'checkbox' })}
              />

              <NumberInput
                label="Late fee percentage (%)"
                description="Percentage of invoice total charged as the late fee"
                placeholder="10"
                min={0.01}
                max={100}
                decimalScale={2}
                suffix="%"
                disabled={!isAdmin || !late_fee_enabled}
                {...form.getInputProps('late_fee_percent')}
              />

              <NumberInput
                label="Apply fee after (days overdue)"
                description="Number of days past due date before the late fee is applied"
                placeholder="1"
                min={1}
                max={365}
                suffix=" days"
                disabled={!isAdmin || !late_fee_enabled}
                {...form.getInputProps('late_fee_days')}
              />

              {late_fee_enabled && (
                <Alert icon={<IconAlertCircle size={16} />} color="orange" variant="light">
                  A <strong>{late_fee_percent}%</strong> late fee will be added to any unpaid invoice that is{' '}
                  <strong>{late_fee_days} {late_fee_days === 1 ? 'day' : 'days'}</strong> or more past its due date.
                  The fee appears as a separate line item on the invoice.
                </Alert>
              )}

              {isAdmin && (
                <Group justify="flex-end">
                  <Button type="submit" loading={saveMutation.isPending} disabled={isLoading}>
                    Save Late Fee Settings
                  </Button>
                </Group>
              )}
            </Stack>
          </form>

          {isAdmin && (
            <>
              <Divider label="Existing Late Fees" labelPosition="left" />

              <Stack gap="xs">
                <Group justify="space-between" align="center">
                  <div>
                    <Text size="sm" fw={500}>Remove late fees from invoices</Text>
                    <Text size="xs" c="dimmed">
                      Remove late fee line items from unpaid invoices (sent, overdue, partial). Paid and cancelled invoices are skipped.
                    </Text>
                  </div>
                  <Badge color={affectedCount > 0 ? 'orange' : 'gray'} variant="light" size="lg">
                    {affectedCount} invoice{affectedCount !== 1 ? 's' : ''} affected
                  </Badge>
                </Group>

                <Group justify="flex-end">
                  <Button
                    color="red"
                    variant="light"
                    leftSection={<IconTrash size={16} />}
                    disabled={affectedCount === 0}
                    onClick={openRevert}
                  >
                    Remove Late Fees
                  </Button>
                </Group>
              </Stack>
            </>
          )}
        </Stack>
      </Paper>

      <Modal
        opened={revertModal}
        onClose={closeRevert}
        title="Remove Late Fees from Invoices"
        centered
      >
        <Stack gap="md">
          <Text size="sm">
            This will remove the late fee line item from{' '}
            <strong>{affectedCount} unpaid invoice{affectedCount !== 1 ? 's' : ''}</strong> (status: sent, overdue, or partial) and reset their overdue escalation stage.
            Paid and cancelled invoices are not affected.
          </Text>

          <Alert icon={<IconAlertCircle size={16} />} color="orange" variant="light">
            This action cannot be undone. Late fees will be re-applied by the next nightly automation run if late fees are still enabled.
          </Alert>

          <Switch
            label="Update invoice totals"
            description="Deduct the late fee amount from each invoice's subtotal and total. If off, the line item is removed but the charged amount stays."
            checked={updateTotals}
            onChange={(e) => setUpdateTotals(e.currentTarget.checked)}
          />

          <Group justify="flex-end" mt="sm">
            <Button variant="default" onClick={closeRevert} disabled={revertMutation.isPending}>
              Cancel
            </Button>
            <Button
              color="red"
              loading={revertMutation.isPending}
              onClick={() => revertMutation.mutate({ update_totals: updateTotals })}
            >
              Remove Late Fees
            </Button>
          </Group>
        </Stack>
      </Modal>
    </>
  );
}
