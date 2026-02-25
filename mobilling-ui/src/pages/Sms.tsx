import { useState } from 'react';
import {
  Title, Text, Paper, Group, Badge, Card, SimpleGrid, Stack,
  NumberInput, Button, Table, Pagination, Loader, Center, Alert,
  ThemeIcon, rem,
} from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { useQuery, useMutation } from '@tanstack/react-query';
import {
  IconMessage, IconAlertCircle, IconCheck, IconCreditCard,
  IconSend, IconReceipt, IconFileInvoice, IconRefresh,
} from '@tabler/icons-react';
import {
  getSmsPackages, getSmsBalance, smsCheckout, getSmsPurchaseHistory,
  requestSmsActivation, retrySmsPurchase, downloadSmsReceipt, downloadSmsInvoice,
  SmsPackage, SmsPurchase,
} from '../api/sms';

const statusColors: Record<string, string> = {
  pending: 'yellow',
  completed: 'green',
  failed: 'red',
};

const tierColors = ['blue', 'teal', 'violet', 'orange', 'pink'];

export default function Sms() {
  const { data: balanceData, isLoading: balanceLoading } = useQuery({
    queryKey: ['sms-balance'],
    queryFn: getSmsBalance,
  });

  const balance = balanceData?.data?.data;
  const smsConfigured = !balanceLoading && balance?.sms_balance !== null && balance?.sms_balance !== undefined;

  return (
    <Stack gap="xl">
      <div>
        <Title order={2} mb={4}>SMS</Title>
        <Text c="dimmed">View your SMS balance, buy credits, and track purchases.</Text>
      </div>

      <BalanceCard balance={balance} isLoading={balanceLoading} />

      {!balanceLoading && !smsConfigured && <SmsNotConfigured />}

      <BuySection smsConfigured={smsConfigured} />

      {smsConfigured && <PurchaseHistory />}
    </Stack>
  );
}

function BalanceCard({ balance, isLoading }: { balance: any; isLoading: boolean }) {
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
            <Text c="dimmed" size="sm">SMS not configured for this tenant</Text>
          )}
        </div>
      </Group>
    </Paper>
  );
}

function SmsNotConfigured() {
  const requestMutation = useMutation({
    mutationFn: requestSmsActivation,
    onSuccess: (res) => {
      notifications.show({
        title: 'Request sent',
        message: res.data.message,
        color: 'green',
      });
    },
    onError: (err: any) => {
      notifications.show({
        title: 'Error',
        message: err.response?.data?.message || 'Failed to send request',
        color: 'red',
      });
    },
  });

  return (
    <Alert icon={<IconAlertCircle size={16} />} color="yellow" title="SMS not configured">
      <Stack gap="sm">
        <Text size="sm">
          SMS has not been enabled for your account yet. Request activation and the administrator will configure it for you.
        </Text>
        <div>
          <Button
            size="sm"
            variant="filled"
            color="yellow"
            leftSection={<IconSend size={16} />}
            loading={requestMutation.isPending}
            onClick={() => requestMutation.mutate()}
          >
            Request SMS Activation
          </Button>
        </div>
      </Stack>
    </Alert>
  );
}

function BuySection({ smsConfigured }: { smsConfigured: boolean }) {
  const [selectedPkg, setSelectedPkg] = useState<string | null>(null);
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

  const handleSelect = (pkg: SmsPackage) => {
    setSelectedPkg(pkg.id);
    setSelectedQty(pkg.min_quantity);
  };

  // Compute cost for selected quantity
  const activePkg = packages.find(p => p.id === selectedPkg);
  const qty = Number(selectedQty) || 0;
  const estimatedCost = activePkg ? qty * Number(activePkg.price_per_sms) : 0;

  return (
    <Paper withBorder p="lg">
      <Text size="lg" fw={600} mb="md">Buy SMS Credits</Text>

      <SimpleGrid cols={{ base: 1, sm: 2, md: packages.length >= 4 ? 4 : 3 }} mb="xl">
        {packages.map((pkg, i) => {
          const isSelected = selectedPkg === pkg.id;
          const color = tierColors[i % tierColors.length];
          return (
            <Card
              key={pkg.id}
              withBorder
              padding="lg"
              radius="md"
              style={{
                cursor: 'pointer',
                borderColor: isSelected ? `var(--mantine-color-${color}-6)` : undefined,
                borderWidth: isSelected ? 2 : 1,
                transition: 'border-color 150ms ease, box-shadow 150ms ease',
                boxShadow: isSelected ? `0 0 0 1px var(--mantine-color-${color}-6)` : undefined,
              }}
              onClick={() => handleSelect(pkg)}
            >
              <Group justify="space-between" mb="xs">
                <Text fw={700} size="md">{pkg.name}</Text>
                {isSelected && (
                  <ThemeIcon color={color} size="sm" radius="xl">
                    <IconCheck size={12} />
                  </ThemeIcon>
                )}
              </Group>

              <Text size={rem(28)} fw={800} c={color} lh={1.2}>
                TZS {Number(pkg.price_per_sms).toFixed(0)}
              </Text>
              <Text size="xs" c="dimmed" mb="sm">per SMS</Text>

              <Badge color={color} variant="light" size="sm">
                {pkg.min_quantity.toLocaleString()}
                {pkg.max_quantity ? ` \u2013 ${pkg.max_quantity.toLocaleString()}` : '+'} SMS
              </Badge>
            </Card>
          );
        })}
      </SimpleGrid>

      {smsConfigured && (
        <Paper withBorder p="md" radius="md" bg="var(--mantine-color-body)">
          <Group align="flex-end" gap="md">
            <NumberInput
              label="SMS Quantity"
              value={selectedQty}
              onChange={setSelectedQty}
              min={100}
              step={100}
              w={160}
            />
            {estimatedCost > 0 && (
              <Stack gap={0} pb={2}>
                <Text size="xs" c="dimmed">Estimated Cost</Text>
                <Text fw={700} size="lg">TZS {estimatedCost.toLocaleString()}</Text>
              </Stack>
            )}
            <Button
              size="md"
              leftSection={<IconCreditCard size={18} />}
              loading={checkoutMutation.isPending}
              onClick={() => {
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
      )}
    </Paper>
  );
}

function PurchaseHistory() {
  const [page, setPage] = useState(1);
  const [loadingAction, setLoadingAction] = useState<string | null>(null);

  const { data, isLoading } = useQuery({
    queryKey: ['sms-purchases', page],
    queryFn: () => getSmsPurchaseHistory({ page }),
  });

  const purchases: SmsPurchase[] = data?.data?.data || [];
  const lastPage: number = data?.data?.last_page || 1;

  const handleRetry = async (purchase: SmsPurchase) => {
    setLoadingAction(`retry-${purchase.id}`);
    try {
      const res = await retrySmsPurchase(purchase.id);
      const url = res.data.data.redirect_url;
      if (url) {
        window.location.href = url;
      } else {
        notifications.show({ title: 'Error', message: 'No redirect URL received.', color: 'red' });
      }
    } catch (err: any) {
      notifications.show({
        title: 'Retry Failed',
        message: err.response?.data?.message || 'Failed to retry payment.',
        color: 'red',
      });
    } finally {
      setLoadingAction(null);
    }
  };

  const handleDownload = async (purchaseId: string, type: 'receipt' | 'invoice', label: string) => {
    setLoadingAction(`${type}-${purchaseId}`);
    try {
      const res = type === 'receipt'
        ? await downloadSmsReceipt(purchaseId)
        : await downloadSmsInvoice(purchaseId);
      const url = window.URL.createObjectURL(new Blob([res.data]));
      const link = document.createElement('a');
      link.href = url;
      link.setAttribute('download', `sms-${type}-${purchaseId}.pdf`);
      document.body.appendChild(link);
      link.click();
      link.remove();
      window.URL.revokeObjectURL(url);
    } catch {
      notifications.show({ title: 'Download Failed', message: `Could not download ${label}.`, color: 'red' });
    } finally {
      setLoadingAction(null);
    }
  };

  return (
    <Paper withBorder p="lg">
      <Text size="lg" fw={600} mb="md">Purchase History</Text>

      {isLoading ? (
        <Center py="xl"><Loader /></Center>
      ) : (
        <Table.ScrollContainer minWidth={750}>
          <Table striped highlightOnHover>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Package</Table.Th>
                <Table.Th>Quantity</Table.Th>
                <Table.Th>Amount (TZS)</Table.Th>
                <Table.Th>Status</Table.Th>
                <Table.Th>Payment Method</Table.Th>
                <Table.Th>Date</Table.Th>
                <Table.Th>Actions</Table.Th>
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
                <Table.Td>
                  <Group gap="xs" wrap="nowrap">
                    {(p.status === 'pending' || p.status === 'failed') && (
                      <Button
                        size="compact-xs"
                        variant="light"
                        color="blue"
                        leftSection={<IconRefresh size={14} />}
                        loading={loadingAction === `retry-${p.id}`}
                        onClick={() => handleRetry(p)}
                      >
                        Pay Again
                      </Button>
                    )}
                    {p.status === 'completed' && (
                      <Button
                        size="compact-xs"
                        variant="light"
                        color="green"
                        leftSection={<IconReceipt size={14} />}
                        loading={loadingAction === `receipt-${p.id}`}
                        onClick={() => handleDownload(p.id, 'receipt', 'receipt')}
                      >
                        Receipt
                      </Button>
                    )}
                    <Button
                      size="compact-xs"
                      variant="light"
                      color="gray"
                      leftSection={<IconFileInvoice size={14} />}
                      loading={loadingAction === `invoice-${p.id}`}
                      onClick={() => handleDownload(p.id, 'invoice', 'invoice')}
                    >
                      Invoice
                    </Button>
                  </Group>
                </Table.Td>
              </Table.Tr>
            ))}
            {purchases.length === 0 && (
              <Table.Tr>
                <Table.Td colSpan={7}>
                  <Text ta="center" c="dimmed" py="md">No purchases yet</Text>
                </Table.Td>
              </Table.Tr>
            )}
            </Table.Tbody>
          </Table>
        </Table.ScrollContainer>
      )}

      {lastPage > 1 && (
        <Group justify="center" mt="md">
          <Pagination total={lastPage} value={page} onChange={setPage} />
        </Group>
      )}
    </Paper>
  );
}
