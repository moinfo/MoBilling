import { useState } from 'react';
import {
  Title, Table, Badge, ActionIcon, Modal, Stack, TextInput, NumberInput,
  Switch, Button, Group, Text, Loader, Center, Paper,
} from '@mantine/core';
import { useForm } from '@mantine/form';
import { notifications } from '@mantine/notifications';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { IconPlus, IconEdit, IconTrash } from '@tabler/icons-react';
import {
  getAdminCurrencies, createCurrency, updateCurrency, deleteCurrency,
  Currency, CurrencyFormData,
} from '../../api/admin';

export default function Currencies() {
  const queryClient = useQueryClient();
  const [editItem, setEditItem] = useState<Currency | null>(null);
  const [createOpen, setCreateOpen] = useState(false);

  const { data, isLoading } = useQuery({
    queryKey: ['admin-currencies'],
    queryFn: getAdminCurrencies,
  });

  const currencies: Currency[] = data?.data?.data || [];

  const deleteMut = useMutation({
    mutationFn: deleteCurrency,
    onSuccess: () => {
      notifications.show({ title: 'Deleted', message: 'Currency deleted', color: 'green' });
      queryClient.invalidateQueries({ queryKey: ['admin-currencies'] });
    },
    onError: (err: any) => {
      notifications.show({
        title: 'Error',
        message: err.response?.data?.message || 'Failed to delete',
        color: 'red',
      });
    },
  });

  return (
    <>
      <Group justify="space-between" mb="md" wrap="wrap">
        <div>
          <Title order={2}>Currencies</Title>
          <Text c="dimmed">Manage currencies available for tenants.</Text>
        </div>
        <Button leftSection={<IconPlus size={16} />} onClick={() => setCreateOpen(true)}>
          Add Currency
        </Button>
      </Group>

      {isLoading ? (
        <Center py="xl"><Loader /></Center>
      ) : (
        <Paper withBorder>
          <Table.ScrollContainer minWidth={550}>
            <Table striped highlightOnHover>
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Code</Table.Th>
                  <Table.Th>Name</Table.Th>
                  <Table.Th>Symbol</Table.Th>
                  <Table.Th>Status</Table.Th>
                  <Table.Th>Order</Table.Th>
                  <Table.Th w={100}>Actions</Table.Th>
                </Table.Tr>
              </Table.Thead>
            <Table.Tbody>
              {currencies.map((c) => (
                <Table.Tr key={c.id}>
                  <Table.Td fw={600}>{c.code}</Table.Td>
                  <Table.Td>{c.name}</Table.Td>
                  <Table.Td><Text c="dimmed">{c.symbol || '—'}</Text></Table.Td>
                  <Table.Td>
                    <Badge color={c.is_active ? 'green' : 'gray'} variant="light">
                      {c.is_active ? 'Active' : 'Inactive'}
                    </Badge>
                  </Table.Td>
                  <Table.Td>{c.sort_order}</Table.Td>
                  <Table.Td>
                    <Group gap={4}>
                      <ActionIcon variant="subtle" onClick={() => setEditItem(c)}>
                        <IconEdit size={16} />
                      </ActionIcon>
                      <ActionIcon
                        variant="subtle"
                        color="red"
                        loading={deleteMut.isPending}
                        onClick={() => {
                          if (confirm(`Delete "${c.code}"?`)) deleteMut.mutate(c.id);
                        }}
                      >
                        <IconTrash size={16} />
                      </ActionIcon>
                    </Group>
                  </Table.Td>
                </Table.Tr>
              ))}
              {currencies.length === 0 && (
                <Table.Tr>
                  <Table.Td colSpan={6}>
                    <Text ta="center" c="dimmed" py="md">No currencies configured</Text>
                  </Table.Td>
                </Table.Tr>
              )}
            </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        </Paper>
      )}

      <Modal opened={createOpen} onClose={() => setCreateOpen(false)} title="Add Currency">
        <CurrencyForm
          onSaved={() => {
            queryClient.invalidateQueries({ queryKey: ['admin-currencies'] });
            setCreateOpen(false);
          }}
        />
      </Modal>

      <Modal opened={!!editItem} onClose={() => setEditItem(null)} title={`Edit — ${editItem?.code}`}>
        {editItem && (
          <CurrencyForm
            existing={editItem}
            onSaved={() => {
              queryClient.invalidateQueries({ queryKey: ['admin-currencies'] });
              setEditItem(null);
            }}
          />
        )}
      </Modal>
    </>
  );
}

function CurrencyForm({ existing, onSaved }: { existing?: Currency; onSaved: () => void }) {
  const form = useForm<CurrencyFormData>({
    initialValues: {
      code: existing?.code ?? '',
      name: existing?.name ?? '',
      symbol: existing?.symbol ?? '',
      is_active: existing?.is_active ?? true,
      sort_order: existing?.sort_order ?? 0,
    },
  });

  const mutation = useMutation({
    mutationFn: (values: CurrencyFormData) =>
      existing ? updateCurrency(existing.id, values) : createCurrency(values),
    onSuccess: () => {
      notifications.show({
        title: 'Success',
        message: existing ? 'Currency updated' : 'Currency created',
        color: 'green',
      });
      onSaved();
    },
    onError: (err: any) => {
      notifications.show({
        title: 'Error',
        message: err.response?.data?.message || 'Failed to save',
        color: 'red',
      });
    },
  });

  return (
    <form onSubmit={form.onSubmit((values) => mutation.mutate(values))}>
      <Stack>
        <TextInput
          label="Currency Code"
          placeholder="e.g. TZS"
          required
          maxLength={10}
          {...form.getInputProps('code')}
          onChange={(e) => form.setFieldValue('code', e.currentTarget.value.toUpperCase())}
        />
        <TextInput label="Name" placeholder="e.g. Tanzanian Shilling" required {...form.getInputProps('name')} />
        <TextInput label="Symbol" placeholder="e.g. TSh" {...form.getInputProps('symbol')} />
        <NumberInput label="Sort Order" min={0} {...form.getInputProps('sort_order')} />
        <Switch label="Active" {...form.getInputProps('is_active', { type: 'checkbox' })} />
        <Group justify="flex-end">
          <Button type="submit" loading={mutation.isPending}>
            {existing ? 'Update' : 'Create'}
          </Button>
        </Group>
      </Stack>
    </form>
  );
}
