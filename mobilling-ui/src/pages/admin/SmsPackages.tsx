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
  getSmsPackages, createSmsPackage, updateSmsPackage, deleteSmsPackage,
  SmsPackage, SmsPackageFormData,
} from '../../api/admin';

export default function SmsPackages() {
  const queryClient = useQueryClient();
  const [editPackage, setEditPackage] = useState<SmsPackage | null>(null);
  const [createOpen, setCreateOpen] = useState(false);

  const { data, isLoading } = useQuery({
    queryKey: ['admin-sms-packages'],
    queryFn: getSmsPackages,
  });

  const packages: SmsPackage[] = data?.data?.data || [];

  const deleteMut = useMutation({
    mutationFn: deleteSmsPackage,
    onSuccess: () => {
      notifications.show({ title: 'Deleted', message: 'Package deleted', color: 'green' });
      queryClient.invalidateQueries({ queryKey: ['admin-sms-packages'] });
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
      <Group justify="space-between" mb="md">
        <div>
          <Title order={2}>SMS Packages</Title>
          <Text c="dimmed">Manage SMS pricing tiers for tenant purchases.</Text>
        </div>
        <Button leftSection={<IconPlus size={16} />} onClick={() => setCreateOpen(true)}>
          Add Package
        </Button>
      </Group>

      {isLoading ? (
        <Center py="xl"><Loader /></Center>
      ) : (
        <Paper withBorder>
          <Table striped highlightOnHover>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Name</Table.Th>
                <Table.Th>Price/SMS (TZS)</Table.Th>
                <Table.Th>Min Qty</Table.Th>
                <Table.Th>Max Qty</Table.Th>
                <Table.Th>Status</Table.Th>
                <Table.Th>Order</Table.Th>
                <Table.Th w={100}>Actions</Table.Th>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {packages.map((pkg) => (
                <Table.Tr key={pkg.id}>
                  <Table.Td fw={500}>{pkg.name}</Table.Td>
                  <Table.Td>{pkg.price_per_sms}</Table.Td>
                  <Table.Td>{pkg.min_quantity.toLocaleString()}</Table.Td>
                  <Table.Td>{pkg.max_quantity?.toLocaleString() || '∞'}</Table.Td>
                  <Table.Td>
                    <Badge color={pkg.is_active ? 'green' : 'gray'} variant="light">
                      {pkg.is_active ? 'Active' : 'Inactive'}
                    </Badge>
                  </Table.Td>
                  <Table.Td>{pkg.sort_order}</Table.Td>
                  <Table.Td>
                    <Group gap={4}>
                      <ActionIcon variant="subtle" onClick={() => setEditPackage(pkg)}>
                        <IconEdit size={16} />
                      </ActionIcon>
                      <ActionIcon
                        variant="subtle"
                        color="red"
                        loading={deleteMut.isPending}
                        onClick={() => {
                          if (confirm(`Delete "${pkg.name}"?`)) deleteMut.mutate(pkg.id);
                        }}
                      >
                        <IconTrash size={16} />
                      </ActionIcon>
                    </Group>
                  </Table.Td>
                </Table.Tr>
              ))}
              {packages.length === 0 && (
                <Table.Tr>
                  <Table.Td colSpan={7}>
                    <Text ta="center" c="dimmed" py="md">No packages yet</Text>
                  </Table.Td>
                </Table.Tr>
              )}
            </Table.Tbody>
          </Table>
        </Paper>
      )}

      <Modal
        opened={createOpen}
        onClose={() => setCreateOpen(false)}
        title="Add SMS Package"
      >
        <PackageForm
          onSaved={() => {
            queryClient.invalidateQueries({ queryKey: ['admin-sms-packages'] });
            setCreateOpen(false);
          }}
        />
      </Modal>

      <Modal
        opened={!!editPackage}
        onClose={() => setEditPackage(null)}
        title={`Edit — ${editPackage?.name}`}
      >
        {editPackage && (
          <PackageForm
            existing={editPackage}
            onSaved={() => {
              queryClient.invalidateQueries({ queryKey: ['admin-sms-packages'] });
              setEditPackage(null);
            }}
          />
        )}
      </Modal>
    </>
  );
}

function PackageForm({ existing, onSaved }: { existing?: SmsPackage; onSaved: () => void }) {
  const form = useForm<SmsPackageFormData>({
    initialValues: {
      name: existing?.name ?? '',
      price_per_sms: existing ? Number(existing.price_per_sms) : '',
      min_quantity: existing?.min_quantity ?? '',
      max_quantity: existing?.max_quantity ?? '',
      is_active: existing?.is_active ?? true,
      sort_order: existing?.sort_order ?? 0,
    },
  });

  const mutation = useMutation({
    mutationFn: (values: SmsPackageFormData) =>
      existing ? updateSmsPackage(existing.id, values) : createSmsPackage(values),
    onSuccess: () => {
      notifications.show({
        title: 'Success',
        message: existing ? 'Package updated' : 'Package created',
        color: 'green',
      });
      onSaved();
    },
    onError: (err: any) => {
      notifications.show({
        title: 'Error',
        message: err.response?.data?.message || 'Failed to save package',
        color: 'red',
      });
    },
  });

  return (
    <form onSubmit={form.onSubmit((values) => mutation.mutate(values))}>
      <Stack>
        <TextInput label="Package Name" placeholder="e.g. Starter" required {...form.getInputProps('name')} />
        <NumberInput label="Price per SMS (TZS)" placeholder="25.00" min={0.01} decimalScale={2} required {...form.getInputProps('price_per_sms')} />
        <NumberInput label="Min Quantity" placeholder="100" min={1} required {...form.getInputProps('min_quantity')} />
        <NumberInput label="Max Quantity" placeholder="Leave empty for unlimited" min={1} {...form.getInputProps('max_quantity')} />
        <NumberInput label="Sort Order" min={0} {...form.getInputProps('sort_order')} />
        <Switch
          label="Active"
          {...form.getInputProps('is_active', { type: 'checkbox' })}
        />
        <Group justify="flex-end">
          <Button type="submit" loading={mutation.isPending}>
            {existing ? 'Update' : 'Create'}
          </Button>
        </Group>
      </Stack>
    </form>
  );
}
