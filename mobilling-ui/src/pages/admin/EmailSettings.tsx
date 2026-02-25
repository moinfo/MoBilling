import { useState } from 'react';
import {
  Title, Table, Badge, ActionIcon, Modal, Stack, TextInput, NumberInput,
  Select, Switch, Button, Group, PasswordInput, Text, Loader, Center,
  Paper,
} from '@mantine/core';
import { useForm } from '@mantine/form';
import { useDebouncedValue } from '@mantine/hooks';
import { notifications } from '@mantine/notifications';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { IconSettings, IconSearch } from '@tabler/icons-react';
import {
  getTenants, getTenantEmailSettings, updateTenantEmailSettings, testTenantEmailSettings,
  Tenant, SmtpSettings, SmtpSettingsFormData,
} from '../../api/admin';

export default function EmailSettings() {
  const queryClient = useQueryClient();
  const [search, setSearch] = useState('');
  const [debouncedSearch] = useDebouncedValue(search, 300);
  const [selectedTenant, setSelectedTenant] = useState<Tenant | null>(null);

  const { data, isLoading } = useQuery({
    queryKey: ['admin-tenants-email', debouncedSearch],
    queryFn: () => getTenants({ search: debouncedSearch || undefined, per_page: 100 }),
  });

  const tenants: Tenant[] = data?.data?.data || [];

  return (
    <>
      <Title order={2} mb="md">Email Settings</Title>
      <Text c="dimmed" mb="lg">Configure SMTP email delivery per tenant. Enable email and set SMTP credentials for each tenant.</Text>

      <TextInput
        placeholder="Search tenants..."
        leftSection={<IconSearch size={16} />}
        value={search}
        onChange={(e) => setSearch(e.currentTarget.value)}
        mb="md"
        maw={300}
      />

      {isLoading ? (
        <Center py="xl"><Loader /></Center>
      ) : (
        <Table.ScrollContainer minWidth={650}>
          <Table striped highlightOnHover>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Tenant</Table.Th>
                <Table.Th>Email</Table.Th>
                <Table.Th>Email Status</Table.Th>
                <Table.Th>SMTP Host</Table.Th>
                <Table.Th w={80}>Configure</Table.Th>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {tenants.map((tenant) => (
                <Table.Tr key={tenant.id}>
                  <Table.Td fw={500}>{tenant.name}</Table.Td>
                  <Table.Td>{tenant.email}</Table.Td>
                  <Table.Td>
                    <Badge color={tenant.email_enabled ? 'green' : 'gray'} variant="light">
                      {tenant.email_enabled ? 'Enabled' : 'Disabled'}
                    </Badge>
                  </Table.Td>
                  <Table.Td c="dimmed">{tenant.smtp_host || '—'}</Table.Td>
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
        </Table.ScrollContainer>
      )}

      <Modal
        opened={!!selectedTenant}
        onClose={() => setSelectedTenant(null)}
        title={`Email Settings — ${selectedTenant?.name}`}
        size="lg"
      >
        {selectedTenant && (
          <SmtpConfigForm
            tenantId={selectedTenant.id}
            onSaved={() => {
              queryClient.invalidateQueries({ queryKey: ['admin-tenants-email'] });
              setSelectedTenant(null);
            }}
          />
        )}
      </Modal>
    </>
  );
}

function SmtpConfigForm({ tenantId, onSaved }: { tenantId: string; onSaved: () => void }) {
  const { data, isLoading } = useQuery({
    queryKey: ['admin-email-settings', tenantId],
    queryFn: () => getTenantEmailSettings(tenantId),
  });

  const settings: SmtpSettings | undefined = data?.data?.data;

  const form = useForm<SmtpSettingsFormData>({
    initialValues: {
      email_enabled: settings?.email_enabled ?? false,
      smtp_host: settings?.smtp_host ?? '',
      smtp_port: settings?.smtp_port ?? 587,
      smtp_username: settings?.smtp_username ?? '',
      smtp_password: '',
      smtp_encryption: settings?.smtp_encryption ?? 'tls',
      smtp_from_email: settings?.smtp_from_email ?? '',
      smtp_from_name: settings?.smtp_from_name ?? '',
    },
  });

  // Re-initialize when data loads
  const [initialized, setInitialized] = useState(false);
  if (settings && !initialized) {
    form.setValues({
      email_enabled: settings.email_enabled,
      smtp_host: settings.smtp_host ?? '',
      smtp_port: settings.smtp_port ?? 587,
      smtp_username: settings.smtp_username ?? '',
      smtp_password: '',
      smtp_encryption: settings.smtp_encryption ?? 'tls',
      smtp_from_email: settings.smtp_from_email ?? '',
      smtp_from_name: settings.smtp_from_name ?? '',
    });
    setInitialized(true);
  }

  const mutation = useMutation({
    mutationFn: (values: SmtpSettingsFormData) => updateTenantEmailSettings(tenantId, values),
    onSuccess: () => {
      notifications.show({ title: 'Success', message: 'Email settings updated', color: 'green' });
      onSaved();
    },
    onError: (err: any) => {
      notifications.show({
        title: 'Error',
        message: err.response?.data?.message || 'Failed to update email settings',
        color: 'red',
      });
    },
  });

  const testMutation = useMutation({
    mutationFn: () => testTenantEmailSettings(tenantId),
    onSuccess: (res) => {
      notifications.show({ title: 'Success', message: res.data.message, color: 'green' });
    },
    onError: (err: any) => {
      notifications.show({
        title: 'Test Failed',
        message: err.response?.data?.message || 'Failed to send test email',
        color: 'red',
      });
    },
  });

  if (isLoading) {
    return <Center py="xl"><Loader /></Center>;
  }

  return (
    <form onSubmit={form.onSubmit((values) => mutation.mutate(values))}>
      <Stack>
        <Switch
          label="Email Enabled"
          description="Allow this tenant to send emails"
          {...form.getInputProps('email_enabled', { type: 'checkbox' })}
        />

        <TextInput label="SMTP Host" placeholder="smtp.gmail.com" {...form.getInputProps('smtp_host')} />
        <NumberInput label="SMTP Port" placeholder="587" min={1} max={65535} {...form.getInputProps('smtp_port')} />
        <TextInput label="SMTP Username" placeholder="user@example.com" {...form.getInputProps('smtp_username')} />
        <PasswordInput
          label="SMTP Password"
          placeholder={settings?.has_password ? '••••••• (unchanged)' : 'Enter password'}
          {...form.getInputProps('smtp_password')}
        />
        <Select
          label="Encryption"
          data={[
            { value: 'tls', label: 'TLS' },
            { value: 'ssl', label: 'SSL' },
            { value: 'none', label: 'None' },
          ]}
          {...form.getInputProps('smtp_encryption')}
        />
        <TextInput label="From Email" placeholder="noreply@company.com" {...form.getInputProps('smtp_from_email')} />
        <TextInput label="From Name" placeholder="Company Name" {...form.getInputProps('smtp_from_name')} />

        <Group justify="flex-end">
          <Button
            variant="outline"
            loading={testMutation.isPending}
            onClick={() => testMutation.mutate()}
            disabled={!settings?.smtp_host}
          >
            Send Test Email
          </Button>
          <Button type="submit" loading={mutation.isPending}>Save Settings</Button>
        </Group>
      </Stack>
    </form>
  );
}
