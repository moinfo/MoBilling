import { useState } from 'react';
import {
  PasswordInput, Button, Paper, Title, Text, Anchor, Stack,
  Image, Group, Box, ThemeIcon, List, rem, useMantineColorScheme, useComputedColorScheme,
  ActionIcon, Alert,
} from '@mantine/core';
import { useForm } from '@mantine/form';
import { notifications } from '@mantine/notifications';
import { useNavigate, useSearchParams, Link } from 'react-router-dom';
import {
  IconLock, IconShieldCheck, IconKey, IconSun, IconMoon, IconArrowLeft, IconAlertCircle,
} from '@tabler/icons-react';
import { resetPassword } from '../api/auth';

const tips = [
  { icon: IconKey, text: 'Choose a strong password with at least 8 characters' },
  { icon: IconShieldCheck, text: 'Use a mix of letters, numbers, and symbols' },
  { icon: IconLock, text: 'Never share your password with anyone' },
];

export default function ResetPassword() {
  const [loading, setLoading] = useState(false);
  const [searchParams] = useSearchParams();
  const navigate = useNavigate();
  const { toggleColorScheme } = useMantineColorScheme();
  const computedColorScheme = useComputedColorScheme('light');
  const isDark = computedColorScheme === 'dark';

  const token = searchParams.get('token') || '';
  const email = searchParams.get('email') || '';

  const form = useForm({
    initialValues: { password: '', password_confirmation: '' },
    validate: {
      password: (v) => (v.length >= 8 ? null : 'Password must be at least 8 characters'),
      password_confirmation: (v, values) =>
        v === values.password ? null : 'Passwords do not match',
    },
  });

  if (!token || !email) {
    return (
      <Box style={{ minHeight: '100vh', display: 'flex', justifyContent: 'center', alignItems: 'center', padding: rem(24) }}>
        <Box maw={400} w="100%">
          <Alert icon={<IconAlertCircle size={18} />} color="red" title="Invalid reset link">
            This password reset link is invalid or has expired.
          </Alert>
          <Text c="dimmed" size="sm" ta="center" mt="lg">
            <Anchor component={Link} to="/forgot-password" size="sm" fw={600}>
              Request a new reset link
            </Anchor>
          </Text>
        </Box>
      </Box>
    );
  }

  const handleSubmit = async (values: typeof form.values) => {
    setLoading(true);
    try {
      await resetPassword({ token, email, ...values });
      notifications.show({
        title: 'Password reset',
        message: 'Your password has been reset successfully. Please sign in.',
        color: 'green',
      });
      navigate('/login');
    } catch (err: any) {
      notifications.show({
        title: 'Reset failed',
        message: err.response?.data?.message || 'The reset link may have expired. Please try again.',
        color: 'red',
      });
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
            : 'linear-gradient(160deg, #7048e8 0%, #7c3aed 50%, #6d28d9 100%)',
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
              ? 'radial-gradient(circle, rgba(112,72,232,0.12) 0%, transparent 70%)'
              : 'rgba(255,255,255,0.06)',
            filter: isDark ? 'blur(40px)' : undefined,
          }}
        />
        <Box
          style={{
            position: 'absolute', bottom: '-15%', left: '-5%',
            width: '40%', height: '40%', borderRadius: '50%',
            background: isDark
              ? 'radial-gradient(circle, rgba(109,40,217,0.10) 0%, transparent 70%)'
              : 'rgba(255,255,255,0.04)',
            filter: isDark ? 'blur(30px)' : undefined,
          }}
        />

        <Group gap={12} mb={rem(48)}>
          <Image src="/moinfotech-logo.png" h={44} w="auto" alt="MoBilling" />
          <Text size={rem(28)} fw={800} c="white">MoBilling</Text>
        </Group>

        <Title order={2} c="white" fw={700} mb="sm" style={{ lineHeight: 1.3 }}>
          Set your new{'\n'}password
        </Title>
        <Text c={isDark ? 'rgba(255,255,255,0.5)' : 'rgba(255,255,255,0.75)'} size="lg" mb={rem(40)} maw={420}>
          Choose a strong password to keep your account secure.
        </Text>

        <List spacing="lg" size="md" center>
          {tips.map((t, i) => (
            <List.Item
              key={i}
              icon={
                <ThemeIcon
                  size={36}
                  radius="xl"
                  color={isDark ? 'violet' : 'violet'}
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

          <Title order={2} ta="center" mb={4}>New password</Title>
          <Text c="dimmed" size="sm" ta="center" mb={rem(32)}>
            Enter your new password below
          </Text>

          <Paper withBorder shadow="sm" p="xl" radius="md">
            <form onSubmit={form.onSubmit(handleSubmit)}>
              <Stack gap="md">
                <PasswordInput
                  label="New password"
                  placeholder="Min 8 characters"
                  size="md"
                  required
                  {...form.getInputProps('password')}
                />
                <PasswordInput
                  label="Confirm password"
                  placeholder="Repeat password"
                  size="md"
                  required
                  {...form.getInputProps('password_confirmation')}
                />
                <Button fullWidth type="submit" size="md" mt="xs" loading={loading}>
                  Reset password
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
        </Box>
      </Box>
    </Box>
  );
}
