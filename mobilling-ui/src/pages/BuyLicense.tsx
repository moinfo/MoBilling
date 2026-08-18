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

  const form = useForm({
    initialValues: {
      customer_name: '', customer_email: '', customer_phone: '',
      product: preselect || '', billing_period: '',
    },
    validate: {
      customer_name: (v) => (v.trim() ? null : 'Required'),
      customer_email: (v) => (/^\S+@\S+\.\S+$/.test(v) ? null : 'Valid email required'),
      product: (v) => (v ? null : 'Choose a package'),
      billing_period: (v) => (v ? null : 'Choose a billing period'),
    },
  });

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
        product: values.product as 'lite' | 'reseller' | 'general',
        billing_period: values.billing_period as 'monthly' | 'quarterly' | 'semi_annual' | 'annual' | 'perpetual',
      });
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

              {availablePeriods.length > 0 && (
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

              {selectedPrice && (
                <Group justify="space-between" mt="sm">
                  <Text fw={600}>Total</Text>
                  <Text fw={700} size="lg">TZS {Number(selectedPrice).toLocaleString()}</Text>
                </Group>
              )}

              <Button type="submit" loading={loading} leftSection={<IconCreditCard size={16} />} mt="sm">
                Pay with Pesapal
              </Button>
            </Stack>
          </form>
        )}
      </Paper>
    </Container>
  );
}
