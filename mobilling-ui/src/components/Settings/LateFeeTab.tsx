import { useEffect } from 'react';
import { Switch, NumberInput, Button, Stack, Text, Alert, Group, Paper, Divider } from '@mantine/core';
import { useForm } from '@mantine/form';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { notifications } from '@mantine/notifications';
import { IconAlertCircle, IconCheck } from '@tabler/icons-react';
import { getLateFeeSettings, updateLateFeeSettings, type LateFeeSettings } from '../../api/settings';

export default function LateFeeTab({ isAdmin }: { isAdmin: boolean }) {
  const queryClient = useQueryClient();

  const { data, isLoading } = useQuery({
    queryKey: ['settings-late-fee'],
    queryFn: getLateFeeSettings,
  });

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

  const mutation = useMutation({
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

  const { late_fee_enabled, late_fee_percent, late_fee_days } = form.values;

  return (
    <Paper withBorder p="md" radius="md">
      <Stack gap="md">
        <div>
          <Text fw={600} size="sm">Late Fee Automation</Text>
          <Text size="xs" c="dimmed" mt={2}>
            When enabled, a late fee line item is automatically added to overdue invoices by the nightly automation.
          </Text>
        </div>

        <Divider />

        <form onSubmit={form.onSubmit((v) => mutation.mutate(v))}>
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
              label="Apply fee after (days)"
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
                <Button type="submit" loading={mutation.isPending} disabled={isLoading}>
                  Save Late Fee Settings
                </Button>
              </Group>
            )}
          </Stack>
        </form>
      </Stack>
    </Paper>
  );
}
