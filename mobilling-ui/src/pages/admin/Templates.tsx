import { useState } from 'react';
import {
  Title, Table, ActionIcon, Modal, Stack, TextInput, Textarea, Button,
  Group, Text, Loader, Center, Paper, Badge, Divider, Box, Alert,
} from '@mantine/core';
import { useForm } from '@mantine/form';
import { useDebouncedValue } from '@mantine/hooks';
import { notifications } from '@mantine/notifications';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { IconSettings, IconSearch, IconAlertCircle } from '@tabler/icons-react';
import {
  getTenants, getTenantTemplates, updateTenantTemplates,
  Tenant, TenantTemplates,
} from '../../api/admin';

const DEFAULT_TEMPLATES: TenantTemplates = {
  invoice_email_subject: '{doc_type} {doc_number} — {company_name}',
  invoice_email_body: 'Hello {client_name},\n\nPlease find attached your {doc_type}.\n\nAmount: {currency} {amount}\nDue date: {due_date}\n\nThank you for your business.',
  reminder_email_subject: 'Reminder: {bill_name} due on {due_date}',
  reminder_email_body: '{bill_name} of {currency} {amount} is due on {due_date}. Please pay on time.',
  overdue_email_subject: 'OVERDUE: {bill_name} — {company_name}',
  overdue_email_body: '{bill_name} of {currency} {amount} was due on {due_date}. This bill is now overdue. Please pay immediately.',
  reminder_sms_body: '{bill_name} of {currency} {amount} is due on {due_date}. Please pay on time.',
  overdue_sms_body: 'OVERDUE: {bill_name} of {currency} {amount} was due {due_date}. Pay immediately.',
  email_footer_text: null,
};

export default function Templates() {
  const [search, setSearch] = useState('');
  const [debouncedSearch] = useDebouncedValue(search, 300);
  const [selectedTenant, setSelectedTenant] = useState<Tenant | null>(null);

  const { data, isLoading } = useQuery({
    queryKey: ['admin-tenants-templates', debouncedSearch],
    queryFn: () => getTenants({ search: debouncedSearch || undefined, per_page: 100 }),
  });

  const tenants: Tenant[] = data?.data?.data || [];

  return (
    <>
      <Title order={2} mb="md">Email Templates</Title>
      <Text c="dimmed" mb="lg">
        Manage email and SMS templates per tenant. Customize invoice emails, bill reminders, and email branding.
      </Text>

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
        <Table.ScrollContainer minWidth={500}>
          <Table striped highlightOnHover>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Tenant</Table.Th>
                <Table.Th>Email</Table.Th>
                <Table.Th>Currency</Table.Th>
                <Table.Th w={80}>Configure</Table.Th>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {tenants.map((tenant) => (
                <Table.Tr key={tenant.id}>
                  <Table.Td fw={500}>{tenant.name}</Table.Td>
                  <Table.Td>{tenant.email}</Table.Td>
                  <Table.Td>{tenant.currency}</Table.Td>
                  <Table.Td>
                    <ActionIcon variant="subtle" onClick={() => setSelectedTenant(tenant)}>
                      <IconSettings size={18} />
                    </ActionIcon>
                  </Table.Td>
                </Table.Tr>
              ))}
              {tenants.length === 0 && (
                <Table.Tr>
                  <Table.Td colSpan={4}>
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
        title={`Templates — ${selectedTenant?.name}`}
        size="xl"
      >
        {selectedTenant && (
          <TemplatesForm
            tenantId={selectedTenant.id}
            onSaved={() => setSelectedTenant(null)}
          />
        )}
      </Modal>
    </>
  );
}

function TemplatesForm({ tenantId, onSaved }: { tenantId: string; onSaved: () => void }) {
  const queryClient = useQueryClient();

  const { data, isLoading } = useQuery({
    queryKey: ['admin-tenant-templates', tenantId],
    queryFn: () => getTenantTemplates(tenantId),
  });

  const settings: TenantTemplates | undefined = data?.data?.data;

  const form = useForm<TenantTemplates>({
    initialValues: { ...DEFAULT_TEMPLATES },
  });

  const [initialized, setInitialized] = useState(false);
  if (settings && !initialized) {
    form.setValues({
      invoice_email_subject: settings.invoice_email_subject ?? DEFAULT_TEMPLATES.invoice_email_subject,
      invoice_email_body: settings.invoice_email_body ?? DEFAULT_TEMPLATES.invoice_email_body,
      reminder_email_subject: settings.reminder_email_subject ?? DEFAULT_TEMPLATES.reminder_email_subject,
      reminder_email_body: settings.reminder_email_body ?? DEFAULT_TEMPLATES.reminder_email_body,
      overdue_email_subject: settings.overdue_email_subject ?? DEFAULT_TEMPLATES.overdue_email_subject,
      overdue_email_body: settings.overdue_email_body ?? DEFAULT_TEMPLATES.overdue_email_body,
      reminder_sms_body: settings.reminder_sms_body ?? DEFAULT_TEMPLATES.reminder_sms_body,
      overdue_sms_body: settings.overdue_sms_body ?? DEFAULT_TEMPLATES.overdue_sms_body,
      email_footer_text: settings.email_footer_text ?? DEFAULT_TEMPLATES.email_footer_text,
    });
    setInitialized(true);
  }

  const mutation = useMutation({
    mutationFn: (values: TenantTemplates) => updateTenantTemplates(tenantId, values),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['admin-tenant-templates', tenantId] });
      notifications.show({ title: 'Success', message: 'Templates updated', color: 'green' });
      onSaved();
    },
    onError: (err: any) => {
      notifications.show({
        title: 'Error',
        message: err.response?.data?.message || 'Failed to update templates',
        color: 'red',
      });
    },
  });

  const handleResetDefaults = () => {
    form.setValues({ ...DEFAULT_TEMPLATES });
  };

  if (isLoading) {
    return <Center py="xl"><Loader /></Center>;
  }

  return (
    <form onSubmit={form.onSubmit((values) => mutation.mutate(values))}>
      <Stack>
        {/* Email Branding */}
        <Divider label="Email Branding" labelPosition="left" />

        <Textarea
          label="Email Footer Text"
          description="Custom footer for all emails. Leave blank for default."
          placeholder="e.g. 123 Business St, Nairobi · +254 700 123456"
          autosize
          minRows={2}
          maxLength={500}
          {...form.getInputProps('email_footer_text')}
        />

        {/* Invoice / Quote Email */}
        <Divider label="Invoice / Quote Email" labelPosition="left" mt="sm" />

        <Alert variant="light" color="blue" icon={<IconAlertCircle size={16} />} py="xs">
          <Text size="xs">
            Placeholders: <Badge size="xs" variant="light">{'{doc_type}'}</Badge>{' '}
            <Badge size="xs" variant="light">{'{doc_number}'}</Badge>{' '}
            <Badge size="xs" variant="light">{'{client_name}'}</Badge>{' '}
            <Badge size="xs" variant="light">{'{amount}'}</Badge>{' '}
            <Badge size="xs" variant="light">{'{currency}'}</Badge>{' '}
            <Badge size="xs" variant="light">{'{due_date}'}</Badge>{' '}
            <Badge size="xs" variant="light">{'{company_name}'}</Badge>
          </Text>
        </Alert>

        <TextInput label="Subject" {...form.getInputProps('invoice_email_subject')} />
        <Textarea label="Body" autosize minRows={3} {...form.getInputProps('invoice_email_body')} />

        {/* Bill Reminder Email & SMS */}
        <Divider label="Bill Reminder Email & SMS" labelPosition="left" mt="sm" />

        <Alert variant="light" color="blue" icon={<IconAlertCircle size={16} />} py="xs">
          <Text size="xs">
            Placeholders: <Badge size="xs" variant="light">{'{bill_name}'}</Badge>{' '}
            <Badge size="xs" variant="light">{'{amount}'}</Badge>{' '}
            <Badge size="xs" variant="light">{'{currency}'}</Badge>{' '}
            <Badge size="xs" variant="light">{'{due_date}'}</Badge>{' '}
            <Badge size="xs" variant="light">{'{company_name}'}</Badge>
          </Text>
        </Alert>

        <TextInput label="Due Reminder — Subject" {...form.getInputProps('reminder_email_subject')} />
        <Textarea label="Due Reminder — Body" autosize minRows={2} {...form.getInputProps('reminder_email_body')} />
        <TextInput label="Overdue — Subject" {...form.getInputProps('overdue_email_subject')} />
        <Textarea label="Overdue — Body" autosize minRows={2} {...form.getInputProps('overdue_email_body')} />

        <Divider label="SMS Templates" labelPosition="left" />

        <Box>
          <Textarea label="Due Reminder SMS" autosize minRows={2} maxLength={160} {...form.getInputProps('reminder_sms_body')} />
          <Text size="xs" c="dimmed" ta="right">{(form.values.reminder_sms_body || '').length}/160</Text>
        </Box>
        <Box>
          <Textarea label="Overdue SMS" autosize minRows={2} maxLength={160} {...form.getInputProps('overdue_sms_body')} />
          <Text size="xs" c="dimmed" ta="right">{(form.values.overdue_sms_body || '').length}/160</Text>
        </Box>

        <Group justify="space-between">
          <Button variant="subtle" color="gray" onClick={handleResetDefaults}>
            Reset to Defaults
          </Button>
          <Button type="submit" loading={mutation.isPending}>Save Templates</Button>
        </Group>
      </Stack>
    </form>
  );
}
