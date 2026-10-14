import { useParams, useNavigate } from 'react-router-dom';
import {
  Stack, Group, Paper, Text, Title, Button, Table, Badge, SimpleGrid, Loader,
  Alert,
} from '@mantine/core';
import { useQuery } from '@tanstack/react-query';
import { IconArrowLeft, IconMail, IconCheck, IconX, IconClock, IconInfoCircle } from '@tabler/icons-react';
import { getBroadcastDeliveryReport } from '../api/broadcasts';
import StatCard from '../components/Reports/StatCard';
import { formatDate } from '../utils/formatDate';

export default function BroadcastDeliveryReport() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();

  const { data, isLoading } = useQuery({
    queryKey: ['broadcast-delivery-report', id],
    queryFn: () => getBroadcastDeliveryReport(id as string),
    enabled: !!id,
  });

  const r = data?.data;

  return (
    <Stack gap="lg">
      <Group>
        <Button
          variant="subtle"
          size="compact-sm"
          leftSection={<IconArrowLeft size={16} />}
          onClick={() => navigate('/broadcast')}
        >
          Back to Broadcast
        </Button>
      </Group>

      <Title order={2}>Delivery Report</Title>

      {isLoading && <Group justify="center" py="xl"><Loader /></Group>}

      {r && (
        <>
          <Paper withBorder p="md">
            <Text fw={600} tt="uppercase">{r.broadcast.channel}</Text>
            <Text size="sm" c="dimmed">{formatDate(r.broadcast.created_at)}</Text>
            {r.broadcast.subject && <Text mt="xs">{r.broadcast.subject}</Text>}
          </Paper>

          {r.summary.total === 0 ? (
            <Alert color="yellow" icon={<IconInfoCircle size={18} />}>
              No delivery-tracked messages found for this broadcast — it was likely sent before
              delivery-status tracking existed, so only the sent/failed counts on the Broadcast
              History page are available for it.
            </Alert>
          ) : (
            <>
              <SimpleGrid cols={{ base: 2, md: 4 }}>
                <StatCard label="Total" value={r.summary.total} icon={<IconMail size={24} />} color="blue" />
                <StatCard label="Delivered" value={r.summary.delivered} icon={<IconCheck size={24} />} color="teal" />
                <StatCard label="Delivery Failed" value={r.summary.delivery_failed} icon={<IconX size={24} />} color="red" />
                <StatCard label="Pending" value={r.summary.delivery_pending} icon={<IconClock size={24} />} color="gray" />
              </SimpleGrid>

              <Paper withBorder p="md">
                <Table.ScrollContainer minWidth={700}>
                  <Table striped highlightOnHover>
                    <Table.Thead>
                      <Table.Tr>
                        <Table.Th>Recipient</Table.Th>
                        <Table.Th>Client</Table.Th>
                        <Table.Th>Sent</Table.Th>
                        <Table.Th>Delivery</Table.Th>
                        <Table.Th>Error</Table.Th>
                      </Table.Tr>
                    </Table.Thead>
                    <Table.Tbody>
                      {r.messages.map((m) => (
                        <Table.Tr key={m.id}>
                          <Table.Td>{m.recipient}</Table.Td>
                          <Table.Td>{m.client_name || '-'}</Table.Td>
                          <Table.Td>
                            <Badge color={m.status === 'sent' ? 'green' : 'red'} variant="light" tt="capitalize">
                              {m.status}
                            </Badge>
                          </Table.Td>
                          <Table.Td>
                            {m.delivery_status ? (
                              <Badge
                                color={m.delivery_status === 'delivered' || m.delivery_status === 'read' ? 'teal' : m.delivery_status === 'failed' ? 'red' : 'gray'}
                                variant="light"
                                tt="capitalize"
                              >
                                {m.delivery_status}
                              </Badge>
                            ) : (
                              <Text size="xs" c="dimmed">pending</Text>
                            )}
                          </Table.Td>
                          <Table.Td c="red" maw={200} style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                            {m.delivery_error || m.error || '-'}
                          </Table.Td>
                        </Table.Tr>
                      ))}
                    </Table.Tbody>
                  </Table>
                </Table.ScrollContainer>
              </Paper>
            </>
          )}
        </>
      )}
    </Stack>
  );
}
