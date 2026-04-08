import { useState } from 'react';
import {
  Stack, Group, Button, TextInput, ActionIcon, Text, Table,
  Badge, Loader, Alert,
} from '@mantine/core';
import { IconPlus, IconEdit, IconTrash, IconCheck, IconX, IconAlertCircle } from '@tabler/icons-react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { notifications } from '@mantine/notifications';
import { usePermissions } from '../../hooks/usePermissions';
import {
  getServices, createService, updateService, deleteService,
  type MarketingService,
} from '../../api/marketingServices';

export default function ServicesManager() {
  const { can } = usePermissions();
  const qc = useQueryClient();

  const [newName, setNewName] = useState('');
  const [editId, setEditId] = useState<string | null>(null);
  const [editName, setEditName] = useState('');

  const { data, isLoading } = useQuery({
    queryKey: ['marketing-services'],
    queryFn: getServices,
    enabled: can('marketing_services.read'),
  });

  const services: MarketingService[] = data?.data ?? [];

  const invalidate = () => qc.invalidateQueries({ queryKey: ['marketing-services'] });

  const createMutation = useMutation({
    mutationFn: () => createService(newName.trim()),
    onSuccess: () => {
      setNewName('');
      invalidate();
      notifications.show({ message: 'Service added', color: 'green' });
    },
    onError: (err: any) => {
      const msg = err?.response?.data?.message ?? 'Failed to add service';
      notifications.show({ message: msg, color: 'red' });
    },
  });

  const updateMutation = useMutation({
    mutationFn: () => updateService(editId!, editName.trim()),
    onSuccess: () => {
      setEditId(null);
      invalidate();
      notifications.show({ message: 'Service updated', color: 'green' });
    },
    onError: (err: any) => {
      const msg = err?.response?.data?.message ?? 'Failed to update service';
      notifications.show({ message: msg, color: 'red' });
    },
  });

  const deleteMutation = useMutation({
    mutationFn: deleteService,
    onSuccess: () => {
      invalidate();
      notifications.show({ message: 'Service deleted', color: 'orange' });
    },
  });

  const startEdit = (s: MarketingService) => {
    setEditId(s.id);
    setEditName(s.name);
  };

  const cancelEdit = () => {
    setEditId(null);
    setEditName('');
  };

  if (!can('marketing_services.read')) {
    return <Alert icon={<IconAlertCircle size={16} />} color="red">No permission to view services.</Alert>;
  }

  return (
    <Stack gap="md">
      <Text c="dimmed" size="sm">
        Manage the list of services shown in field visit forms and WhatsApp contact forms.
        Changes apply to all users in your organisation.
      </Text>

      {can('marketing_services.create') && (
        <Group gap="xs" align="flex-end">
          <TextInput
            placeholder="Service name..."
            value={newName}
            onChange={(e) => setNewName(e.currentTarget.value)}
            onKeyDown={(e) => { if (e.key === 'Enter' && newName.trim()) createMutation.mutate(); }}
            w={260}
          />
          <Button
            leftSection={<IconPlus size={14} />}
            onClick={() => createMutation.mutate()}
            disabled={!newName.trim()}
            loading={createMutation.isPending}
          >
            Add Service
          </Button>
        </Group>
      )}

      {isLoading ? (
        <Group justify="center" py="xl"><Loader size="sm" /></Group>
      ) : services.length === 0 ? (
        <Text c="dimmed" ta="center" py="md">No services found.</Text>
      ) : (
        <Table.ScrollContainer minWidth={400}>
          <Table highlightOnHover>
            <Table.Thead>
              <Table.Tr>
                <Table.Th w={40}>#</Table.Th>
                <Table.Th>Service Name</Table.Th>
                <Table.Th w={120}></Table.Th>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {services.map((s, idx) => (
                <Table.Tr key={s.id}>
                  <Table.Td>
                    <Text size="sm" c="dimmed">{idx + 1}</Text>
                  </Table.Td>
                  <Table.Td>
                    {editId === s.id ? (
                      <TextInput
                        value={editName}
                        onChange={(e) => setEditName(e.currentTarget.value)}
                        onKeyDown={(e) => {
                          if (e.key === 'Enter' && editName.trim()) updateMutation.mutate();
                          if (e.key === 'Escape') cancelEdit();
                        }}
                        autoFocus
                        size="xs"
                        w={200}
                      />
                    ) : (
                      <Badge variant="outline" color="blue" size="md">{s.name}</Badge>
                    )}
                  </Table.Td>
                  <Table.Td>
                    <Group gap={4} justify="flex-end">
                      {editId === s.id ? (
                        <>
                          <ActionIcon
                            color="green"
                            variant="light"
                            onClick={() => updateMutation.mutate()}
                            loading={updateMutation.isPending}
                            disabled={!editName.trim()}
                          >
                            <IconCheck size={14} />
                          </ActionIcon>
                          <ActionIcon variant="light" onClick={cancelEdit}>
                            <IconX size={14} />
                          </ActionIcon>
                        </>
                      ) : (
                        <>
                          {can('marketing_services.update') && (
                            <ActionIcon variant="light" onClick={() => startEdit(s)}>
                              <IconEdit size={14} />
                            </ActionIcon>
                          )}
                          {can('marketing_services.delete') && (
                            <ActionIcon
                              variant="light"
                              color="red"
                              onClick={() => deleteMutation.mutate(s.id)}
                              loading={deleteMutation.isPending && deleteMutation.variables === s.id}
                            >
                              <IconTrash size={14} />
                            </ActionIcon>
                          )}
                        </>
                      )}
                    </Group>
                  </Table.Td>
                </Table.Tr>
              ))}
            </Table.Tbody>
          </Table>
        </Table.ScrollContainer>
      )}
    </Stack>
  );
}
