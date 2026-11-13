import { useEffect, useState } from 'react';
import {
  Container, Paper, Title, Text, Stack, TextInput, Select, Button, Group, Center, Loader,
  Alert, Image, Radio, Anchor,
} from '@mantine/core';
import { useForm } from '@mantine/form';
import { useSearchParams, Link } from 'react-router-dom';
import { useQuery } from '@tanstack/react-query';
import { IconAlertTriangle, IconCreditCard } from '@tabler/icons-react';
import { getPublicLicensePlans, PublicLicensePlan } from '../api/subscription';
import { checkoutLicensePurchase } from '../api/license';

const PERIOD_LABELS: Record<string, string> = {
  monthly: 'Monthly', quarterly: 'Quarterly', semi_annual: 'Semi-Annual',
  annual: 'Annual', perpetual: 'Perpetual (one-time)',
};

function periodsFor(plan: PublicLicensePlan) {
  return (['monthly', 'quarterly', 'semi_annual', 'annual', 'perpetual'] as const)
    .filter((p) => plan[`${p}_price` as const] !== null);
}

export default function BuyLicense() {
  const [searchParams] = useSearchParams();
  const preselect = searchParams.get('product');
  const { data, isLoading } = useQuery({ queryKey: ['public-license-plans'], queryFn: getPublicLicensePlans });
  const plans = data?.data?.data || [];

  const [errorMsg, setErrorMsg] = useState('');
  const [loading, setLoading] = useState(false);
  const [issuedLicense, setIssuedLicense] = useState<{ license_key: string } | null>(null);

  const form = useForm({
    initialValues: {
      customer_name: '', customer_email: '', customer_phone: '',
      product: preselect || '', billing_period: '',
      payment_mode: 'self_managed' as 'self_managed' | 'platform_collected',
    },
    validate: {
      customer_name: (v) => (v.trim() ? null : 'Required'),
      customer_email: (v) => (/^\S+@\S+\.\S+$/.test(v) ? null : 'Valid email required'),
      product: (v) => (v ? null : 'Choose a package'),
      billing_period: (v, values) => (values.product === 'wifi_hotspot' && values.payment_mode === 'platform_collected'
        ? null : (v ? null : 'Choose a billing period')),
    },
  });

  const isWifiHotspot = form.values.product === 'wifi_hotspot';
  const isFreePlatformCollected = isWifiHotspot && form.values.payment_mode === 'platform_collected';

  useEffect(() => {
    if (!form.values.product && plans.length > 0) {
      form.setFieldValue('product', preselect && plans.some((p) => p.product === preselect) ? preselect : plans[0].product);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [plans]);

  const selectedPlan = plans.find((p) => p.product === form.values.product) || null;
  const availablePeriods = selectedPlan ? periodsFor(selectedPlan) : [];
  const selectedPrice = selectedPlan && form.values.billing_period
    ? selectedPlan[`${form.values.billing_period}_price` as keyof PublicLicensePlan]
    : null;

  const submit = async (values: typeof form.values) => {
    setLoading(true);
    setErrorMsg('');
    try {
      const res = await checkoutLicensePurchase({
        customer_name: values.customer_name,
        customer_email: values.customer_email,
        customer_phone: values.customer_phone || undefined,
        product: values.product as 'lite' | 'reseller' | 'general' | 'wifi_hotspot',
        billing_period: (values.billing_period || 'perpetual') as 'monthly' | 'quarterly' | 'semi_annual' | 'annual' | 'perpetual',
        payment_mode: values.product === 'wifi_hotspot' ? values.payment_mode : undefined,
      });
      if (res.data.data.status === 'completed' && res.data.data.license) {
        setIssuedLicense(res.data.data.license);
        setLoading(false);
        return;
      }
      const redirectUrl = res.data.data.redirect_url;
      if (redirectUrl) {
        window.location.href = redirectUrl;
      } else {
        setErrorMsg('Could not start payment. Please try again.');
        setLoading(false);
      }
    } catch (err: any) {
      setErrorMsg(err.response?.data?.message || 'Could not start payment. Please try again.');
      setLoading(false);
    }
  };

  if (issuedLicense) {
    return (
      <Container size="sm" py={{ base: 32, sm: 64 }}>
        <Paper withBorder p={{ base: 'md', sm: 'xl' }} radius="md">
          <Stack align="center">
            <Title order={3} ta="center">Your WiFi Hotspot license is ready</Title>
            <Text c="dimmed" ta="center" size="sm" maw={420}>
              This license is free — MoBilling collects your hotspot customers' voucher payments and keeps a
              small commission per transaction instead of charging a monthly fee. Save your license key below.
            </Text>
            <Paper withBorder p="md" radius="md" bg="var(--mantine-color-default-hover)">
              <Text ff="monospace" fw={700} size="lg" ta="center">{issuedLicense.license_key}</Text>
            </Paper>
            <Text size="sm" ta="center">
              Follow our{' '}
              <Anchor component={Link} to="/license-agreement" target="_blank">install guide</Anchor> to set it up
              on your own server.
            </Text>
          </Stack>
        </Paper>
      </Container>
    );
  }

  return (
    <Container size="sm" py={{ base: 32, sm: 64 }}>
      <Stack align="center" mb="xl">
        <Image src="/moinfotech-logo.png" h={40} w="auto" alt="MoBilling" />
        <Title order={2} ta="center">Buy a Self-Hosted License</Title>
        <Text c="dimmed" ta="center" size="sm" maw={480}>
          Pay once for the period you choose, get your license key immediately, then follow our{' '}
          <Anchor component={Link} to="/license-agreement" target="_blank">install guide</Anchor> to set it up on
          your own server.
        </Text>
      </Stack>

      <Paper withBorder p={{ base: 'md', sm: 'xl' }} radius="md">
        {isLoading ? (
          <Center py="xl"><Loader /></Center>
        ) : (
          <form onSubmit={form.onSubmit(submit)}>
            <Stack>
              {errorMsg && <Alert color="red" icon={<IconAlertTriangle size={16} />}>{errorMsg}</Alert>}

              <Select
                label="Package"
                data={plans.map((p) => ({ value: p.product, label: p.name }))}
                allowDeselect={false}
                {...form.getInputProps('product')}
                onChange={(v) => { form.setFieldValue('product', v || ''); form.setFieldValue('billing_period', ''); }}
              />
              {selectedPlan?.description && <Text size="xs" c="dimmed" mt={-8}>{selectedPlan.description}</Text>}

              {isWifiHotspot && (
                <Radio.Group
                  label="How will you collect voucher payments?"
                  {...form.getInputProps('payment_mode')}
                  onChange={(v) => form.setFieldValue('payment_mode', (v as 'self_managed' | 'platform_collected') || 'self_managed')}
                >
                  <Stack gap={6} mt={4}>
                    <Radio
                      value="self_managed"
                      label={
                        <Stack gap={0}>
                          <Text size="sm">I'll use my own Pesapal account</Text>
                          <Text size="xs" c="dimmed">Pay the license fee below — no commission on your sales.</Text>
                        </Stack>
                      }
                    />
                    <Radio
                      value="platform_collected"
                      label={
                        <Stack gap={0}>
                          <Text size="sm">Let MoBilling collect payments for me</Text>
                          <Text size="xs" c="dimmed">
                            Free license — MoBilling keeps a small commission per voucher sold instead.
                          </Text>
                        </Stack>
                      }
                    />
                  </Stack>
                </Radio.Group>
              )}

              {!isFreePlatformCollected && availablePeriods.length > 0 && (
                <Radio.Group
                  label="Billing Period"
                  {...form.getInputProps('billing_period')}
                >
                  <Stack gap={6} mt={4}>
                    {availablePeriods.map((period) => (
                      <Radio
                        key={period}
                        value={period}
                        label={
                          <Group gap={6}>
                            <Text size="sm">{PERIOD_LABELS[period]}</Text>
                            <Text size="sm" c="dimmed">
                              — TZS {Number(selectedPlan![`${period}_price` as keyof PublicLicensePlan]).toLocaleString()}
                            </Text>
                          </Group>
                        }
                      />
                    ))}
                  </Stack>
                </Radio.Group>
              )}

              <TextInput label="Your Name" required {...form.getInputProps('customer_name')} />
              <TextInput label="Your Email" required {...form.getInputProps('customer_email')} />
              <TextInput label="Phone (optional)" placeholder="255..." {...form.getInputProps('customer_phone')} />

              {isFreePlatformCollected ? (
                <Group justify="space-between" mt="sm">
                  <Text fw={600}>Total</Text>
                  <Text fw={700} size="lg" c="teal">Free</Text>
                </Group>
              ) : selectedPrice && (
                <Group justify="space-between" mt="sm">
                  <Text fw={600}>Total</Text>
                  <Text fw={700} size="lg">TZS {Number(selectedPrice).toLocaleString()}</Text>
                </Group>
              )}

              <Button type="submit" loading={loading} leftSection={<IconCreditCard size={16} />} mt="sm">
                {isFreePlatformCollected ? 'Get Free License' : 'Pay with Pesapal'}
              </Button>
            </Stack>
          </form>
        )}
      </Paper>
    </Container>
  );
}
