import { useState } from 'react';
import {
  TextInput, Button, Paper, Title, Text, Anchor, Stack,
  Image, Group, Box, ThemeIcon, List, rem, useMantineColorScheme, useComputedColorScheme,
  ActionIcon, Alert,
} from '@mantine/core';
import { useForm } from '@mantine/form';
import { notifications } from '@mantine/notifications';
import { Link } from 'react-router-dom';
import {
  IconMail, IconShieldCheck, IconLock, IconSun, IconMoon, IconArrowLeft, IconCheck,
} from '@tabler/icons-react';
import { forgotPassword } from '../api/auth';

const tips = [
  { icon: IconMail, text: 'A reset link will be sent to your email address' },
  { icon: IconShieldCheck, text: 'The link expires in 60 minutes for security' },
  { icon: IconLock, text: 'Your account stays secure throughout the process' },
];

export default function ForgotPassword() {
  const [sent, setSent] = useState(false);
  const [loading, setLoading] = useState(false);
  const { toggleColorScheme } = useMantineColorScheme();
  const computedColorScheme = useComputedColorScheme('light');
  const isDark = computedColorScheme === 'dark';

  const form = useForm({
    initialValues: { email: '' },
    validate: {
      email: (v) => (/^\S+@\S+$/.test(v) ? null : 'Invalid email'),
    },
  });

  const handleSubmit = async (values: typeof form.values) => {
    setLoading(true);
    try {
      await forgotPassword(values.email);
      setSent(true);
    } catch (err: any) {
      const emailError = err.response?.data?.errors?.email?.[0];
      if (emailError) {
        form.setFieldError('email', emailError);
      } else {
        notifications.show({
          title: 'Error',
          message: err.response?.data?.message || 'Something went wrong. Please try again.',
          color: 'red',
        });
      }
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
          We'll help you get back into your account quickly and securely.
        </Text>

        <List spacing="lg" size="md" center>
          {tips.map((t, i) => (
            <List.Item
              key={i}
              icon={
                <ThemeIcon
                  size={36}
                  radius="xl"
                  color={isDark ? 'orange' : 'orange'}
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

          <Title order={2} ta="center" mb={4}>Reset password</Title>
          <Text c="dimmed" size="sm" ta="center" mb={rem(32)}>
            Enter your email and we'll send you a reset link
          </Text>

          <Paper withBorder shadow="sm" p="xl" radius="md">
            {sent ? (
              <Alert icon={<IconCheck size={18} />} color="green" title="Check your email">
                If an account exists with that email, you'll receive a password reset link shortly.
                Check your inbox (and spam folder).
              </Alert>
            ) : (
              <form onSubmit={form.onSubmit(handleSubmit)}>
                <Stack gap="md">
                  <TextInput
                    label="Email address"
                    placeholder="you@company.com"
                    size="md"
                    required
                    {...form.getInputProps('email')}
                  />
                  <Button fullWidth type="submit" size="md" mt="xs" loading={loading}>
                    Send reset link
                  </Button>
                </Stack>
              </form>
            )}
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
