import { useState, useRef } from 'react';
import {
  Title, Text, Card, SimpleGrid, Stack, Button, Group, Badge,
  Container, Paper, ThemeIcon, List, Center, Loader, Alert, Divider,
  FileButton,
} from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { useQuery, useMutation } from '@tanstack/react-query';
import {
  IconCrown, IconCheck, IconLogout, IconCreditCard, IconBuildingBank,
  IconDownload, IconUpload, IconFileInvoice, IconAlertCircle,
} from '@tabler/icons-react';
import { useAuth } from '../context/AuthContext';
import {
  getSubscriptionPlans, subscriptionCheckout, downloadSubscriptionInvoice,
  uploadPaymentProof, SubscriptionPlan, CheckoutResponse,
} from '../api/subscription';
import { useNavigate } from 'react-router-dom';

export default function SubscriptionExpired() {
  const { user, logout, subscriptionStatus, daysRemaining } = useAuth();
  const navigate = useNavigate();
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

  const bankTransferMutation = useMutation({
    mutationFn: (planId: string) => subscriptionCheckout(planId, 'bank_transfer'),
    onSuccess: (res) => {
      setBankTransferResult(res.data.data);
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

  const handleLogout = async () => {
    await logout();
    navigate('/login');
  };

  const isCheckingOut = pesapalMutation.isPending || bankTransferMutation.isPending;

  return (
    <Container size="lg" py="xl">
      <Stack align="center" gap="xl">
        <Group justify="space-between" w="100%">
          <div>
            <Title order={2}>MoBilling</Title>
            <Text c="dimmed" size="sm">{user?.tenant?.name}</Text>
          </div>
          <Button variant="subtle" color="gray" leftSection={<IconLogout size={16} />} onClick={handleLogout}>
            Logout
          </Button>
        </Group>

        <Paper withBorder p="xl" radius="md" w="100%" ta="center">
          <ThemeIcon size={60} radius="xl" color="orange" variant="light" mx="auto" mb="md">
            <IconCrown size={32} />
          </ThemeIcon>
          <Title order={3} mb="xs">
            {subscriptionStatus === 'trial' ? 'Your Trial is Ending Soon' : 'Your Subscription Has Expired'}
          </Title>
          <Text c="dimmed" maw={500} mx="auto">
            {subscriptionStatus === 'trial'
              ? `You have ${daysRemaining} day(s) left in your free trial. Subscribe now to keep uninterrupted access.`
              : 'Choose a plan below to restore access to MoBilling and continue managing your business.'}
          </Text>
        </Paper>

        {bankTransferResult && (
          <BankTransferInfo
            result={bankTransferResult}
            onDismiss={() => setBankTransferResult(null)}
          />
        )}

        {isLoading ? (
          <Center py="xl"><Loader /></Center>
        ) : plans.length === 0 ? (
          <Text c="dimmed">No plans available. Please contact support.</Text>
        ) : (
          <SimpleGrid cols={{ base: 1, sm: 2, md: 3 }} w="100%">
            {plans.map((plan) => (
              <Card key={plan.id} withBorder padding="xl" radius="md">
                <Stack gap="md">
                  <div>
                    <Text size="xl" fw={700}>{plan.name}</Text>
                    {plan.description && (
                      <Text size="sm" c="dimmed" mt={4}>{plan.description}</Text>
                    )}
                  </div>

                  <div>
                    <Group gap={4} align="baseline">
                      <Text size="xl" fw={700}>TZS {Number(plan.price).toLocaleString()}</Text>
                      <Text size="sm" c="dimmed">/ {plan.billing_cycle_days} days</Text>
                    </Group>
                  </div>

                  {plan.features && plan.features.length > 0 && (
                    <List
                      spacing="xs"
                      size="sm"
                      icon={<ThemeIcon size={20} radius="xl" color="green" variant="light"><IconCheck size={12} /></ThemeIcon>}
                    >
                      {plan.features.map((feature, i) => (
                        <List.Item key={i}>{feature}</List.Item>
                      ))}
                    </List>
                  )}

                  <Stack gap="xs">
                    <Button
                      fullWidth
                      size="md"
                      loading={isCheckingOut}
                      onClick={() => pesapalMutation.mutate(plan.id)}
                      leftSection={<IconCreditCard size={18} />}
                    >
                      Pay with Pesapal
                    </Button>
                    <Button
                      fullWidth
                      size="md"
                      variant="light"
                      loading={isCheckingOut}
                      onClick={() => bankTransferMutation.mutate(plan.id)}
                      leftSection={<IconBuildingBank size={18} />}
                    >
                      Pay via Bank Transfer
                    </Button>
                  </Stack>
                </Stack>
              </Card>
            ))}
          </SimpleGrid>
        )}
      </Stack>
    </Container>
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
      w="100%"
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
