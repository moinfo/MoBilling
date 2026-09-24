import { useState } from 'react';
import { Table, Badge, ActionIcon, Group, Switch, Text, Tooltip, Modal, Stack, Center, Loader } from '@mantine/core';
import { useQuery } from '@tanstack/react-query';
import { IconEdit, IconTrash, IconServer } from '@tabler/icons-react';
import { ProductService } from '../../api/productServices';
import { getClientSubscriptions } from '../../api/clientSubscriptions';
import { formatCurrency } from '../../utils/formatCurrency';
import { formatDate } from '../../utils/formatDate';
import { usePermissions } from '../../hooks/usePermissions';

interface Props {
  items: ProductService[];
  onEdit: (item: ProductService) => void;
  onDelete: (item: ProductService) => void;
}

const statusColors: Record<string, string> = { active: 'green', pending: 'blue', cancelled: 'red', suspended: 'yellow' };

export default function ProductServiceTable({ items, onEdit, onDelete }: Props) {
  const { can } = usePermissions();
  const canSeeSubscribers = can('client_subscriptions.read');
  const [viewing, setViewing] = useState<ProductService | null>(null);

  if (items.length === 0) {
    return <Text c="dimmed" ta="center" py="xl">No products or services found</Text>;
  }

  return (
    <>
    <Table.ScrollContainer minWidth={800}>
      <Table striped highlightOnHover>
        <Table.Thead>
          <Table.Tr>
            <Table.Th>Type</Table.Th>
            <Table.Th>Code</Table.Th>
            <Table.Th>Name</Table.Th>
            <Table.Th>Price</Table.Th>
            <Table.Th>Tax %</Table.Th>
            <Table.Th>Unit</Table.Th>
            <Table.Th>WHM</Table.Th>
            <Table.Th>Used By</Table.Th>
            <Table.Th>Active</Table.Th>
            <Table.Th w={100}>Actions</Table.Th>
          </Table.Tr>
        </Table.Thead>
      <Table.Tbody>
        {items.map((item) => (
          <Table.Tr key={item.id}>
            <Table.Td>
              <Badge color={item.type === 'product' ? 'blue' : 'green'} size="sm">
                {item.type}
              </Badge>
            </Table.Td>
            <Table.Td>{item.code || '—'}</Table.Td>
            <Table.Td>{item.name}</Table.Td>
            <Table.Td>{formatCurrency(item.price)}</Table.Td>
            <Table.Td>{item.tax_percent}%</Table.Td>
            <Table.Td>{item.unit}</Table.Td>
            <Table.Td>
              {item.provisioning_type === 'whm_cpanel' ? (
                <Tooltip label={`cPanel package: ${item.cpanel_package ?? '—'}${item.auto_provision ? ' · auto-provision' : ''}`}>
                  <Badge size="xs" variant="light" color="teal" leftSection={<IconServer size={10} />}>
                    {item.cpanel_package ?? 'WHM'}
                  </Badge>
                </Tooltip>
              ) : item.provisioning_type === 'linode' ? (
                <Tooltip label="Linode server: billing only, no automatic action on the server">
                  <Badge size="xs" variant="light" color="indigo" leftSection={<IconServer size={10} />}>Linode</Badge>
                </Tooltip>
              ) : (
                <Text size="xs" c="dimmed">—</Text>
              )}
            </Table.Td>
            <Table.Td>
              {item.clients_count ? (
                <Tooltip label={`${item.subscriptions_count} subscription(s) total, ${item.active_subscriptions_count} currently active${canSeeSubscribers ? ' — click to view' : ''}`}>
                  <Badge
                    size="sm" variant="light" color={item.active_subscriptions_count ? 'teal' : 'gray'}
                    style={canSeeSubscribers ? { cursor: 'pointer' } : undefined}
                    onClick={canSeeSubscribers ? () => setViewing(item) : undefined}
                  >
                    {item.clients_count} client{item.clients_count === 1 ? '' : 's'}
                  </Badge>
                </Tooltip>
              ) : (
                <Text size="xs" c="dimmed">Unused</Text>
              )}
            </Table.Td>
            <Table.Td><Switch checked={item.is_active} readOnly size="xs" /></Table.Td>
            <Table.Td>
              <Group gap="xs">
                <ActionIcon variant="light" onClick={() => onEdit(item)}>
                  <IconEdit size={16} />
                </ActionIcon>
                <ActionIcon variant="light" color="red" onClick={() => onDelete(item)}>
                  <IconTrash size={16} />
                </ActionIcon>
              </Group>
            </Table.Td>
          </Table.Tr>
        ))}
      </Table.Tbody>
      </Table>
    </Table.ScrollContainer>
    <SubscribersModal item={viewing} onClose={() => setViewing(null)} />
    </>
  );
}

function SubscribersModal({ item, onClose }: { item: ProductService | null; onClose: () => void }) {
  const { data, isLoading } = useQuery({
    queryKey: ['product-subscribers', item?.id],
    queryFn: () => getClientSubscriptions({ product_service_id: item!.id, per_page: 200 }),
    enabled: !!item,
  });
  const subs = (data as any)?.data?.data ?? [];

  return (
    <Modal opened={!!item} onClose={onClose} title={`Clients on ${item?.name} — ${item ? formatCurrency(item.price) : ''}`} size="lg">
      {isLoading ? (
        <Center py="xl"><Loader size="sm" /></Center>
      ) : subs.length === 0 ? (
        <Text c="dimmed" ta="center" py="md">No subscriptions found.</Text>
      ) : (
        <Stack gap={0}>
          <Table striped highlightOnHover verticalSpacing="xs">
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Client</Table.Th>
                <Table.Th>Status</Table.Th>
                <Table.Th>Start</Table.Th>
                <Table.Th>Expires</Table.Th>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {subs.map((s: any) => (
                <Table.Tr key={s.id}>
                  <Table.Td>{s.client_name ?? '—'}</Table.Td>
                  <Table.Td>
                    <Badge size="sm" variant="light" color={statusColors[s.status] ?? 'gray'}>{s.status}</Badge>
                  </Table.Td>
                  <Table.Td fz="sm" c="dimmed">{formatDate(s.start_date)}</Table.Td>
                  <Table.Td fz="sm" c="dimmed">{s.expire_date ? formatDate(s.expire_date) : '—'}</Table.Td>
                </Table.Tr>
              ))}
            </Table.Tbody>
          </Table>
        </Stack>
      )}
    </Modal>
  );
}
