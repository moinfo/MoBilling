import { useState, useRef } from 'react';
import {
  Title, Text, Paper, Group, Badge, Card, SimpleGrid, Stack,
  Button, Table, Pagination, Loader, Center, ThemeIcon, List, rem,
  Alert, Divider, FileButton,
} from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  IconCreditCard, IconCheck, IconCrown, IconCalendar, IconClock,
  IconBuildingBank, IconDownload, IconUpload, IconAlertCircle, IconFileInvoice,
} from '@tabler/icons-react';
import { useAuth } from '../context/AuthContext';
import {
  getSubscriptionPlans, getSubscriptionCurrent, subscriptionCheckout,
  getSubscriptionHistory, downloadSubscriptionInvoice, uploadPaymentProof,
  SubscriptionPlan, TenantSubscription, CheckoutResponse, BankDetails,
} from '../api/subscription';

const statusColors: Record<string, string> = {
  trial: 'blue',
  subscribed: 'green',
  expired: 'red',
  deactivated: 'gray',
  pending: 'yellow',
  active: 'green',
  cancelled: 'gray',
};

const planColors = ['blue', 'teal', 'violet', 'orange'];

export default function Subscription() {
  return (
    <Stack gap="xl">
      <div>
        <Title order={2} mb={4}>Subscription</Title>
        <Text c="dimmed">Manage your subscription plan and billing.</Text>
      </div>
      <CurrentStatus />
      <PlansSection />
      <SubscriptionHistory />
    </Stack>
  );
}

function CurrentStatus() {
  const { subscriptionStatus, daysRemaining } = useAuth();

  const { data, isLoading } = useQuery({
    queryKey: ['subscription-current'],
    queryFn: getSubscriptionCurrent,
  });

  const current = data?.data?.data;
  const color = statusColors[subscriptionStatus || 'expired'];
  const daysColor = daysRemaining <= 0 ? 'red' : daysRemaining <= 7 ? 'orange' : 'green';

  return (
    <Paper withBorder p="lg" radius="md">
      <Group gap="md" align="flex-start">
        <ThemeIcon size={48} radius="xl" color={color} variant="light">
          <IconCrown size={24} />
        </ThemeIcon>
        <Stack gap={4} style={{ flex: 1 }}>
          <Text size="sm" c="dimmed">Current Status</Text>
          {isLoading ? (
            <Loader size="sm" />
          ) : (
            <>
              <Group gap="sm">
                <Badge color={color} variant="light" size="lg">
                  {subscriptionStatus === 'trial' ? 'Free Trial' :
                   subscriptionStatus === 'subscribed' ? 'Active Subscription' :
                   subscriptionStatus === 'expired' ? 'Expired' : 'Deactivated'}
                </Badge>
                {current?.active_subscription?.plan && (
                  <Badge variant="outline" size="lg">
                    {current.active_subscription.plan.name}
                  </Badge>
                )}
              </Group>

              {(subscriptionStatus === 'trial' || subscriptionStatus === 'subscribed') && (
                <Group gap="xl" mt="sm">
                  <Group gap={6}>
                    <IconClock size={14} color="var(--mantine-color-dimmed)" />
                    <Text size="sm">
                      <Text span fw={600} c={daysColor}>{daysRemaining}</Text>
                      <Text span c="dimmed"> days remaining</Text>
                    </Text>
                  </Group>

                  {current?.active_subscription?.ends_at && (
                    <Group gap={6}>
                      <IconCalendar size={14} color="var(--mantine-color-dimmed)" />
                      <Text size="sm" c="dimmed">
                        Renews {new Date(current.active_subscription.ends_at).toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' })}
                      </Text>
                    </Group>
                  )}

                  {current?.trial_ends_at && subscriptionStatus === 'trial' && (
                    <Group gap={6}>
                      <IconCalendar size={14} color="var(--mantine-color-dimmed)" />
                      <Text size="sm" c="dimmed">
                        Trial ends {new Date(current.trial_ends_at).toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' })}
                      </Text>
                    </Group>
                  )}
                </Group>
              )}

              {subscriptionStatus === 'expired' && (
                <Text size="sm" c="red" mt="xs">
                  Your subscription has expired. Choose a plan below to restore access.
                </Text>
              )}
            </>
          )}
        </Stack>
      </Group>
    </Paper>
  );
}

function PlansSection() {
  const { subscriptionStatus } = useAuth();
  const queryClient = useQueryClient();
  const [bankTransferResult, setBankTransferResult] = useState<CheckoutResponse | null>(null);

  const { data, isLoading } = useQuery({
    queryKey: ['subscription-plans'],
    queryFn: getSubscriptionPlans,
  });

  const plans: SubscriptionPlan[] = data?.data?.data || [];

  const pesapalMutation = useMutation({
    mutationFn: (planId: string) => subscriptionCheckout(planId, 'pesapal'),
    onSuccess: (res) => {
      const redirectUrl = res.data.data.redirect_url;
      if (redirectUrl) {
        window.location.href = redirectUrl;
      } else {
        notifications.show({ title: 'Checkout Initiated', message: 'Redirecting to payment...', color: 'blue' });
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

  const bankTransferMutation = useMutation({
    mutationFn: (planId: string) => subscriptionCheckout(planId, 'bank_transfer'),
    onSuccess: (res) => {
      setBankTransferResult(res.data.data);
      queryClient.invalidateQueries({ queryKey: ['subscription-history'] });
      notifications.show({
        title: 'Invoice Generated',
        message: 'Your subscription invoice has been created. Please pay via bank transfer.',
        color: 'green',
      });
    },
    onError: (err: any) => {
      notifications.show({
        title: 'Failed',
        message: err.response?.data?.message || 'Failed to generate invoice',
        color: 'red',
      });
    },
  });

  const isExpiredOrTrial = subscriptionStatus === 'expired' || subscriptionStatus === 'trial';
  const isCheckingOut = pesapalMutation.isPending || bankTransferMutation.isPending;

  return (
    <Paper withBorder p="lg" radius="md">
      <Group justify="space-between" mb="lg">
        <div>
          <Text size="lg" fw={600}>
            {isExpiredOrTrial ? 'Choose a Plan' : 'Available Plans'}
          </Text>
          <Text size="sm" c="dimmed">
            {isExpiredOrTrial
              ? 'Subscribe to unlock full access to MoBilling.'
              : 'Upgrade or renew your subscription.'}
          </Text>
        </div>
      </Group>

      {bankTransferResult && (
        <BankTransferInfo
          result={bankTransferResult}
          onDismiss={() => setBankTransferResult(null)}
        />
      )}

      {isLoading ? (
        <Center py="xl"><Loader /></Center>
      ) : plans.length === 0 ? (
        <Paper withBorder p="xl" radius="md" ta="center" bg="var(--mantine-color-body)">
          <ThemeIcon size={48} radius="xl" color="gray" variant="light" mx="auto" mb="md">
            <IconCreditCard size={24} />
          </ThemeIcon>
          <Text fw={500} mb={4}>No plans available yet</Text>
          <Text size="sm" c="dimmed">
            Subscription plans haven't been configured. Please contact your administrator.
          </Text>
        </Paper>
      ) : (
        <SimpleGrid cols={{ base: 1, sm: 2, md: plans.length >= 4 ? 4 : plans.length }}>
          {plans.map((plan, i) => {
            const color = planColors[i % planColors.length];
            return (
              <Card
                key={plan.id}
                withBorder
                padding="xl"
                radius="md"
                style={{
                  borderTop: `3px solid var(--mantine-color-${color}-6)`,
                }}
              >
                <Stack gap="md" justify="space-between" h="100%">
                  <div>
                    <Text fw={700} size="lg">{plan.name}</Text>
                    {plan.description && (
                      <Text size="sm" c="dimmed" mt={4}>{plan.description}</Text>
                    )}

                    <Group gap={4} align="baseline" mt="md">
                      <Text size={rem(32)} fw={800} lh={1}>
                        TZS {Number(plan.price).toLocaleString()}
                      </Text>
                    </Group>
                    <Text size="sm" c="dimmed">
                      per {plan.billing_cycle_days} days
                    </Text>

                    {plan.features && plan.features.length > 0 && (
                      <List
                        spacing={6}
                        size="sm"
                        mt="md"
                        icon={
                          <ThemeIcon size={18} radius="xl" color={color} variant="light">
                            <IconCheck size={11} />
                          </ThemeIcon>
                        }
                      >
                        {plan.features.map((f, fi) => <List.Item key={fi}>{f}</List.Item>)}
                      </List>
                    )}
                  </div>

                  <Button
                    fullWidth
                    size="md"
                    color={color}
                    loading={isCheckingOut}
                    onClick={() => pesapalMutation.mutate(plan.id)}
                    leftSection={<IconCreditCard size={18} />}
                  >
                    Pay with Pesapal
                  </Button>
                </Stack>
              </Card>
            );
          })}
        </SimpleGrid>
      )}
    </Paper>
  );
}

function BankTransferInfo({
  result,
  onDismiss,
}: {
  result: CheckoutResponse;
  onDismiss: () => void;
}) {
  const resetRef = useRef<() => void>(null);

  const invoiceDownload = useMutation({
    mutationFn: () => downloadSubscriptionInvoice(result.subscription_id),
    onSuccess: (res) => {
      const url = window.URL.createObjectURL(new Blob([res.data]));
      const link = document.createElement('a');
      link.href = url;
      link.setAttribute('download', `invoice-${result.invoice_number}.pdf`);
      document.body.appendChild(link);
      link.click();
      link.remove();
      window.URL.revokeObjectURL(url);
    },
    onError: () => {
      notifications.show({ title: 'Error', message: 'Failed to download invoice', color: 'red' });
    },
  });

  const proofUpload = useMutation({
    mutationFn: (file: File) => uploadPaymentProof(result.subscription_id, file),
    onSuccess: () => {
      notifications.show({ title: 'Uploaded', message: 'Payment proof uploaded successfully', color: 'green' });
      resetRef.current?.();
    },
    onError: (err: any) => {
      notifications.show({
        title: 'Upload Failed',
        message: err.response?.data?.message || 'Failed to upload proof',
        color: 'red',
      });
    },
  });

  return (
    <Alert
      icon={<IconFileInvoice size={20} />}
      title="Bank Transfer Invoice Created"
      color="blue"
      mb="lg"
      withCloseButton
      onClose={onDismiss}
    >
      <Stack gap="sm">
        <Group gap="xl">
          <div>
            <Text size="xs" c="dimmed">Invoice Number</Text>
            <Text fw={600}>{result.invoice_number}</Text>
          </div>
          <div>
            <Text size="xs" c="dimmed">Amount</Text>
            <Text fw={600}>TZS {Number(result.amount).toLocaleString()}</Text>
          </div>
          <div>
            <Text size="xs" c="dimmed">Due Date</Text>
            <Text fw={600}>
              {result.invoice_due_date
                ? new Date(result.invoice_due_date).toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' })
                : '—'}
            </Text>
          </div>
          <Badge color="yellow" variant="light" size="lg">Pending Payment</Badge>
        </Group>

        {result.bank_details && (
          <>
            <Divider my="xs" />
            <Text size="sm" fw={600}>Bank Details</Text>
            <Group gap="xl">
              <div>
                <Text size="xs" c="dimmed">Bank</Text>
                <Text size="sm">{result.bank_details.bank_name}</Text>
              </div>
              <div>
                <Text size="xs" c="dimmed">Account Name</Text>
                <Text size="sm">{result.bank_details.bank_account_name}</Text>
              </div>
              <div>
                <Text size="xs" c="dimmed">Account Number</Text>
                <Text size="sm" fw={600}>{result.bank_details.bank_account_number}</Text>
              </div>
              <div>
                <Text size="xs" c="dimmed">Branch</Text>
                <Text size="sm">{result.bank_details.bank_branch}</Text>
              </div>
            </Group>
            {result.bank_details.payment_instructions && (
              <Alert color="yellow" variant="light" icon={<IconAlertCircle size={16} />}>
                {result.bank_details.payment_instructions}
              </Alert>
            )}
          </>
        )}

        <Group gap="sm" mt="xs">
          <Button
            size="sm"
            variant="light"
            leftSection={<IconDownload size={16} />}
            loading={invoiceDownload.isPending}
            onClick={() => invoiceDownload.mutate()}
          >
            Download Invoice
          </Button>
          <FileButton
            resetRef={resetRef}
            onChange={(file) => file && proofUpload.mutate(file)}
            accept="application/pdf,image/jpeg,image/png"
          >
            {(props) => (
              <Button
                {...props}
                size="sm"
                variant="subtle"
                leftSection={<IconUpload size={16} />}
                loading={proofUpload.isPending}
              >
                Upload Payment Proof
              </Button>
            )}
          </FileButton>
        </Group>
      </Stack>
    </Alert>
  );
}

function SubscriptionHistory() {
  const [page, setPage] = useState(1);

  const { data, isLoading } = useQuery({
    queryKey: ['subscription-history', page],
    queryFn: () => getSubscriptionHistory({ page }),
  });

  const subscriptions: TenantSubscription[] = data?.data?.data || [];
  const lastPage: number = data?.data?.last_page || 1;

  const handleDownloadInvoice = async (sub: TenantSubscription) => {
    try {
      const res = await downloadSubscriptionInvoice(sub.id);
      const url = window.URL.createObjectURL(new Blob([res.data]));
      const link = document.createElement('a');
      link.href = url;
      link.setAttribute('download', `invoice-${sub.invoice_number || sub.id}.pdf`);
      document.body.appendChild(link);
      link.click();
      link.remove();
      window.URL.revokeObjectURL(url);
    } catch {
      notifications.show({ title: 'Error', message: 'Failed to download invoice', color: 'red' });
    }
  };

  return (
    <Paper withBorder p="lg" radius="md">
      <Text size="lg" fw={600} mb="md">Subscription History</Text>
      {isLoading ? (
        <Center py="xl"><Loader /></Center>
      ) : (
        <Table striped highlightOnHover>
          <Table.Thead>
            <Table.Tr>
              <Table.Th>Plan</Table.Th>
              <Table.Th>Invoice</Table.Th>
              <Table.Th>Amount (TZS)</Table.Th>
              <Table.Th>Status</Table.Th>
              <Table.Th>Period</Table.Th>
              <Table.Th>Payment Method</Table.Th>
              <Table.Th>Date</Table.Th>
              <Table.Th></Table.Th>
            </Table.Tr>
          </Table.Thead>
          <Table.Tbody>
            {subscriptions.map((sub) => (
              <Table.Tr key={sub.id}>
                <Table.Td fw={500}>{sub.plan?.name || '—'}</Table.Td>
                <Table.Td>
                  <Text size="xs" ff="monospace">{sub.invoice_number || '—'}</Text>
                </Table.Td>
                <Table.Td>{Number(sub.amount_paid).toLocaleString()}</Table.Td>
                <Table.Td>
                  <Badge color={statusColors[sub.status]} variant="light">
                    {sub.status}
                  </Badge>
                </Table.Td>
                <Table.Td>
                  {sub.starts_at && sub.ends_at
                    ? `${new Date(sub.starts_at).toLocaleDateString('en-GB', { day: '2-digit', month: 'short' })} – ${new Date(sub.ends_at).toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' })}`
                    : '—'}
                </Table.Td>
                <Table.Td>
                  {sub.payment_method === 'bank_transfer' ? 'Bank Transfer' :
                   sub.payment_method === 'pesapal' ? 'Pesapal' :
                   sub.payment_method_used || '—'}
                </Table.Td>
                <Table.Td>{new Date(sub.created_at).toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' })}</Table.Td>
                <Table.Td>
                  {sub.invoice_number && (
                    <Button
                      size="compact-xs"
                      variant="subtle"
                      leftSection={<IconDownload size={14} />}
                      onClick={() => handleDownloadInvoice(sub)}
                    >
                      Invoice
                    </Button>
                  )}
                </Table.Td>
              </Table.Tr>
            ))}
            {subscriptions.length === 0 && (
              <Table.Tr>
                <Table.Td colSpan={8}>
                  <Text ta="center" c="dimmed" py="md">No subscriptions yet</Text>
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
