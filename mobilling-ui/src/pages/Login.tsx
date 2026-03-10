import { useState } from 'react';
import {
  TextInput, PasswordInput, Button, Paper, Title, Text, Anchor, Stack,
  Image, Group, Box, ThemeIcon, List, rem, useMantineColorScheme, useComputedColorScheme,
  ActionIcon, PinInput, Divider, Alert,
} from '@mantine/core';
import { useForm } from '@mantine/form';
import { notifications } from '@mantine/notifications';
import { useAuth } from '../context/AuthContext';
import { useNavigate, Link } from 'react-router-dom';
import { verifyAndRegisterPortal } from '../api/auth';
import {
  IconFileInvoice, IconChartBar, IconShieldCheck, IconSun, IconMoon, IconArrowLeft,
  IconCheck,
} from '@tabler/icons-react';

const features = [
  { icon: IconFileInvoice, text: 'Create invoices, quotations & proformas in seconds' },
  { icon: IconChartBar, text: 'Track payments, bills & statutory obligations' },
  { icon: IconShieldCheck, text: 'Secure multi-tenant platform with role-based access' },
];

export default function Login() {
  const { login } = useAuth();
  const navigate = useNavigate();
  const { toggleColorScheme } = useMantineColorScheme();
  const computedColorScheme = useComputedColorScheme('light');

  // OTP setup state
  const [otpMode, setOtpMode] = useState(false);
  const [otpEmail, setOtpEmail] = useState('');
  const [otpClientName, setOtpClientName] = useState('');
  const [otpValue, setOtpValue] = useState('');
  const [otpLoading, setOtpLoading] = useState(false);
  const [otpDone, setOtpDone] = useState(false);

  const form = useForm({
    initialValues: { identifier: '', password: '' },
    validate: {
      identifier: (v) => (v.length > 0 ? null : 'Email or phone is required'),
      password: (v) => (v.length > 0 ? null : 'Password is required'),
    },
  });

  const setupForm = useForm({
    initialValues: { name: '', password: '', password_confirmation: '', phone: '' },
    validate: {
      name: (v) => (v.length > 0 ? null : 'Required'),
      password: (v) => (v.length >= 8 ? null : 'Min 8 characters'),
      password_confirmation: (v, values) => (v === values.password ? null : 'Passwords do not match'),
    },
  });

  const handleSubmit = async (values: typeof form.values) => {
    try {
      const { user, userType } = await login(values);
      if (userType === 'client') {
        navigate('/portal/dashboard');
      } else {
        navigate(user.role === 'super_admin' ? '/admin/tenants' : '/dashboard');
      }
    } catch (err: any) {
      // Check if backend says OTP is required (status 449)
      if (err.response?.status === 449 && err.response?.data?.requires_otp) {
        setOtpEmail(values.identifier);
        setOtpClientName(err.response.data.client_name || '');
        setOtpMode(true);
        notifications.show({
          title: 'Verification required',
          message: 'A verification code has been sent to your email.',
          color: 'blue',
        });
        return;
      }

      notifications.show({
        title: 'Login failed',
        message: err.response?.data?.message || 'Invalid credentials',
        color: 'red',
      });
    }
  };

  const handleSetupAccount = async (values: typeof setupForm.values) => {
    if (otpValue.length !== 6) {
      notifications.show({ title: 'Error', message: 'Enter the 6-digit code', color: 'red' });
      return;
    }
    setOtpLoading(true);
    try {
      const res = await verifyAndRegisterPortal({
        email: otpEmail,
        otp: otpValue,
        name: values.name,
        password: values.password,
        password_confirmation: values.password_confirmation,
        phone: values.phone || undefined,
      });
      localStorage.setItem('token', res.data.token);
      localStorage.setItem('user_type', 'client');
      setOtpDone(true);
      setTimeout(() => { window.location.href = '/portal/dashboard'; }, 1500);
    } catch (err: any) {
      notifications.show({
        title: 'Error',
        message: err.response?.data?.message || err.response?.data?.errors?.otp?.[0] || 'Verification failed',
        color: 'red',
      });
    } finally {
      setOtpLoading(false);
    }
  };

  const isDark = computedColorScheme === 'dark';

  return (
    <Box style={{ minHeight: '100vh', display: 'flex' }}>
      {/* Left branding panel — hidden on mobile */}
      <Box
        visibleFrom="md"
        style={{
          width: '45%',
          background: isDark
            ? '#141517'
            : 'linear-gradient(160deg, #3b5bdb 0%, #364fc7 50%, #2b3a8e 100%)',
          display: 'flex',
          flexDirection: 'column',
          justifyContent: 'center',
          padding: rem(60),
          position: 'relative',
          overflow: 'hidden',
        }}
      >
        <Box
          style={{
            position: 'absolute', top: '-20%', right: '-10%',
            width: '60%', height: '60%', borderRadius: '50%',
            background: isDark
              ? 'radial-gradient(circle, rgba(59,130,246,0.12) 0%, transparent 70%)'
              : 'rgba(255,255,255,0.06)',
            filter: isDark ? 'blur(40px)' : undefined,
          }}
        />
        <Box
          style={{
            position: 'absolute', bottom: '-15%', left: '-5%',
            width: '40%', height: '40%', borderRadius: '50%',
            background: isDark
              ? 'radial-gradient(circle, rgba(99,102,241,0.10) 0%, transparent 70%)'
              : 'rgba(255,255,255,0.04)',
            filter: isDark ? 'blur(30px)' : undefined,
          }}
        />

        <Group gap={12} mb={rem(48)}>
          <Image src="/moinfotech-logo.png" h={44} w="auto" alt="MoBilling" />
          <Text size={rem(28)} fw={800} c="white">MoBilling</Text>
        </Group>

        <Title order={2} c="white" fw={700} mb="sm" style={{ lineHeight: 1.3 }}>
          Billing & Statutory{'\n'}Management Made Simple
        </Title>
        <Text c={isDark ? 'rgba(255,255,255,0.5)' : 'rgba(255,255,255,0.75)'} size="lg" mb={rem(40)} maw={420}>
          Streamline your invoicing, track payments, and stay compliant — all in one platform.
        </Text>

        <List spacing="lg" size="md" center>
          {features.map((f, i) => (
            <List.Item
              key={i}
              icon={
                <ThemeIcon
                  size={36}
                  radius="xl"
                  color={isDark ? 'blue' : 'indigo'}
                  variant={isDark ? 'light' : 'white'}
                >
                  <f.icon size={18} />
                </ThemeIcon>
              }
            >
              <Text c={isDark ? 'rgba(255,255,255,0.7)' : 'white'} size="sm" fw={500}>{f.text}</Text>
            </List.Item>
          ))}
        </List>

        <Text size="xs" c="rgba(255,255,255,0.25)" mt="auto" pt={rem(60)}>
          &copy; {new Date().getFullYear()} Moinfotech. All rights reserved.
        </Text>
      </Box>

      {/* Right form panel */}
      <Box
        style={{
          flex: 1,
          display: 'flex',
          flexDirection: 'column',
          justifyContent: 'center',
          alignItems: 'center',
          padding: rem(24),
          position: 'relative',
        }}
      >
        <Group style={{ position: 'absolute', top: rem(20), right: rem(20) }} gap="xs">
          <Button
            component="a"
            href="/"
            variant="subtle"
            size="compact-sm"
            leftSection={<IconArrowLeft size={14} />}
          >
            Home
          </Button>
          <ActionIcon
            variant="default"
            size="lg"
            onClick={toggleColorScheme}
            aria-label="Toggle color scheme"
          >
            {computedColorScheme === 'dark' ? <IconSun size={18} /> : <IconMoon size={18} />}
          </ActionIcon>
        </Group>

        <Box w="100%" maw={400}>
          {/* Mobile-only logo */}
          <Group justify="center" gap={8} mb="md" hiddenFrom="md">
            <Image src="/moinfotech-logo.png" h={36} w="auto" alt="MoBilling" />
            <Text size="xl" fw={800}>MoBilling</Text>
          </Group>

          {!otpMode ? (
            <>
              <Title order={2} ta="center" mb={4}>Welcome back</Title>
              <Text c="dimmed" size="sm" ta="center" mb={rem(32)}>
                Sign in to continue to your dashboard
              </Text>

              <Paper withBorder shadow="sm" p="xl" radius="md">
                <form onSubmit={form.onSubmit(handleSubmit)}>
                  <Stack gap="md">
                    <TextInput
                      label="Email or Phone"
                      placeholder="you@company.com or 0712345678"
                      size="md"
                      required
                      {...form.getInputProps('identifier')}
                    />
                    <PasswordInput
                      label="Password"
                      placeholder="Your password"
                      size="md"
                      required
                      {...form.getInputProps('password')}
                    />
                    <Anchor component={Link} to="/forgot-password" size="sm" ta="right" display="block">
                      Forgot password?
                    </Anchor>
                    <Button fullWidth type="submit" size="md" mt="xs">
                      Sign in
                    </Button>
                  </Stack>
                </form>
              </Paper>

              <Text c="dimmed" size="sm" ta="center" mt="lg">
                Don&apos;t have an account?{' '}
                <Anchor component={Link} to="/register" size="sm" fw={600}>
                  Create one
                </Anchor>
              </Text>
            </>
          ) : otpDone ? (
            <Paper withBorder shadow="sm" p="xl" radius="md">
              <Stack gap="md" align="center" py="lg">
                <ThemeIcon size={60} radius="xl" color="green" variant="light">
                  <IconCheck size={32} />
                </ThemeIcon>
                <Title order={3}>Account Created!</Title>
                <Text c="dimmed" ta="center">Redirecting to your portal...</Text>
              </Stack>
            </Paper>
          ) : (
            <>
              <Title order={2} ta="center" mb={4}>Set Up Your Account</Title>
              <Text c="dimmed" size="sm" ta="center" mb={rem(32)}>
                Verify your email and create your portal password
              </Text>

              <Paper withBorder shadow="sm" p="xl" radius="md">
                <form onSubmit={setupForm.onSubmit(handleSetupAccount)}>
                  <Stack gap="md">
                    <Alert color="blue" variant="light">
                      Code sent to <b>{otpEmail}</b>
                      {otpClientName && <> for <b>{otpClientName}</b></>}
                    </Alert>

                    <div>
                      <Text size="sm" fw={500} mb={4}>Verification Code</Text>
                      <Group justify="center">
                        <PinInput
                          length={6}
                          type="number"
                          size="md"
                          value={otpValue}
                          onChange={setOtpValue}
                        />
                      </Group>
                    </div>

                    <Divider />

                    <TextInput label="Your Name" required {...setupForm.getInputProps('name')} />
                    <TextInput label="Phone" {...setupForm.getInputProps('phone')} />
                    <PasswordInput label="Set Password" required {...setupForm.getInputProps('password')} />
                    <PasswordInput label="Confirm Password" required {...setupForm.getInputProps('password_confirmation')} />

                    <Button fullWidth type="submit" size="md" loading={otpLoading}>
                      Create Account
                    </Button>

                    <Anchor size="sm" ta="center" onClick={() => { setOtpMode(false); setOtpValue(''); }}>
                      Back to Sign in
                    </Anchor>
                  </Stack>
                </form>
              </Paper>
            </>
          )}
        </Box>
      </Box>
    </Box>
  );
}
