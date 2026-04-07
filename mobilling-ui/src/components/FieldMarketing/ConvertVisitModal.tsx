import { useState } from 'react';
import { Modal, SegmentedControl, TextInput, Stack, Button, Group, Select } from '@mantine/core';
import { useForm } from '@mantine/form';
import { useQuery } from '@tanstack/react-query';
import { getClients } from '../../api/clients';
import type { FieldVisit } from '../../api/fieldMarketing';

interface Props {
  visit: FieldVisit | null;
  onClose: () => void;
  onConvert: (data: {
    client_id?: string;
    client_name?: string;
    client_email?: string;
    client_phone?: string;
  }) => void;
  loading?: boolean;
}

export default function ConvertVisitModal({ visit, onClose, onConvert, loading }: Props) {
  const [mode, setMode] = useState<'new' | 'existing'>('new');

  const { data: clientsData } = useQuery({
    queryKey: ['clients'],
    queryFn: () => getClients({ per_page: 200 }),
    enabled: mode === 'existing',
  });
  const clients: { id: string; name: string }[] = clientsData?.data?.data ?? [];

  const form = useForm({
    initialValues: {
      client_id:    '',
      client_name:  visit?.business_name ?? '',
      client_email: '',
      client_phone: visit?.phone ?? '',
    },
    validate: {
      client_name:  (v) => mode === 'new' && !v.trim() ? 'Name is required' : null,
      client_id:    (v) => mode === 'existing' && !v ? 'Select a client' : null,
    },
  });

  const handleSubmit = form.onSubmit(v => {
    if (mode === 'existing') {
      onConvert({ client_id: v.client_id });
    } else {
      onConvert({
        client_name:  v.client_name,
        client_email: v.client_email || undefined,
        client_phone: v.client_phone || undefined,
      });
    }
  });

  const clientOptions = clients.map(c => ({ value: c.id, label: c.name }));

  return (
    <Modal
      opened={!!visit}
      onClose={onClose}
      title={`Convert: ${visit?.business_name}`}
      centered
    >
      <form onSubmit={handleSubmit}>
        <Stack>
          <SegmentedControl
            value={mode}
            onChange={v => setMode(v as 'new' | 'existing')}
            data={[
              { label: 'Create New Client', value: 'new' },
              { label: 'Link Existing',     value: 'existing' },
            ]}
            fullWidth
          />

          {mode === 'new' ? (
            <>
              <TextInput label="Client Name" required {...form.getInputProps('client_name')} />
              <TextInput label="Email" type="email" {...form.getInputProps('client_email')} />
              <TextInput label="Phone" {...form.getInputProps('client_phone')} />
            </>
          ) : (
            <Select
              label="Select Client"
              placeholder="Search clients..."
              data={clientOptions}
              searchable
              required
              {...form.getInputProps('client_id')}
            />
          )}

          <Group justify="flex-end">
            <Button variant="default" onClick={onClose}>Cancel</Button>
            <Button type="submit" color="green" loading={loading}>Convert to Client</Button>
          </Group>
        </Stack>
      </form>
    </Modal>
  );
}
