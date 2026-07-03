import { useState } from 'react';
import { Stack, Paper, Title, Table, Badge, LoadingOverlay, Button, Tooltip, SegmentedControl, Group, Text, Alert } from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { useQuery } from '@tanstack/react-query';
import { useNavigate } from 'react-router-dom';
import { IconFileInvoice, IconAlertCircle } from '@tabler/icons-react';
import { getPortalSubscriptions, generateSubscriptionInvoice } from '../../api/portal';

const fmt = (n: number) => n.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const fmtDate = (d: string | null) => d ? new Date(d).toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' }) : '-';

const statusColor: Record<string, string> = {
  active: 'green', paused: 'yellow', cancelled: 'red',
};

const cycleLabel: Record<string, string> = {
  once: 'One-time',
  monthly: 'Monthly',
  quarterly: 'Quarterly',
  half_yearly: 'Half Yearly',
  yearly: 'Yearly',
};

export default function PortalSubscriptions() {
  const navigate = useNavigate();
  const [generatingId, setGeneratingId] = useState<string | null>(null);

  const { data, isLoading } = useQuery({
    queryKey: ['portal-subscriptions'],
    queryFn: () => getPortalSubscriptions(),
  });

  const allSubs = data?.data?.data || [];
  const [statusFilter, setStatusFilter] = useState('current');
  const subs = allSubs.filter((s: any) =>
    statusFilter === 'all' ? true :
    statusFilter === 'suspended' ? s.status === 'suspended' :
    ['active', 'pending'].includes(s.status));
  const counts = {
    active: allSubs.filter((s: any) => s.status === 'active').length,
    suspended: allSubs.filter((s: any) => s.status === 'suspended').length,
  };

  const handleGenerateInvoice = async (subId: string) => {
    setGeneratingId(subId);
    try {
      const res = await generateSubscriptionInvoice(subId);
      notifications.show({
        title: 'Invoice Created',
        message: `${res.data.data.document_number} created. Redirecting to invoices...`,
        color: 'green',
      });
      setTimeout(() => navigate('/portal/invoices'), 1500);
    } catch (err: any) {
      notifications.show({
        title: 'Error',
        message: err.response?.data?.message || 'Failed to generate invoice.',
        color: 'red',
      });
    } finally {
      setGeneratingId(null);
    }
  };

  return (
    <Stack gap="lg" pos="relative">
      <LoadingOverlay visible={isLoading} />
      <Group justify="space-between" align="center">
        <Group gap="sm">
          <Title order={3}>Subscriptions</Title>
          <Badge variant="light" color="green">{counts.active} active</Badge>
          {counts.suspended > 0 && <Badge variant="light" color="orange">{counts.suspended} suspended</Badge>}
        </Group>
        <SegmentedControl
          size="xs"
          value={statusFilter}
          onChange={setStatusFilter}
          data={[
            { value: 'current', label: 'Current' },
            { value: 'suspended', label: `Suspended (${counts.suspended})` },
            { value: 'all', label: 'All' },
          ]}
        />
      </Group>

      {statusFilter === 'suspended' && counts.suspended > 0 && (
        <Alert icon={<IconAlertCircle size={16} />} color="orange" variant="light">
          Suspended services usually have an unpaid invoice — check the Invoices page or contact us to restore them.
        </Alert>
      )}

      <Paper withBorder p="md">
        <Table.ScrollContainer minWidth={700}>
          <Table striped highlightOnHover>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Service</Table.Th>
                <Table.Th>Label</Table.Th>
                <Table.Th ta="right">Qty</Table.Th>
                <Table.Th ta="right">Price</Table.Th>
                <Table.Th>Schedule</Table.Th>
                <Table.Th>Start Date</Table.Th>
                <Table.Th>Expire Date</Table.Th>
                <Table.Th>Next Due</Table.Th>
                <Table.Th ta="right">Days Left</Table.Th>
                <Table.Th>Status</Table.Th>
                <Table.Th ta="center">Action</Table.Th>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {subs.length === 0 && (
                <Table.Tr>
                  <Table.Td colSpan={11}>
                    <Text c="dimmed" ta="center" py="md" size="sm">Nothing here.</Text>
                  </Table.Td>
                </Table.Tr>
              )}
              {subs.map((s: any) => {
                const daysLeft = s.status === 'active' && s.next_invoice_date
                  ? Math.ceil((new Date(s.next_invoice_date).getTime() - Date.now()) / 86400000)
                  : null;
                return (
                  <Table.Tr key={s.id}>
                    <Table.Td>{s.product_service?.name || '-'}</Table.Td>
                    <Table.Td>{s.label || '-'}</Table.Td>
                    <Table.Td ta="right">{s.quantity}</Table.Td>
                    <Table.Td ta="right">{s.product_service?.price ? fmt(s.product_service.price) : '-'}</Table.Td>
                    <Table.Td>
                      <Badge variant="light" color="gray" size="sm">
                        {cycleLabel[s.billing_cycle] || s.billing_cycle || '-'}
                      </Badge>
                    </Table.Td>
                    <Table.Td>{fmtDate(s.start_date)}</Table.Td>
                    <Table.Td>
                      {s.expire_date ? fmtDate(s.expire_date) : '-'}
                    </Table.Td>
                    <Table.Td>{s.status === 'active' ? fmtDate(s.next_invoice_date) : '-'}</Table.Td>
                    <Table.Td ta="right">
                      {daysLeft !== null && (
                        <Badge
                          variant="light"
                          color={daysLeft <= 3 ? 'red' : daysLeft <= 7 ? 'orange' : 'blue'}
                          size="sm"
                        >
                          {daysLeft <= 0 ? 'Due today' : `${daysLeft} days`}
                        </Badge>
                      )}
                    </Table.Td>
                    <Table.Td>
                      <Badge color={statusColor[s.status] || 'gray'} variant="light" size="sm">
                        {s.status}
                      </Badge>
                    </Table.Td>
                    <Table.Td ta="center">
                      {s.status === 'active' && (
                        <Tooltip label="Generate invoice and pay now">
                          <Button
                            variant="light"
                            size="compact-sm"
                            leftSection={<IconFileInvoice size={14} />}
                            loading={generatingId === s.id}
                            onClick={() => handleGenerateInvoice(s.id)}
                          >
                            Pay Now
                          </Button>
                        </Tooltip>
                      )}
                    </Table.Td>
                  </Table.Tr>
                );
              })}
              {subs.length === 0 && (
                <Table.Tr>
                  <Table.Td colSpan={11} ta="center" c="dimmed">No subscriptions found</Table.Td>
                </Table.Tr>
              )}
            </Table.Tbody>
          </Table>
        </Table.ScrollContainer>
      </Paper>
    </Stack>
  );
}
