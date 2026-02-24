import {
  TextInput, PasswordInput, Button, Paper, Title, Text, Anchor, Stack,
  Image, Group, Box, ThemeIcon, List, rem, useMantineColorScheme, useComputedColorScheme,
  ActionIcon,
} from '@mantine/core';
import { useForm } from '@mantine/form';
import { notifications } from '@mantine/notifications';
import { useAuth } from '../context/AuthContext';
import { useNavigate, Link } from 'react-router-dom';
import {
  IconRocket, IconUsers, IconLock, IconSun, IconMoon, IconArrowLeft,
} from '@tabler/icons-react';

const highlights = [
  { icon: IconRocket, text: 'Get started with a 14-day free trial — no card required' },
  { icon: IconUsers, text: 'Invite your team and manage roles effortlessly' },
  { icon: IconLock, text: 'Your data is encrypted and securely isolated' },
];

export default function Register() {
  const { register } = useAuth();
  const navigate = useNavigate();
  const { toggleColorScheme } = useMantineColorScheme();
  const computedColorScheme = useComputedColorScheme('light');
  const isDark = computedColorScheme === 'dark';

  const form = useForm({
    initialValues: {
      company_name: '',
      name: '',
      email: '',
      phone: '',
      password: '',
      password_confirmation: '',
    },
    validate: {
      company_name: (v) => (v.length > 0 ? null : 'Company name is required'),
      name: (v) => (v.length > 0 ? null : 'Name is required'),
      email: (v) => (/^\S+@\S+$/.test(v) ? null : 'Invalid email'),
      password: (v) => (v.length >= 8 ? null : 'Password must be at least 8 characters'),
      password_confirmation: (v, values) =>
        v === values.password ? null : 'Passwords do not match',
    },
  });

  const handleSubmit = async (values: typeof form.values) => {
    try {
      await register(values);
      navigate('/dashboard');
    } catch (err: any) {
      const errors = err.response?.data?.errors;
      if (errors) {
        Object.entries(errors).forEach(([key, messages]) => {
          form.setFieldError(key, (messages as string[])[0]);
        });
      } else {
        notifications.show({
          title: 'Registration failed',
          message: err.response?.data?.message || 'Something went wrong',
          color: 'red',
        });
      }
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
            : 'linear-gradient(160deg, #0ca678 0%, #1098ad 50%, #1c7ed6 100%)',
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
              ? 'radial-gradient(circle, rgba(20,184,166,0.12) 0%, transparent 70%)'
              : 'rgba(255,255,255,0.06)',
            filter: isDark ? 'blur(40px)' : undefined,
          }}
        />
        <Box
          style={{
            position: 'absolute', bottom: '-15%', left: '-5%',
            width: '40%', height: '40%', borderRadius: '50%',
            background: isDark
              ? 'radial-gradient(circle, rgba(59,130,246,0.10) 0%, transparent 70%)'
              : 'rgba(255,255,255,0.04)',
            filter: isDark ? 'blur(30px)' : undefined,
          }}
        />

        <Group gap={12} mb={rem(48)}>
          <Image src="/moinfotech-logo.png" h={44} w="auto" alt="MoBilling" />
          <Text size={rem(28)} fw={800} c="white">MoBilling</Text>
        </Group>

        <Title order={2} c="white" fw={700} mb="sm" style={{ lineHeight: 1.3 }}>
          Start managing your{'\n'}business today
        </Title>
        <Text c={isDark ? 'rgba(255,255,255,0.5)' : 'rgba(255,255,255,0.75)'} size="lg" mb={rem(40)} maw={420}>
          Join hundreds of businesses using MoBilling to simplify billing and stay compliant.
        </Text>

        <List spacing="lg" size="md" center>
          {highlights.map((h, i) => (
            <List.Item
              key={i}
              icon={
                <ThemeIcon
                  size={36}
                  radius="xl"
                  color={isDark ? 'teal' : 'teal'}
                  variant={isDark ? 'light' : 'white'}
                >
                  <h.icon size={18} />
                </ThemeIcon>
              }
            >
              <Text c={isDark ? 'rgba(255,255,255,0.7)' : 'white'} size="sm" fw={500}>{h.text}</Text>
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

        <Box w="100%" maw={440}>
          <Group justify="center" gap={8} mb="md" hiddenFrom="md">
            <Image src="/moinfotech-logo.png" h={36} w="auto" alt="MoBilling" />
            <Text size="xl" fw={800}>MoBilling</Text>
          </Group>

          <Title order={2} ta="center" mb={4}>Create your account</Title>
          <Text c="dimmed" size="sm" ta="center" mb={rem(32)}>
            Set up your business in under 2 minutes
          </Text>

          <Paper withBorder shadow="sm" p="xl" radius="md">
            <form onSubmit={form.onSubmit(handleSubmit)}>
              <Stack gap="md">
                <TextInput label="Company Name" placeholder="Your company" size="md" required {...form.getInputProps('company_name')} />
                <TextInput label="Your Name" placeholder="John Doe" size="md" required {...form.getInputProps('name')} />
                <TextInput label="Email" placeholder="you@company.com" size="md" required {...form.getInputProps('email')} />
                <TextInput label="Phone" placeholder="+255 7xx xxx xxx" size="md" {...form.getInputProps('phone')} />
                <PasswordInput label="Password" placeholder="Min 8 characters" size="md" required {...form.getInputProps('password')} />
                <PasswordInput label="Confirm Password" placeholder="Repeat password" size="md" required {...form.getInputProps('password_confirmation')} />
                <Button fullWidth type="submit" size="md" mt="xs">
                  Create Account
                </Button>
              </Stack>
            </form>
          </Paper>

          <Text c="dimmed" size="sm" ta="center" mt="lg">
            Already have an account?{' '}
            <Anchor component={Link} to="/login" size="sm" fw={600}>
              Sign in
            </Anchor>
          </Text>
        </Box>
      </Box>
    </Box>
  );
}
