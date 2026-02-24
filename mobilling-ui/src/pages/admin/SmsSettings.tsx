import { useState } from 'react';
import {
  Title, Table, Badge, ActionIcon, Modal, Stack, TextInput, Switch,
  Button, Group, Text, Loader, Center, Paper, NumberInput, PasswordInput,
} from '@mantine/core';
import { useForm } from '@mantine/form';
import { useDebouncedValue } from '@mantine/hooks';
import { notifications } from '@mantine/notifications';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { IconSettings, IconSearch } from '@tabler/icons-react';
import {
  getTenants, getTenantSmsSettings, updateTenantSmsSettings,
  rechargeTenantSms, deductTenantSms,
  Tenant, SmsSettings as SmsSettingsType, SmsSettingsFormData,
} from '../../api/admin';

export default function SmsSettings() {
  const queryClient = useQueryClient();
  const [search, setSearch] = useState('');
  const [debouncedSearch] = useDebouncedValue(search, 300);
  const [selectedTenant, setSelectedTenant] = useState<Tenant | null>(null);

  const { data, isLoading } = useQuery({
    queryKey: ['admin-tenants-sms', debouncedSearch],
    queryFn: () => getTenants({ search: debouncedSearch || undefined, per_page: 100 }),
  });

  const tenants: Tenant[] = data?.data?.data || [];

  return (
    <>
      <Title order={2} mb="md">SMS Settings</Title>
      <Text c="dimmed" mb="lg">Configure SMS gateway credentials and manage SMS credits per tenant.</Text>

      <TextInput
        placeholder="Search tenants..."
        leftSection={<IconSearch size={16} />}
        value={search}
        onChange={(e) => setSearch(e.currentTarget.value)}
        mb="md"
        w={300}
      />

      {isLoading ? (
        <Center py="xl"><Loader /></Center>
      ) : (
        <Paper withBorder>
          <Table striped highlightOnHover>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Tenant</Table.Th>
                <Table.Th>Email</Table.Th>
                <Table.Th>SMS Status</Table.Th>
                <Table.Th>Gateway Email</Table.Th>
                <Table.Th w={80}>Configure</Table.Th>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {tenants.map((tenant) => (
                <Table.Tr key={tenant.id}>
                  <Table.Td fw={500}>{tenant.name}</Table.Td>
                  <Table.Td>{tenant.email}</Table.Td>
                  <Table.Td>
                    <Badge color={(tenant as any).sms_enabled ? 'green' : 'gray'} variant="light">
                      {(tenant as any).sms_enabled ? 'Enabled' : 'Disabled'}
                    </Badge>
                  </Table.Td>
                  <Table.Td c="dimmed">{(tenant as any).gateway_email || '—'}</Table.Td>
                  <Table.Td>
                    <ActionIcon variant="subtle" onClick={() => setSelectedTenant(tenant)}>
                      <IconSettings size={18} />
                    </ActionIcon>
                  </Table.Td>
                </Table.Tr>
              ))}
              {tenants.length === 0 && (
                <Table.Tr>
                  <Table.Td colSpan={5}>
                    <Text ta="center" c="dimmed" py="md">No tenants found</Text>
                  </Table.Td>
                </Table.Tr>
              )}
            </Table.Tbody>
          </Table>
        </Paper>
      )}

      <Modal
        opened={!!selectedTenant}
        onClose={() => setSelectedTenant(null)}
        title={`SMS Settings — ${selectedTenant?.name}`}
        size="lg"
      >
        {selectedTenant && (
          <SmsConfigForm
            tenantId={selectedTenant.id}
            onSaved={() => {
              queryClient.invalidateQueries({ queryKey: ['admin-tenants-sms'] });
              setSelectedTenant(null);
            }}
          />
        )}
      </Modal>
    </>
  );
}

function SmsConfigForm({ tenantId, onSaved }: { tenantId: string; onSaved: () => void }) {
  const queryClient = useQueryClient();
  const [rechargeQty, setRechargeQty] = useState<number | string>(100);
  const [deductQty, setDeductQty] = useState<number | string>(100);

  const { data, isLoading } = useQuery({
    queryKey: ['admin-sms-settings', tenantId],
    queryFn: () => getTenantSmsSettings(tenantId),
  });

  const settings: SmsSettingsType | undefined = data?.data?.data;

  const form = useForm<SmsSettingsFormData>({
    initialValues: {
      sms_enabled: settings?.sms_enabled ?? false,
      gateway_email: settings?.gateway_email ?? '',
      gateway_username: settings?.gateway_username ?? '',
      sender_id: settings?.sender_id ?? '',
      sms_authorization: '',
    },
  });

  const [initialized, setInitialized] = useState(false);
  if (settings && !initialized) {
    form.setValues({
      sms_enabled: settings.sms_enabled,
      gateway_email: settings.gateway_email ?? '',
      gateway_username: settings.gateway_username ?? '',
      sender_id: settings.sender_id ?? '',
      sms_authorization: '',
    });
    setInitialized(true);
  }

  const mutation = useMutation({
    mutationFn: (values: SmsSettingsFormData) => updateTenantSmsSettings(tenantId, values),
    onSuccess: () => {
      notifications.show({ title: 'Success', message: 'SMS settings updated', color: 'green' });
      onSaved();
    },
    onError: (err: any) => {
      notifications.show({
        title: 'Error',
        message: err.response?.data?.message || 'Failed to update SMS settings',
        color: 'red',
      });
    },
  });

  const rechargeMutation = useMutation({
    mutationFn: (qty: number) => rechargeTenantSms(tenantId, qty),
    onSuccess: (res) => {
      notifications.show({ title: 'Success', message: res.data.message, color: 'green' });
      queryClient.invalidateQueries({ queryKey: ['admin-sms-settings', tenantId] });
    },
    onError: (err: any) => {
      notifications.show({
        title: 'Recharge Failed',
        message: err.response?.data?.message || 'Failed to recharge',
        color: 'red',
      });
    },
  });

  const deductMutation = useMutation({
    mutationFn: (qty: number) => deductTenantSms(tenantId, qty),
    onSuccess: (res) => {
      notifications.show({ title: 'Success', message: res.data.message, color: 'green' });
      queryClient.invalidateQueries({ queryKey: ['admin-sms-settings', tenantId] });
    },
    onError: (err: any) => {
      notifications.show({
        title: 'Deduction Failed',
        message: err.response?.data?.message || 'Failed to deduct',
        color: 'red',
      });
    },
  });

  if (isLoading) {
    return <Center py="xl"><Loader /></Center>;
  }

  return (
    <Stack>
      <form onSubmit={form.onSubmit((values) => mutation.mutate(values))}>
        <Stack>
          <Switch
            label="SMS Enabled"
            description="Allow this tenant to send SMS"
            {...form.getInputProps('sms_enabled', { type: 'checkbox' })}
          />

          <TextInput label="Gateway Email" placeholder="tenant@gateway.com" {...form.getInputProps('gateway_email')} />
          <TextInput label="Gateway Username" placeholder="tenant_username" {...form.getInputProps('gateway_username')} />
          <TextInput label="Sender ID" placeholder="MOBILLING" {...form.getInputProps('sender_id')} />
          <PasswordInput
            label="SMS Authorization"
            placeholder={settings?.has_authorization ? '••••••• (unchanged)' : 'Base64 auth token'}
            description="Base64 encoded authorization for the SMS gateway"
            {...form.getInputProps('sms_authorization')}
          />

          <Group justify="flex-end">
            <Button type="submit" loading={mutation.isPending}>Save Settings</Button>
          </Group>
        </Stack>
      </form>

      {settings?.sms_enabled && (
        <Paper withBorder p="md">
          <Text fw={600} mb="sm">SMS Balance & Credits</Text>

          <Group mb="md">
            <Text>Current Balance:</Text>
            {settings.sms_balance !== null && settings.sms_balance !== undefined ? (
              <Badge size="lg" color="blue" variant="light">
                {Number(settings.sms_balance).toLocaleString()} SMS
              </Badge>
            ) : (
              <Text c="dimmed" size="sm">{settings.balance_error || 'Unable to fetch'}</Text>
            )}
          </Group>

          <Group>
            <NumberInput
              label="Recharge"
              value={rechargeQty}
              onChange={setRechargeQty}
              min={1}
              w={120}
            />
            <Button
              mt={24}
              color="green"
              variant="light"
              loading={rechargeMutation.isPending}
              onClick={() => rechargeMutation.mutate(Number(rechargeQty))}
            >
              Recharge
            </Button>
          </Group>

          <Group mt="sm">
            <NumberInput
              label="Deduct"
              value={deductQty}
              onChange={setDeductQty}
              min={1}
              w={120}
            />
            <Button
              mt={24}
              color="red"
              variant="light"
              loading={deductMutation.isPending}
              onClick={() => deductMutation.mutate(Number(deductQty))}
            >
              Deduct
            </Button>
          </Group>
        </Paper>
      )}
    </Stack>
  );
}
