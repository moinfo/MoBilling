import { useEffect, useState } from 'react';
import {
  TextInput, PasswordInput, Button, Paper, Title, Text, Anchor, Stack,
  Image, Group, Box, rem, useMantineColorScheme, useComputedColorScheme,
  ActionIcon, PinInput, Alert, ThemeIcon, Grid,
} from '@mantine/core';
import { useForm } from '@mantine/form';
import { notifications } from '@mantine/notifications';
import { useNavigate, useSearchParams, Link } from 'react-router-dom';
import { IconSun, IconMoon, IconArrowLeft, IconCheck, IconUserPlus } from '@tabler/icons-react';
import { requestPortalOtp, verifyAndRegisterPortal } from '../../api/auth';

export default function PortalRegister() {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const { toggleColorScheme } = useMantineColorScheme();
  const computedColorScheme = useComputedColorScheme('light');
  const isDark = computedColorScheme === 'dark';

  const [step, setStep] = useState<'details' | 'verify' | 'done'>('details');
  const [otpValue, setOtpValue] = useState('');
  const [loading, setLoading] = useState(false);
  const [clientName, setClientName] = useState<string | null>(null);
  const [isNewClient, setIsNewClient] = useState(true);

  const form = useForm({
    initialValues: {
      name: '', company: '', email: searchParams.get('email') ?? '',
      phone: '', address: '', password: '', password_confirmation: '',
    },
    validate: {
      name: (v) => (v.trim().length > 1 ? null : 'Your full name is required'),
      email: (v) => (/^\S+@\S+\.\S+$/.test(v) ? null : 'A valid email is required'),
      password: (v) => (v.length >= 8 ? null : 'Minimum 8 characters'),
      password_confirmation: (v, values) => (v === values.password ? null : 'Passwords do not match'),
    },
  });

  // Arriving from login with ?sent=1: the OTP email is already on its way
  // (imported client claiming their account) — go straight to the code step.
  useEffect(() => {
    if (searchParams.get('email') && searchParams.get('sent')) {
      setStep('verify');
      setIsNewClient(false);
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const sendOtp = async (silent = false) => {
    setLoading(true);
    try {
      const res = await requestPortalOtp(form.values.email.trim().toLowerCase());
      if (res.data.has_account) {
        notifications.show({
          title: 'You already have an account',
          message: 'Please sign in instead — use "Forgot password" if needed.',
          color: 'blue',
        });
        navigate('/portal/login');
        return;
      }
      setClientName(res.data.client_name ?? null);
      setIsNewClient(res.data.new_client ?? !res.data.client_name);
      setStep('verify');
      if (!silent) {
        notifications.show({ message: 'Verification code sent to your email.', color: 'green' });
      }
    } catch (e: any) {
      notifications.show({
        message: e?.response?.data?.message
          ?? e?.response?.data?.errors?.email?.[0]
          ?? 'Could not send the verification code.',
        color: 'red',
      });
    } finally {
      setLoading(false);
    }
  };

  const handleDetails = form.onSubmit(() => sendOtp());

  const handleVerify = async () => {
    if (otpValue.length !== 6) {
      notifications.show({ message: 'Enter the 6-digit code from your email.', color: 'red' });
      return;
    }
    // Claim flow arrives with empty details — require them before submitting.
    if (!form.values.name.trim() || form.values.password.length < 8
      || form.values.password !== form.values.password_confirmation) {
      notifications.show({ message: 'Fill in your name and a matching password (min 8 characters) below.', color: 'red' });
      return;
    }
    setLoading(true);
    try {
      const res = await verifyAndRegisterPortal({
        email: form.values.email.trim().toLowerCase(),
        otp: otpValue,
        name: form.values.name.trim(),
        password: form.values.password,
        password_confirmation: form.values.password_confirmation,
        phone: form.values.phone || undefined,
        company: form.values.company || undefined,
        address: form.values.address || undefined,
      });
      localStorage.setItem('token', res.data.token);
      localStorage.setItem('user_type', 'client');
      setStep('done');
      setTimeout(() => { window.location.href = '/portal/dashboard'; }, 1500);
    } catch (e: any) {
      notifications.show({
        message: e?.response?.data?.message ?? e?.response?.data?.errors?.otp?.[0] ?? 'Verification failed.',
        color: 'red',
      });
    } finally {
      setLoading(false);
    }
  };

  return (
    <Box style={{
      minHeight: '100vh', display: 'flex', flexDirection: 'column',
      justifyContent: 'center', alignItems: 'center', padding: rem(24), position: 'relative',
    }}>
      <Group style={{ position: 'absolute', top: rem(20), right: rem(20) }} gap="xs">
        <ActionIcon variant="default" size="lg" onClick={toggleColorScheme} aria-label="Toggle color scheme">
          {isDark ? <IconSun size={18} /> : <IconMoon size={18} />}
        </ActionIcon>
      </Group>

      <Box w="100%" maw={560}>
        <Group justify="center" gap={8} mb="md">
          <Image src="/moinfotech-logo.png" h={40} w="auto" alt="Moinfotech" />
          <Text size="xl" fw={800}>Moinfotech</Text>
        </Group>

        {step === 'done' ? (
          <Paper withBorder shadow="sm" p="xl" radius="md">
            <Stack gap="md" align="center" py="lg">
              <ThemeIcon size={60} radius="xl" color="green" variant="light">
                <IconCheck size={32} />
              </ThemeIcon>
              <Title order={3}>Welcome aboard!</Title>
              <Text c="dimmed" ta="center">Your account is ready — taking you to your client area…</Text>
            </Stack>
          </Paper>
        ) : step === 'details' ? (
          <>
            <Title order={2} ta="center" mb={4}>Create an Account</Title>
            <Text c="dimmed" size="sm" ta="center" mb={rem(28)}>
              Register to order hosting & domains, pay invoices and get support
            </Text>

            <Paper withBorder shadow="sm" p="xl" radius="md">
              <form onSubmit={handleDetails}>
                <Stack gap="sm">
                  <Grid>
                    <Grid.Col span={{ base: 12, sm: 6 }}>
                      <TextInput label="Full Name" required {...form.getInputProps('name')} />
                    </Grid.Col>
                    <Grid.Col span={{ base: 12, sm: 6 }}>
                      <TextInput label="Company (optional)" placeholder="Business or organisation"
                        {...form.getInputProps('company')} />
                    </Grid.Col>
                  </Grid>
                  <Grid>
                    <Grid.Col span={{ base: 12, sm: 6 }}>
                      <TextInput label="Email Address" required type="email" {...form.getInputProps('email')} />
                    </Grid.Col>
                    <Grid.Col span={{ base: 12, sm: 6 }}>
                      <TextInput label="Phone" placeholder="0712 345 678" {...form.getInputProps('phone')} />
                    </Grid.Col>
                  </Grid>
                  <TextInput label="Address (optional)" placeholder="Street, city" {...form.getInputProps('address')} />
                  <Grid>
                    <Grid.Col span={{ base: 12, sm: 6 }}>
                      <PasswordInput label="Password" required {...form.getInputProps('password')} />
                    </Grid.Col>
                    <Grid.Col span={{ base: 12, sm: 6 }}>
                      <PasswordInput label="Confirm Password" required {...form.getInputProps('password_confirmation')} />
                    </Grid.Col>
                  </Grid>

                  <Button fullWidth type="submit" size="md" mt="xs" loading={loading}
                    leftSection={<IconUserPlus size={17} />}>
                    Continue — Verify Email
                  </Button>
                </Stack>
              </form>
            </Paper>

            <Text c="dimmed" size="sm" ta="center" mt="lg">
              Already registered?{' '}
              <Anchor component={Link} to="/portal/login" size="sm" fw={600}>Sign in</Anchor>
            </Text>
          </>
        ) : (
          <>
            <Title order={2} ta="center" mb={4}>Verify Your Email</Title>
            <Text c="dimmed" size="sm" ta="center" mb={rem(28)}>
              Enter the 6-digit code we sent to <b>{form.values.email}</b>
            </Text>

            <Paper withBorder shadow="sm" p="xl" radius="md">
              <Stack gap="md">
                {!isNewClient && (
                  <Alert color="blue" variant="light">
                    Welcome back{clientName ? <>, <b>{clientName}</b></> : ''}! We found your existing
                    client account — verify your email and set a password to activate portal access.
                  </Alert>
                )}

                <Group justify="center">
                  <PinInput length={6} type="number" size="lg" value={otpValue} onChange={setOtpValue} autoFocus />
                </Group>

                {/* Claim flow (from login) arrives without details — collect them here */}
                {(!form.values.name || !form.values.password) && (
                  <Stack gap="sm">
                    <TextInput label="Your Name" required {...form.getInputProps('name')} />
                    <TextInput label="Phone" {...form.getInputProps('phone')} />
                    <Grid>
                      <Grid.Col span={{ base: 12, sm: 6 }}>
                        <PasswordInput label="Set Password" required {...form.getInputProps('password')} />
                      </Grid.Col>
                      <Grid.Col span={{ base: 12, sm: 6 }}>
                        <PasswordInput label="Confirm Password" required {...form.getInputProps('password_confirmation')} />
                      </Grid.Col>
                    </Grid>
                  </Stack>
                )}

                <Button fullWidth size="md" loading={loading} onClick={handleVerify}>
                  Create Account
                </Button>

                <Group justify="space-between">
                  <Anchor size="sm" onClick={() => { setStep('details'); setOtpValue(''); }}>
                    <Group gap={4}><IconArrowLeft size={13} /> Edit details</Group>
                  </Anchor>
                  <Anchor size="sm" onClick={() => sendOtp()}>Resend code</Anchor>
                </Group>
              </Stack>
            </Paper>
          </>
        )}
      </Box>
    </Box>
  );
}
