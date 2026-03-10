import { useState } from 'react';
import { Stack, Paper, Title, Table, Badge, TextInput, Group, LoadingOverlay, SegmentedControl } from '@mantine/core';
import { useQuery } from '@tanstack/react-query';
import { IconSearch } from '@tabler/icons-react';
import { getPortalProductServices } from '../../api/portal';

const fmt = (n: number) => n.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 });

const cycleLabel: Record<string, string> = {
  once: 'One-time',
  monthly: 'Monthly',
  quarterly: 'Quarterly',
  half_yearly: 'Half Yearly',
  yearly: 'Yearly',
};

export default function PortalProductServices() {
  const [search, setSearch] = useState('');
  const [typeFilter, setTypeFilter] = useState('all');

  const { data, isLoading } = useQuery({
    queryKey: ['portal-products', typeFilter, search],
    queryFn: () => getPortalProductServices({
      type: typeFilter === 'all' ? undefined : typeFilter,
      search: search || undefined,
    }),
  });

  const items = data?.data?.data || [];

  return (
    <Stack gap="lg" pos="relative">
      <LoadingOverlay visible={isLoading} />
      <Group justify="space-between">
        <Title order={3}>Products & Services</Title>
        <Group>
          <SegmentedControl
            size="sm"
            value={typeFilter}
            onChange={setTypeFilter}
            data={[
              { value: 'all', label: 'All' },
              { value: 'product', label: 'Products' },
              { value: 'service', label: 'Services' },
            ]}
          />
          <TextInput
            placeholder="Search..."
            leftSection={<IconSearch size={16} />}
            value={search}
            onChange={(e) => setSearch(e.currentTarget.value)}
            w={200}
          />
        </Group>
      </Group>

      <Paper withBorder p="md">
        <Table.ScrollContainer minWidth={600}>
          <Table striped highlightOnHover>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Name</Table.Th>
                <Table.Th>Type</Table.Th>
                <Table.Th>Description</Table.Th>
                <Table.Th ta="right">Price</Table.Th>
                <Table.Th>Billing</Table.Th>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {items.map((item) => (
                <Table.Tr key={item.id}>
                  <Table.Td fw={600}>{item.name}</Table.Td>
                  <Table.Td>
                    <Badge variant="light" color={item.type === 'service' ? 'blue' : 'grape'} size="sm">
                      {item.type}
                    </Badge>
                  </Table.Td>
                  <Table.Td c="dimmed">{item.description || '-'}</Table.Td>
                  <Table.Td ta="right" fw={600}>{fmt(item.price)}</Table.Td>
                  <Table.Td>
                    {item.billing_cycle ? (
                      <Badge variant="light" color="gray" size="sm">
                        {cycleLabel[item.billing_cycle] || item.billing_cycle}
                      </Badge>
                    ) : '-'}
                  </Table.Td>
                </Table.Tr>
              ))}
              {items.length === 0 && (
                <Table.Tr>
                  <Table.Td colSpan={5} ta="center" c="dimmed">No products or services found</Table.Td>
                </Table.Tr>
              )}
            </Table.Tbody>
          </Table>
        </Table.ScrollContainer>
      </Paper>
    </Stack>
  );
}
