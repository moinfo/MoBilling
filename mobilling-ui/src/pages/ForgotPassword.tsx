import { useState } from 'react';
import {
  TextInput, PasswordInput, Button, Paper, Title, Text, Anchor, Stack,
  Image, Group, Box, ThemeIcon, List, rem, useMantineColorScheme, useComputedColorScheme,
  ActionIcon, Alert, PinInput,
} from '@mantine/core';
import { useForm } from '@mantine/form';
import { notifications } from '@mantine/notifications';
import { Link, useNavigate } from 'react-router-dom';
import {
  IconMail, IconShieldCheck, IconLock, IconSun, IconMoon, IconArrowLeft, IconCheck,
  IconUserPlus,
} from '@tabler/icons-react';
import { forgotPassword, verifyResetOtp, resetPassword } from '../api/auth';

const tips = [
  { icon: IconMail, text: 'A verification code will be sent to your email' },
  { icon: IconShieldCheck, text: 'The code expires in 10 minutes for security' },
  { icon: IconLock, text: 'Your account stays secure throughout the process' },
];

type Step = 'request' | 'verify' | 'reset' | 'done';

export default function ForgotPassword() {
  const navigate = useNavigate();
  const [step, setStep] = useState<Step>('request');
  const [loading, setLoading] = useState(false);
  const [identifier, setIdentifier] = useState('');
  const [emailHint, setEmailHint] = useState('');
  const [otp, setOtp] = useState('');
  const [isRegistration, setIsRegistration] = useState(false);
  const [clientName, setClientName] = useState('');
  const { toggleColorScheme } = useMantineColorScheme();
  const computedColorScheme = useComputedColorScheme('light');
  const isDark = computedColorScheme === 'dark';

  const requestForm = useForm({
    initialValues: { identifier: '' },
    validate: {
      identifier: (v) => (v.length > 0 ? null : 'Email or phone is required'),
    },
  });

  const resetForm = useForm({
    initialValues: { password: '', password_confirmation: '' },
    validate: {
      password: (v) => (v.length >= 8 ? null : 'Min 8 characters'),
      password_confirmation: (v, values) => (v === values.password ? null : 'Passwords do not match'),
    },
  });

  // Step 1: Request OTP
  const handleRequest = async (values: typeof requestForm.values) => {
    setLoading(true);
    try {
      const res = await forgotPassword(values.identifier);
      setIdentifier(values.identifier);
      setEmailHint(res.data.email_hint || '');
      setIsRegistration(!!res.data.requires_registration);
      setStep('verify');
      notifications.show({ title: 'Code sent', message: res.data.message, color: 'green' });
    } catch (err: any) {
      const msg = err.response?.data?.message || err.response?.data?.errors?.identifier?.[0] || 'Something went wrong.';
      notifications.show({ title: 'Error', message: msg, color: 'red' });
    } finally {
      setLoading(false);
    }
  };

  // Step 2: Verify OTP
  const handleVerifyOtp = async () => {
    if (otp.length !== 6) {
      notifications.show({ title: 'Error', message: 'Enter the 6-digit code', color: 'red' });
      return;
    }
    setLoading(true);
    try {
      const res = await verifyResetOtp({ identifier, otp });
      setIsRegistration(!!res.data.requires_registration);
      if (res.data.client_name) setClientName(res.data.client_name);
      setStep('reset');
      notifications.show({
        title: 'Verified',
        message: res.data.requires_registration
          ? 'Code verified. Set up your portal account.'
          : 'Code verified. Set your new password.',
        color: 'green',
      });
    } catch (err: any) {
      const msg = err.response?.data?.message || err.response?.data?.errors?.otp?.[0] || 'Verification failed.';
      notifications.show({ title: 'Error', message: msg, color: 'red' });
    } finally {
      setLoading(false);
    }
  };

  // Step 3: Reset password or create account
  const handleReset = async (values: typeof resetForm.values) => {
    setLoading(true);
    try {
      const res = await resetPassword({
        identifier,
        otp,
        password: values.password,
        password_confirmation: values.password_confirmation,
      });

      if (isRegistration && res.data.token) {
        // Auto-login after account creation
        localStorage.setItem('token', res.data.token);
        localStorage.setItem('user_type', res.data.user_type || 'client');
        notifications.show({ title: 'Welcome!', message: 'Portal account created successfully.', color: 'green' });
        navigate('/portal/dashboard');
        return;
      }

      setStep('done');
    } catch (err: any) {
      const msg = err.response?.data?.message || err.response?.data?.errors?.otp?.[0]
        || err.response?.data?.errors?.name?.[0] || 'Failed.';
      notifications.show({ title: 'Error', message: msg, color: 'red' });
    } finally {
      setLoading(false);
    }
  };

  return (
    <Box style={{ minHeight: '100vh', display: 'flex' }}>
      {/* Left branding panel */}
      <Box
        visibleFrom="md"
        style={{
          width: '45%',
          background: isDark
            ? '#141517'
            : 'linear-gradient(160deg, #e8590c 0%, #d9480f 50%, #c92a2a 100%)',
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
              ? 'radial-gradient(circle, rgba(232,89,12,0.12) 0%, transparent 70%)'
              : 'rgba(255,255,255,0.06)',
            filter: isDark ? 'blur(40px)' : undefined,
          }}
        />
        <Box
          style={{
            position: 'absolute', bottom: '-15%', left: '-5%',
            width: '40%', height: '40%', borderRadius: '50%',
            background: isDark
              ? 'radial-gradient(circle, rgba(201,42,42,0.10) 0%, transparent 70%)'
              : 'rgba(255,255,255,0.04)',
            filter: isDark ? 'blur(30px)' : undefined,
          }}
        />

        <Group gap={12} mb={rem(48)}>
          <Image src="/moinfotech-logo.png" h={44} w="auto" alt="MoBilling" />
          <Text size={rem(28)} fw={800} c="white">MoBilling</Text>
        </Group>

        <Title order={2} c="white" fw={700} mb="sm" style={{ lineHeight: 1.3 }}>
          Forgot your password?{'\n'}No worries.
        </Title>
        <Text c={isDark ? 'rgba(255,255,255,0.5)' : 'rgba(255,255,255,0.75)'} size="lg" mb={rem(40)} maw={420}>
          We&apos;ll help you get back into your account quickly and securely.
        </Text>

        <List spacing="lg" size="md" center>
          {tips.map((t, i) => (
            <List.Item
              key={i}
              icon={
                <ThemeIcon
                  size={36}
                  radius="xl"
                  color="orange"
                  variant={isDark ? 'light' : 'white'}
                >
                  <t.icon size={18} />
                </ThemeIcon>
              }
            >
              <Text c={isDark ? 'rgba(255,255,255,0.7)' : 'white'} size="sm" fw={500}>{t.text}</Text>
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
            {isDark ? <IconSun size={18} /> : <IconMoon size={18} />}
          </ActionIcon>
        </Group>

        <Box w="100%" maw={400}>
          <Group justify="center" gap={8} mb="md" hiddenFrom="md">
            <Image src="/moinfotech-logo.png" h={36} w="auto" alt="MoBilling" />
            <Text size="xl" fw={800}>MoBilling</Text>
          </Group>

          {/* Step 1: Enter email or phone */}
          {step === 'request' && (
            <>
              <Title order={2} ta="center" mb={4}>Reset password</Title>
              <Text c="dimmed" size="sm" ta="center" mb={rem(32)}>
                Enter your email or phone and we&apos;ll send you a verification code
              </Text>

              <Paper withBorder shadow="sm" p="xl" radius="md">
                <form onSubmit={requestForm.onSubmit(handleRequest)}>
                  <Stack gap="md">
                    <TextInput
                      label="Email or Phone"
                      placeholder="you@company.com or 0712345678"
                      size="md"
                      required
                      {...requestForm.getInputProps('identifier')}
                    />
                    <Button fullWidth type="submit" size="md" mt="xs" loading={loading}>
                      Send verification code
                    </Button>
                  </Stack>
                </form>
              </Paper>

              <Text c="dimmed" size="sm" ta="center" mt="lg">
                Remember your password?{' '}
                <Anchor component={Link} to="/login" size="sm" fw={600}>
                  Sign in
                </Anchor>
              </Text>
            </>
          )}

          {/* Step 2: Enter and verify OTP */}
          {step === 'verify' && (
            <>
              <Title order={2} ta="center" mb={4}>Verify code</Title>
              <Text c="dimmed" size="sm" ta="center" mb={rem(32)}>
                Enter the 6-digit code sent to your email
              </Text>

              <Paper withBorder shadow="sm" p="xl" radius="md">
                <Stack gap="md">
                  <Alert color="blue" variant="light">
                    Code sent to {emailHint || identifier}
                  </Alert>

                  <div>
                    <Text size="sm" fw={500} mb={4}>Verification Code</Text>
                    <Group justify="center">
                      <PinInput
                        length={6}
                        type="number"
                        size="md"
                        value={otp}
                        onChange={setOtp}
                      />
                    </Group>
                  </div>

                  <Button fullWidth size="md" loading={loading} onClick={handleVerifyOtp}>
                    Verify Code
                  </Button>

                  <Anchor size="sm" ta="center" onClick={() => { setStep('request'); setOtp(''); }}>
                    Use a different email or phone
                  </Anchor>
                </Stack>
              </Paper>
            </>
          )}

          {/* Step 3: Set new password OR create account */}
          {step === 'reset' && (
            <>
              <Title order={2} ta="center" mb={4}>
                {isRegistration ? 'Create portal account' : 'Set new password'}
              </Title>
              <Text c="dimmed" size="sm" ta="center" mb={rem(32)}>
                {isRegistration
                  ? 'Your identity has been verified. Set up your portal account.'
                  : 'Your identity has been verified. Choose a new password.'}
              </Text>

              <Paper withBorder shadow="sm" p="xl" radius="md">
                <form onSubmit={resetForm.onSubmit(handleReset)}>
                  <Stack gap="md">
                    <Alert
                      color={isRegistration ? 'blue' : 'green'}
                      variant="light"
                      icon={isRegistration ? <IconUserPlus size={16} /> : <IconCheck size={16} />}
                    >
                      {isRegistration
                        ? `Setting up portal access for ${clientName || identifier}`
                        : `Code verified for ${emailHint || identifier}`}
                    </Alert>

                    <PasswordInput
                      label={isRegistration ? 'Password' : 'New Password'}
                      required
                      size="md"
                      {...resetForm.getInputProps('password')}
                    />
                    <PasswordInput
                      label="Confirm Password"
                      required
                      size="md"
                      {...resetForm.getInputProps('password_confirmation')}
                    />

                    <Button fullWidth type="submit" size="md" loading={loading}>
                      {isRegistration ? 'Create Account' : 'Reset Password'}
                    </Button>
                  </Stack>
                </form>
              </Paper>
            </>
          )}

          {/* Step 4: Success (password reset only — registration auto-redirects) */}
          {step === 'done' && (
            <Paper withBorder shadow="sm" p="xl" radius="md">
              <Stack gap="md" align="center" py="lg">
                <ThemeIcon size={60} radius="xl" color="green" variant="light">
                  <IconCheck size={32} />
                </ThemeIcon>
                <Title order={3}>Password Reset!</Title>
                <Text c="dimmed" ta="center">Your password has been changed successfully.</Text>
                <Button fullWidth size="md" onClick={() => navigate('/login')}>
                  Sign in
                </Button>
              </Stack>
            </Paper>
          )}
        </Box>
      </Box>
    </Box>
  );
}
