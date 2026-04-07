import { useState } from 'react';
import {
  Modal, Stack, Button, Group, Text, Select, TextInput, Divider, SegmentedControl,
} from '@mantine/core';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { notifications } from '@mantine/notifications';
import { WhatsappContact, convertToClient } from '../../api/whatsappContacts';
import { getClients } from '../../api/clients';

interface Props {
  contact: WhatsappContact | null;
  onClose: () => void;
}

export default function ConvertToClientModal({ contact, onClose }: Props) {
  const qc = useQueryClient();
  const [mode, setMode] = useState<'existing' | 'new'>('new');
  const [existingClientId, setExistingClientId] = useState<string | null>(null);
  const [newName, setNewName] = useState(contact?.name ?? '');
  const [newEmail, setNewEmail] = useState('');
  const [newPhone, setNewPhone] = useState(contact?.phone ?? '');

  const { data: clientsData } = useQuery({
    queryKey: ['clients-simple'],
    queryFn: () => getClients({ per_page: 200 }),
    enabled: mode === 'existing',
  });

  const clientOptions = (clientsData?.data?.data ?? []).map((c: any) => ({
    value: c.id,
    label: `${c.name} ${c.phone ? `(${c.phone})` : ''}`,
  }));

  const mutation = useMutation({
    mutationFn: () => {
      if (!contact) return Promise.reject();
      if (mode === 'existing') {
        return convertToClient(contact.id, { client_id: existingClientId! });
      }
      return convertToClient(contact.id, {
        client_name: newName,
        client_email: newEmail || undefined,
        client_phone: newPhone || undefined,
      });
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['whatsapp-contacts'] });
      qc.invalidateQueries({ queryKey: ['whatsapp-stats'] });
      notifications.show({ message: 'Contact converted to client', color: 'green' });
      onClose();
    },
    onError: () => {
      notifications.show({ message: 'Conversion failed', color: 'red' });
    },
  });

  const canSubmit = mode === 'existing' ? !!existingClientId : !!newName;

  return (
    <Modal
      opened={!!contact}
      onClose={onClose}
      title={`Convert "${contact?.name}" to Client`}
      size="sm"
    >
      <Stack gap="sm">
        <Text size="sm" c="dimmed">
          This will link the contact to a MoBilling client and move them to <b>New Customer</b> stage.
        </Text>

        <SegmentedControl
          value={mode}
          onChange={(v) => setMode(v as 'existing' | 'new')}
          data={[
            { value: 'new', label: 'Create New Client' },
            { value: 'existing', label: 'Link Existing Client' },
          ]}
          fullWidth
        />

        <Divider />

        {mode === 'new' ? (
          <>
            <TextInput label="Client Name" required value={newName} onChange={(e) => setNewName(e.currentTarget.value)} />
            <TextInput label="Email" value={newEmail} onChange={(e) => setNewEmail(e.currentTarget.value)} />
            <TextInput label="Phone" value={newPhone} onChange={(e) => setNewPhone(e.currentTarget.value)} />
          </>
        ) : (
          <Select
            label="Select Existing Client"
            data={clientOptions}
            searchable
            value={existingClientId}
            onChange={setExistingClientId}
            placeholder="Search clients..."
          />
        )}

        <Group justify="flex-end" mt="sm">
          <Button variant="default" onClick={onClose}>Cancel</Button>
          <Button
            color="green"
            disabled={!canSubmit}
            loading={mutation.isPending}
            onClick={() => mutation.mutate()}
          >
            Convert to Client
          </Button>
        </Group>
      </Stack>
    </Modal>
  );
}
