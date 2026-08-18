import { useEffect, useState } from 'react';
import {
  Container, Paper, Title, Text, Stepper, Button, Group, Stack, TextInput,
  PasswordInput, NumberInput, Center, Loader, ThemeIcon, Alert, Image,
} from '@mantine/core';
import { useForm } from '@mantine/form';
import { Link, useNavigate } from 'react-router-dom';
import {
  IconCheck, IconX, IconAlertTriangle, IconServerCog,
} from '@tabler/icons-react';
import {
  getInstallStatus, getInstallRequirements, testInstallDatabase, runInstallMigrations,
  checkInstallLicense, createInstallTenant, InstallRequirements,
} from '../api/install';

export default function Install() {
  const navigate = useNavigate();
  const [checkingStatus, setCheckingStatus] = useState(true);
  const [alreadyInstalled, setAlreadyInstalled] = useState(false);
  const [active, setActive] = useState(0);
  const [licenseKey, setLicenseKey] = useState('');

  useEffect(() => {
    getInstallStatus()
      .then((res) => setAlreadyInstalled(res.data.installed))
      .catch(() => setAlreadyInstalled(false))
      .finally(() => setCheckingStatus(false));
  }, []);

  if (checkingStatus) {
    return <Center h="100vh"><Loader /></Center>;
  }

  if (alreadyInstalled) {
    return (
      <Center h="100vh" p="md">
        <Paper withBorder p="xl" radius="md" maw={420}>
          <Stack align="center">
            <ThemeIcon size={48} radius="xl" color="green" variant="light"><IconCheck size={28} /></ThemeIcon>
            <Title order={3} ta="center">Already Installed</Title>
            <Text c="dimmed" ta="center" size="sm">This MoBilling install is already set up.</Text>
            <Button component={Link} to="/login" fullWidth mt="sm">Go to Login</Button>
          </Stack>
        </Paper>
      </Center>
    );
  }

  return (
    <Container size="sm" py={{ base: 32, sm: 64 }}>
      <Stack align="center" mb="xl">
        <Image src="/moinfotech-logo.png" h={40} w="auto" alt="MoBilling" />
        <Title order={2} ta="center">MoBilling Setup</Title>
        <Text c="dimmed" ta="center" size="sm">Let's get your self-hosted install running.</Text>
      </Stack>

      <Paper withBorder p={{ base: 'md', sm: 'xl' }} radius="md">
        <Stepper active={active} onStepClick={() => {}} allowNextStepsSelect={false} size="sm">
          <Stepper.Step label="Requirements" description="Server check">
            <RequirementsStep onNext={() => setActive(1)} />
          </Stepper.Step>
          <Stepper.Step label="Database" description="Connect & migrate">
            <DatabaseStep onNext={() => setActive(2)} />
          </Stepper.Step>
          <Stepper.Step label="License" description="Activate">
            <LicenseStep onNext={(key) => { setLicenseKey(key); setActive(3); }} />
          </Stepper.Step>
          <Stepper.Step label="Admin" description="Your account">
            <AdminStep licenseKey={licenseKey} onDone={() => setActive(4)} />
          </Stepper.Step>
          <Stepper.Completed>
            <Stack align="center" py="xl">
              <ThemeIcon size={56} radius="xl" color="green" variant="light"><IconCheck size={32} /></ThemeIcon>
              <Title order={3}>Installation Complete</Title>
              <Text c="dimmed" ta="center">Your MoBilling install is ready.</Text>
              <Button onClick={() => navigate('/login')} mt="sm">Go to Login</Button>
            </Stack>
          </Stepper.Completed>
        </Stepper>
      </Paper>
    </Container>
  );
}

function CheckRow({ ok, label }: { ok: boolean; label: string }) {
  return (
    <Group gap="xs" wrap="nowrap">
      <ThemeIcon size={18} radius="xl" color={ok ? 'green' : 'red'} variant="light">
        {ok ? <IconCheck size={12} /> : <IconX size={12} />}
      </ThemeIcon>
      <Text size="sm">{label}</Text>
    </Group>
  );
}

function RequirementsStep({ onNext }: { onNext: () => void }) {
  const [data, setData] = useState<InstallRequirements | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = () => {
    setLoading(true);
    setError(null);
    getInstallRequirements()
      .then((res) => setData(res.data))
      .catch((err) => setError(err.response?.data?.message || 'Could not check requirements'))
      .finally(() => setLoading(false));
  };

  useEffect(load, []);

  if (loading) return <Center py="xl"><Loader /></Center>;
  if (error) return <Alert color="red" icon={<IconAlertTriangle size={16} />}>{error}</Alert>;
  if (!data) return null;

  return (
    <Stack mt="md" gap="sm">
      <CheckRow ok={data.php_ok} label={`PHP ${data.php_version} (need 8.2+)`} />
      {data.extensions.map((e) => <CheckRow key={e.name} ok={e.loaded} label={`Extension: ${e.name}`} />)}
      {data.writable.map((w) => <CheckRow key={w.path} ok={w.writable} label={`Writable: ${w.path}`} />)}
      <CheckRow ok={data.env_writable} label=".env writable" />

      {!data.all_ok && (
        <Alert color="yellow" icon={<IconAlertTriangle size={16} />} mt="sm">
          Fix the items marked with a red ✕ above, then re-check.
        </Alert>
      )}

      <Group justify="flex-end" mt="md">
        <Button variant="default" onClick={load}>Re-check</Button>
        <Button onClick={onNext} disabled={!data.all_ok}>Next</Button>
      </Group>
    </Stack>
  );
}

function DatabaseStep({ onNext }: { onNext: () => void }) {
  const [stage, setStage] = useState<'form' | 'migrating' | 'error'>('form');
  const [errorMsg, setErrorMsg] = useState('');

  const form = useForm({
    initialValues: { host: '127.0.0.1', port: 3306, database: '', username: '', password: '' },
    validate: {
      host: (v) => (v.trim() ? null : 'Required'),
      database: (v) => (v.trim() ? null : 'Required'),
      username: (v) => (v.trim() ? null : 'Required'),
    },
  });

  const submit = async (values: typeof form.values) => {
    setErrorMsg('');
    try {
      await testInstallDatabase(values);
    } catch (err: any) {
      setErrorMsg(err.response?.data?.message || 'Could not connect to that database.');
      setStage('error');
      return;
    }

    setStage('migrating');
    try {
      await runInstallMigrations();
      onNext();
    } catch (err: any) {
      setErrorMsg(err.response?.data?.message || 'Migration failed.');
      setStage('error');
    }
  };

  if (stage === 'migrating') {
    return <Center py="xl"><Stack align="center"><Loader /><Text size="sm" c="dimmed">Creating database tables…</Text></Stack></Center>;
  }

  return (
    <form onSubmit={form.onSubmit(submit)}>
      <Stack mt="md">
        <Text size="sm" c="dimmed">Create an empty MySQL database first, then enter its credentials here.</Text>
        {stage === 'error' && <Alert color="red" icon={<IconAlertTriangle size={16} />}>{errorMsg}</Alert>}
        <TextInput label="Host" required {...form.getInputProps('host')} />
        <NumberInput label="Port" required {...form.getInputProps('port')} />
        <TextInput label="Database Name" required {...form.getInputProps('database')} />
        <TextInput label="Username" required {...form.getInputProps('username')} />
        <PasswordInput label="Password" {...form.getInputProps('password')} />
        <Group justify="flex-end" mt="md">
          <Button type="submit" loading={form.submitting}>Connect & Create Tables</Button>
        </Group>
      </Stack>
    </form>
  );
}

function LicenseStep({ onNext }: { onNext: (licenseKey: string) => void }) {
  const [loading, setLoading] = useState(false);
  const [errorMsg, setErrorMsg] = useState('');
  const form = useForm({
    initialValues: { license_key: '' },
    validate: { license_key: (v) => (v.trim() ? null : 'Required') },
  });

  const submit = async (values: typeof form.values) => {
    setLoading(true);
    setErrorMsg('');
    try {
      await checkInstallLicense(values.license_key);
      onNext(values.license_key);
    } catch (err: any) {
      setErrorMsg(err.response?.data?.message || 'Invalid license key.');
    } finally {
      setLoading(false);
    }
  };

  return (
    <form onSubmit={form.onSubmit(submit)}>
      <Stack mt="md">
        <Text size="sm" c="dimmed">Enter the license key from your MoBilling purchase.</Text>
        {errorMsg && <Alert color="red" icon={<IconAlertTriangle size={16} />}>{errorMsg}</Alert>}
        <TextInput label="License Key" placeholder="MB-XXXX-XXXX-XXXX-XXXX" required {...form.getInputProps('license_key')} />
        <Group justify="flex-end" mt="md">
          <Button type="submit" loading={loading}>Activate</Button>
        </Group>
      </Stack>
    </form>
  );
}

function AdminStep({ licenseKey, onDone }: { licenseKey: string; onDone: () => void }) {
  const [loading, setLoading] = useState(false);
  const [errorMsg, setErrorMsg] = useState('');
  const form = useForm({
    initialValues: {
      company_name: '', company_email: '', currency: 'TZS',
      admin_name: '', admin_email: '', admin_password: '', admin_password_confirmation: '',
    },
    validate: {
      company_name: (v) => (v.trim() ? null : 'Required'),
      company_email: (v) => (/^\S+@\S+\.\S+$/.test(v) ? null : 'Valid email required'),
      admin_name: (v) => (v.trim() ? null : 'Required'),
      admin_email: (v) => (/^\S+@\S+\.\S+$/.test(v) ? null : 'Valid email required'),
      admin_password: (v) => (v.length >= 8 ? null : 'At least 8 characters'),
      admin_password_confirmation: (v, values) => (v === values.admin_password ? null : 'Passwords do not match'),
    },
  });

  const submit = async (values: typeof form.values) => {
    setLoading(true);
    setErrorMsg('');
    try {
      await createInstallTenant({
        license_key: licenseKey,
        company_name: values.company_name,
        company_email: values.company_email,
        currency: values.currency,
        admin_name: values.admin_name,
        admin_email: values.admin_email,
        admin_password: values.admin_password,
      });
      onDone();
    } catch (err: any) {
      setErrorMsg(err.response?.data?.message || 'Could not complete installation.');
    } finally {
      setLoading(false);
    }
  };

  return (
    <form onSubmit={form.onSubmit(submit)}>
      <Stack mt="md">
        {errorMsg && <Alert color="red" icon={<IconAlertTriangle size={16} />}>{errorMsg}</Alert>}
        <Text fw={600} size="sm">Your Business</Text>
        <TextInput label="Company Name" required {...form.getInputProps('company_name')} />
        <TextInput label="Company Email" required {...form.getInputProps('company_email')} />
        <TextInput label="Currency" required {...form.getInputProps('currency')} />
        <Text fw={600} size="sm" mt="sm">Your Admin Account</Text>
        <TextInput label="Your Name" required {...form.getInputProps('admin_name')} />
        <TextInput label="Your Email" required {...form.getInputProps('admin_email')} />
        <PasswordInput label="Password" required {...form.getInputProps('admin_password')} />
        <PasswordInput label="Confirm Password" required {...form.getInputProps('admin_password_confirmation')} />
        <Group justify="flex-end" mt="md">
          <Button type="submit" loading={loading} leftSection={<IconServerCog size={16} />}>Finish Setup</Button>
        </Group>
      </Stack>
    </form>
  );
}
