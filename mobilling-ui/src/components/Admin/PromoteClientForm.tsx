import { useState } from 'react';
import {
  TextInput, Textarea, Button, Group, Stack, Select, PasswordInput,
  Paper, UnstyledButton, Text, Loader, Center,
} from '@mantine/core';
import { useForm } from '@mantine/form';
import { useQuery } from '@tanstack/react-query';
import { useDebouncedValue } from '@mantine/hooks';
import { IconSearch, IconArrowLeft } from '@tabler/icons-react';
import { searchAdminClients, ClientSearchResult, PromoteClientData, getActiveCurrencies } from '../../api/admin';

interface Props {
  onSubmit: (values: PromoteClientData) => void;
  loading?: boolean;
}

export default function PromoteClientForm({ onSubmit, loading }: Props) {
  const [selected, setSelected] = useState<ClientSearchResult | null>(null);
  const [search, setSearch] = useState('');
  const [debouncedSearch] = useDebouncedValue(search, 300);

  const { data: currencyData } = useQuery({
    queryKey: ['active-currencies'],
    queryFn: getActiveCurrencies,
  });
  const currencyOptions = (currencyData?.data?.data || []).map((c) => ({
    value: c.code,
    label: `${c.code} — ${c.name}`,
  }));

  const { data: searchData, isFetching } = useQuery({
    queryKey: ['admin-client-search', debouncedSearch],
    queryFn: () => searchAdminClients(debouncedSearch),
    enabled: debouncedSearch.length >= 2,
  });
  const results = searchData?.data?.data || [];

  const form = useForm({
    initialValues: {
      client_id: '', name: '', email: '', phone: '', address: '', tax_id: '',
      currency: 'TZS', admin_name: '', admin_email: '', admin_password: '',
    },
    validate: {
      name: (v) => (v.length > 0 ? null : 'Company name is required'),
      email: (v) => (/^\S+@\S+$/.test(v) ? null : 'Valid email is required'),
      admin_name: (v) => (v.length > 0 ? null : 'Admin name is required'),
      admin_email: (v) => (/^\S+@\S+$/.test(v) ? null : 'Valid admin email is required'),
      admin_password: (v) => (v.length >= 8 ? null : 'Password must be at least 8 characters'),
    },
  });

  const pickClient = (client: ClientSearchResult) => {
    setSelected(client);
    form.setValues({
      client_id: client.id,
      name: client.name,
      email: client.email || '',
      phone: client.phone || '',
      address: client.address || '',
      tax_id: client.tax_id || '',
      currency: client.tenant?.currency || 'TZS',
      admin_name: '', admin_email: '', admin_password: '',
    });
  };

  const backToSearch = () => {
    setSelected(null);
    form.reset();
  };

  if (!selected) {
    return (
      <Stack>
        <Text size="sm" c="dimmed">
          Search for the client to promote into their own independent, white-label tenant.
        </Text>
        <TextInput
          placeholder="Search by name, email, phone or TIN..."
          leftSection={<IconSearch size={16} />}
          value={search}
          onChange={(e) => setSearch(e.currentTarget.value)}
          autoFocus
        />
        {isFetching && <Center py="sm"><Loader size="sm" /></Center>}
        {!isFetching && debouncedSearch.length >= 2 && results.length === 0 && (
          <Text size="sm" c="dimmed" ta="center" py="sm">No clients found.</Text>
        )}
        <Stack gap={4}>
          {results.map((c) => (
            <UnstyledButton key={c.id} onClick={() => pickClient(c)}>
              <Paper withBorder p="xs" radius="sm">
                <Text size="sm" fw={500}>{c.name}</Text>
                <Text size="xs" c="dimmed">
                  {c.tenant?.name ?? 'Unknown tenant'} {c.email ? `· ${c.email}` : ''} {c.phone ? `· ${c.phone}` : ''}
                </Text>
              </Paper>
            </UnstyledButton>
          ))}
        </Stack>
      </Stack>
    );
  }

  return (
    <form onSubmit={form.onSubmit((values) => onSubmit(values as PromoteClientData))}>
      <Stack>
        <Button variant="subtle" size="xs" leftSection={<IconArrowLeft size={14} />}
          onClick={backToSearch} style={{ alignSelf: 'flex-start' }}>
          Choose a different client
        </Button>
        <Text size="xs" c="dimmed">
          Promoting <b>{selected.name}</b> (currently a client of {selected.tenant?.name ?? 'unknown tenant'}) —
          nothing about their existing account moves; this creates a brand-new, separate tenant.
        </Text>

        <TextInput label="Company Name" placeholder="Acme Ltd" required {...form.getInputProps('name')} />
        <TextInput label="Company Email" placeholder="info@acme.com" required {...form.getInputProps('email')} />
        <TextInput label="Phone" placeholder="+255 7xx xxx xxx" {...form.getInputProps('phone')} />
        <Textarea label="Address" placeholder="Company address" {...form.getInputProps('address')} />
        <TextInput label="Tax ID / TIN" placeholder="e.g., 123-456-789" {...form.getInputProps('tax_id')} />
        <Select label="Currency" data={currencyOptions} searchable {...form.getInputProps('currency')} />

        <TextInput label="Admin Name" placeholder="John Doe" required {...form.getInputProps('admin_name')} />
        <TextInput label="Admin Email" placeholder="admin@acme.com" required {...form.getInputProps('admin_email')} />
        <PasswordInput label="Admin Password" placeholder="Min. 8 characters" required {...form.getInputProps('admin_password')} />

        <Group justify="flex-end">
          <Button type="submit" loading={loading}>Promote to Tenant</Button>
        </Group>
      </Stack>
    </form>
  );
}
