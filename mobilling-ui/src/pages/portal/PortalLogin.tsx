import {
  TextInput, PasswordInput, Button, Paper, Title, Text, Anchor, Stack,
  Image, Group, Box, ThemeIcon, List, rem, useMantineColorScheme, useComputedColorScheme,
  ActionIcon,
} from '@mantine/core';
import { useForm } from '@mantine/form';
import { notifications } from '@mantine/notifications';
import { useAuth } from '../../context/AuthContext';
import { useBranding } from '../../branding';
import { useNavigate, Link } from 'react-router-dom';
import {
  IconWorldWww, IconServer, IconHeadset, IconSun, IconMoon, IconArrowLeft,
} from '@tabler/icons-react';

const features = [
  { icon: IconWorldWww, text: 'Register, renew & manage your .tz domains' },
  { icon: IconServer, text: 'cPanel hosting — one-click login, upgrades & usage' },
  { icon: IconHeadset, text: 'Invoices, wallet top-ups & 24/7 support tickets' },
];

export default function PortalLogin() {
  const { login } = useAuth();
  const navigate = useNavigate();
  const { toggleColorScheme } = useMantineColorScheme();
  const computedColorScheme = useComputedColorScheme('light');
  const isDark = computedColorScheme === 'dark';
  const branding = useBranding();
  const brandName = branding.branded ? (branding.name ?? 'Client Area') : 'Moinfotech';
  const brandLogo = branding.branded ? branding.logo_url : '/moinfotech-logo.png';

  const form = useForm({
    initialValues: { identifier: '', password: '' },
    validate: {
      identifier: (v) => (v.length > 0 ? null : 'Email or phone is required'),
      password: (v) => (v.length > 0 ? null : 'Password is required'),
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
      // Imported WHMCS client without a portal account yet → claim it via OTP.
      if (err.response?.status === 449 && err.response?.data?.requires_otp) {
        notifications.show({
          title: 'Verification required',
          message: 'A verification code has been sent to your email — finish setting up your account.',
          color: 'blue',
        });
        navigate(`/portal/register?email=${encodeURIComponent(values.identifier)}&sent=1`);
        return;
      }
      notifications.show({
        title: 'Login failed',
        message: err.response?.data?.message || 'Invalid credentials',
        color: 'red',
      });
    }
  };

  return (
    <Box style={{ minHeight: '100vh', display: 'flex' }}>
      {/* Left branding panel */}
      <Box visibleFrom="md"
        style={{
          width: '45%',
          background: isDark
            ? '#141517'
            : 'linear-gradient(160deg, #2f6fed 0%, #2b5cd9 50%, #1f3f9e 100%)',
          display: 'flex', flexDirection: 'column', justifyContent: 'center',
          padding: rem(60), position: 'relative', overflow: 'hidden',
        }}>
        <Box style={{
          position: 'absolute', top: '-20%', right: '-10%', width: '60%', height: '60%',
          borderRadius: '50%',
          background: isDark ? 'radial-gradient(circle, rgba(59,130,246,0.12) 0%, transparent 70%)' : 'rgba(255,255,255,0.06)',
          filter: isDark ? 'blur(40px)' : undefined,
        }} />
        <Group gap={12} mb={rem(48)}>
          {brandLogo && <Image src={brandLogo} h={44} w="auto" alt={brandName} />}
          <Text size={rem(26)} fw={800} c="white">{brandName}</Text>
        </Group>

        <Title order={2} c="white" fw={700} mb="sm" style={{ lineHeight: 1.3 }}>
          Client Area
        </Title>
        <Text c={isDark ? 'rgba(255,255,255,0.5)' : 'rgba(255,255,255,0.75)'} size="lg" mb={rem(40)} maw={420}>
          Manage your domains, hosting, invoices and support — all in one place.
        </Text>

        <List spacing="lg" size="md" center>
          {features.map((f, i) => (
            <List.Item key={i}
              icon={
                <ThemeIcon size={36} radius="xl" color={isDark ? 'blue' : 'indigo'} variant={isDark ? 'light' : 'white'}>
                  <f.icon size={18} />
                </ThemeIcon>
              }>
              <Text c={isDark ? 'rgba(255,255,255,0.7)' : 'white'} size="sm" fw={500}>{f.text}</Text>
            </List.Item>
          ))}
        </List>

        <Text size="xs" c="rgba(255,255,255,0.25)" mt="auto" pt={rem(60)}>
          &copy; {new Date().getFullYear()} {branding.branded ? brandName : 'Moinfotech Company Limited'}. All rights reserved.
        </Text>
      </Box>

      {/* Right form panel */}
      <Box style={{
        flex: 1, display: 'flex', flexDirection: 'column', justifyContent: 'center',
        alignItems: 'center', padding: rem(24), position: 'relative',
      }}>
        <Group style={{ position: 'absolute', top: rem(20), right: rem(20) }} gap="xs">
          {(!branding.branded || branding.website) && (
            <Button component="a" href={branding.branded ? branding.website! : 'https://moinfo.co.tz'}
              variant="subtle" size="compact-sm" leftSection={<IconArrowLeft size={14} />}>
              {branding.branded ? branding.website!.replace(/^https?:\/\//, '') : 'moinfo.co.tz'}
            </Button>
          )}
          <ActionIcon variant="default" size="lg" onClick={toggleColorScheme} aria-label="Toggle color scheme">
            {isDark ? <IconSun size={18} /> : <IconMoon size={18} />}
          </ActionIcon>
        </Group>

        <Box w="100%" maw={400}>
          <Group justify="center" gap={8} mb="md" hiddenFrom="md">
            {brandLogo && <Image src={brandLogo} h={36} w="auto" alt={brandName} />}
            <Text size="xl" fw={800}>{brandName}</Text>
          </Group>

          <Title order={2} ta="center" mb={4}>Client Area Login</Title>
          <Text c="dimmed" size="sm" ta="center" mb={rem(32)}>
            Sign in to manage your services
          </Text>

          <Paper withBorder shadow="sm" p="xl" radius="md">
            <form onSubmit={form.onSubmit(handleSubmit)}>
              <Stack gap="md">
                <TextInput label="Email or Phone" placeholder="you@company.com or 0712345678"
                  size="md" required {...form.getInputProps('identifier')} />
                <PasswordInput label="Password" placeholder="Your password"
                  size="md" required {...form.getInputProps('password')} />
                <Anchor component={Link} to="/forgot-password" size="sm" ta="right" display="block">
                  Forgot password?
                </Anchor>
                <Button fullWidth type="submit" size="md" mt="xs">Sign In</Button>
              </Stack>
            </form>
          </Paper>

          <Text c="dimmed" size="sm" ta="center" mt="lg">
            New to {brandName}?{' '}
            <Anchor component={Link} to="/portal/register" size="sm" fw={600}>
              Create an account
            </Anchor>
          </Text>
        </Box>
      </Box>
    </Box>
  );
}
