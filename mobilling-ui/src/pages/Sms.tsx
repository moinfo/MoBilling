import { useState } from 'react';
import {
  Title, Text, Paper, Group, Badge, Card, SimpleGrid, Stack,
  NumberInput, Button, Table, Pagination, Loader, Center, Alert,
} from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { IconMessage, IconAlertCircle } from '@tabler/icons-react';
import {
  getSmsPackages, getSmsBalance, smsCheckout, getSmsPurchaseHistory,
  SmsPackage, SmsPurchase,
} from '../api/sms';

const statusColors: Record<string, string> = {
  pending: 'yellow',
  completed: 'green',
  failed: 'red',
};

export default function Sms() {
  return (
    <Stack gap="xl">
      <div>
        <Title order={2} mb={4}>SMS</Title>
        <Text c="dimmed">View your SMS balance, buy credits, and track purchases.</Text>
      </div>

      <BalanceCard />
      <BuySection />
      <PurchaseHistory />
    </Stack>
  );
}

function BalanceCard() {
  const { data, isLoading } = useQuery({
    queryKey: ['sms-balance'],
    queryFn: getSmsBalance,
  });

  const balance = data?.data?.data;

  return (
    <Paper withBorder p="lg">
      <Group>
        <IconMessage size={28} />
        <div>
          <Text size="sm" c="dimmed">Current SMS Balance</Text>
          {isLoading ? (
            <Loader size="sm" />
          ) : balance?.sms_balance !== null && balance?.sms_balance !== undefined ? (
            <Text size="xl" fw={700}>{Number(balance.sms_balance).toLocaleString()} SMS</Text>
          ) : (
            <Text c="dimmed" size="sm">{balance?.error || balance?.message || 'Unable to fetch balance'}</Text>
          )}
        </div>
      </Group>
    </Paper>
  );
}

function BuySection() {
  const queryClient = useQueryClient();
  const [selectedQty, setSelectedQty] = useState<number | string>(100);

  const { data, isLoading } = useQuery({
    queryKey: ['sms-packages'],
    queryFn: getSmsPackages,
  });

  const packages: SmsPackage[] = data?.data?.data || [];

  const checkoutMutation = useMutation({
    mutationFn: (qty: number) => smsCheckout(qty),
    onSuccess: (res) => {
      const redirectUrl = res.data.data.redirect_url;
      if (redirectUrl) {
        window.location.href = redirectUrl;
      } else {
        notifications.show({
          title: 'Checkout Initiated',
          message: 'Redirecting to payment...',
          color: 'blue',
        });
      }
    },
    onError: (err: any) => {
      notifications.show({
        title: 'Checkout Failed',
        message: err.response?.data?.message || 'Failed to initiate payment',
        color: 'red',
      });
    },
  });

  if (isLoading) {
    return <Center py="xl"><Loader /></Center>;
  }

  if (packages.length === 0) {
    return (
      <Alert icon={<IconAlertCircle size={16} />} color="yellow">
        No SMS packages available at the moment. Contact your administrator.
      </Alert>
    );
  }

  return (
    <Paper withBorder p="lg">
      <Text size="lg" fw={600} mb="md">Buy SMS Credits</Text>

      <SimpleGrid cols={{ base: 1, sm: 2, md: 3 }} mb="lg">
        {packages.map((pkg) => (
          <Card key={pkg.id} withBorder padding="md">
            <Text fw={600} size="lg">{pkg.name}</Text>
            <Text c="dimmed" size="sm" mt={4}>
              TZS {pkg.price_per_sms}/SMS
            </Text>
            <Text size="sm" mt={4}>
              {pkg.min_quantity.toLocaleString()}
              {pkg.max_quantity ? ` – ${pkg.max_quantity.toLocaleString()}` : '+'} SMS
            </Text>
            <Button
              fullWidth
              mt="md"
              variant="light"
              onClick={() => setSelectedQty(pkg.min_quantity)}
            >
              Select
            </Button>
          </Card>
        ))}
      </SimpleGrid>

      <Group align="flex-end">
        <NumberInput
          label="SMS Quantity"
          value={selectedQty}
          onChange={setSelectedQty}
          min={100}
          step={100}
          w={200}
        />
        <Button
          loading={checkoutMutation.isPending}
          onClick={() => {
            const qty = Number(selectedQty);
            if (qty < 100) {
              notifications.show({ title: 'Error', message: 'Minimum 100 SMS', color: 'red' });
              return;
            }
            checkoutMutation.mutate(qty);
          }}
        >
          Buy Now via Pesapal
        </Button>
      </Group>
    </Paper>
  );
}

function PurchaseHistory() {
  const [page, setPage] = useState(1);

  const { data, isLoading } = useQuery({
    queryKey: ['sms-purchases', page],
    queryFn: () => getSmsPurchaseHistory({ page }),
  });

  const purchases: SmsPurchase[] = data?.data?.data || [];
  const lastPage: number = data?.data?.last_page || 1;

  return (
    <Paper withBorder p="lg">
      <Text size="lg" fw={600} mb="md">Purchase History</Text>

      {isLoading ? (
        <Center py="xl"><Loader /></Center>
      ) : (
        <Table striped highlightOnHover>
          <Table.Thead>
            <Table.Tr>
              <Table.Th>Package</Table.Th>
              <Table.Th>Quantity</Table.Th>
              <Table.Th>Amount (TZS)</Table.Th>
              <Table.Th>Status</Table.Th>
              <Table.Th>Payment Method</Table.Th>
              <Table.Th>Date</Table.Th>
            </Table.Tr>
          </Table.Thead>
          <Table.Tbody>
            {purchases.map((p) => (
              <Table.Tr key={p.id}>
                <Table.Td fw={500}>{p.package_name}</Table.Td>
                <Table.Td>{p.sms_quantity.toLocaleString()}</Table.Td>
                <Table.Td>{Number(p.total_amount).toLocaleString()}</Table.Td>
                <Table.Td>
                  <Badge color={statusColors[p.status]} variant="light">
                    {p.status}
                  </Badge>
                </Table.Td>
                <Table.Td>{p.payment_method_used || '—'}</Table.Td>
                <Table.Td>{new Date(p.created_at).toLocaleDateString()}</Table.Td>
              </Table.Tr>
            ))}
            {purchases.length === 0 && (
              <Table.Tr>
                <Table.Td colSpan={6}>
                  <Text ta="center" c="dimmed" py="md">No purchases yet</Text>
                </Table.Td>
              </Table.Tr>
            )}
          </Table.Tbody>
        </Table>
      )}

      {lastPage > 1 && (
        <Group justify="center" mt="md">
          <Pagination total={lastPage} value={page} onChange={setPage} />
        </Group>
      )}
    </Paper>
  );
}
