import { useEffect, useState } from 'react';
import {
  Box, Paper, Title, Text, Group, Stack, Button, SimpleGrid, TextInput,
  LoadingOverlay, Alert, Badge, Code, Divider, CopyButton, ActionIcon,
} from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { useParams } from 'react-router-dom';
import { IconWifi, IconCheck, IconCopy, IconAlertTriangle, IconClock } from '@tabler/icons-react';
import {
  getPublicWifiCheckoutInfo, submitPublicWifiCheckout, getPublicWifiPurchaseStatus,
  PublicWifiCheckoutInfo, PublicWifiPlan, PublicWifiPurchaseStatus,
} from '../../api/publicWifi';

const fmt = (n: number, currency = 'TZS') => `${currency} ${n.toLocaleString()}`;
const durationLabel = (p: PublicWifiPlan) => `${p.duration_value} ${p.duration_unit}`;

export default function WifiCheckout() {
  const { routerId, purchaseId } = useParams<{ routerId: string; purchaseId?: string }>();

  if (purchaseId) {
    return <VoucherStatus purchaseId={purchaseId} />;
  }
  return <CheckoutForm routerId={routerId!} />;
}

function CheckoutForm({ routerId }: { routerId: string }) {
  const [info, setInfo] = useState<PublicWifiCheckoutInfo | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [selected, setSelected] = useState<PublicWifiPlan | null>(null);
  const [phone, setPhone] = useState('');
  const [name, setName] = useState('');
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    getPublicWifiCheckoutInfo(routerId)
      .then((res) => setInfo(res.data.data))
      .catch(() => setError('This WiFi hotspot is not available right now.'))
      .finally(() => setLoading(false));
  }, [routerId]);

  const handlePay = async () => {
    if (!selected || !phone.trim()) return;
    setSubmitting(true);
    try {
      const res = await submitPublicWifiCheckout(routerId, {
        phone: phone.trim(), name: name.trim() || undefined, wifi_plan_id: selected.id,
      });
      if (res.data.data.redirect_url) {
        window.location.href = res.data.data.redirect_url;
      }
    } catch (e: any) {
      notifications.show({ message: e?.response?.data?.message ?? 'Could not start payment. Please try again.', color: 'red' });
      setSubmitting(false);
    }
  };

  return (
    <Box maw={480} mx="auto" mt="xl" px="md" pos="relative">
      <LoadingOverlay visible={loading} />
      <Stack align="center" mb="lg">
        <IconWifi size={40} color="var(--mantine-color-blue-6)" />
        <Title order={3} ta="center">{info?.tenant.name ?? 'WiFi'} — {info?.router.name}</Title>
        <Text c="dimmed" size="sm" ta="center">Choose a plan, pay, and get connected in minutes.</Text>
      </Stack>

      {error ? (
        <Alert color="red" icon={<IconAlertTriangle size={18} />}>{error}</Alert>
      ) : info && (
        <Stack>
          <SimpleGrid cols={{ base: 1, xs: 2 }}>
            {info.plans.map((p) => (
              <Paper key={p.id} withBorder p="md" radius="md"
                style={{
                  cursor: 'pointer',
                  borderColor: selected?.id === p.id ? 'var(--mantine-color-blue-6)' : undefined,
                  borderWidth: selected?.id === p.id ? 2 : 1,
                }}
                onClick={() => setSelected(p)}>
                <Text fw={600}>{p.name}</Text>
                <Text size="xl" fw={800} c="blue">{fmt(p.price, info.tenant.currency)}</Text>
                <Text size="xs" c="dimmed">{durationLabel(p)} of access</Text>
              </Paper>
            ))}
          </SimpleGrid>

          {info.plans.length === 0 && (
            <Alert color="yellow">No plans are available on this hotspot yet.</Alert>
          )}

          {selected && (
            <Paper withBorder p="md" radius="md">
              <Stack>
                <TextInput label="Phone Number" required placeholder="e.g. 0712345678"
                  value={phone} onChange={(e) => setPhone(e.currentTarget.value)} />
                <TextInput label="Name (optional)" value={name} onChange={(e) => setName(e.currentTarget.value)} />
                <Button size="md" fullWidth loading={submitting} disabled={!phone.trim()} onClick={handlePay}>
                  Pay {fmt(selected.price, info.tenant.currency)}
                </Button>
              </Stack>
            </Paper>
          )}
        </Stack>
      )}
    </Box>
  );
}

const hotspotLoginUrl = (localLoginHost: string, code: string) =>
  `http://${localLoginHost}/login?username=${encodeURIComponent(code)}&password=${encodeURIComponent(code)}`;

function VoucherStatus({ purchaseId }: { purchaseId: string }) {
  const [status, setStatus] = useState<PublicWifiPurchaseStatus | null>(null);
  const [autoTried, setAutoTried] = useState(false);

  useEffect(() => {
    let stopped = false;
    let timer: ReturnType<typeof setTimeout>;

    const check = () => {
      getPublicWifiPurchaseStatus(purchaseId).then((res) => {
        if (stopped) return;
        setStatus(res.data.data);
        if (res.data.data.status === 'pending') {
          timer = setTimeout(check, 3000);
        }
      });
    };
    check();

    return () => { stopped = true; clearTimeout(timer); };
  }, [purchaseId]);

  // Give the customer a couple seconds to see their code, then try to
  // connect them automatically by sending their own browser (still on the
  // hotspot's WiFi) straight to the router's local login endpoint. If it's
  // unreachable (they've left the WiFi, or the owner hasn't set a local
  // login IP) the code above is still on screen as a fallback.
  useEffect(() => {
    if (status?.status !== 'completed' || !status.local_login_host || !status.hotspot_username || autoTried) return;
    const timer = setTimeout(() => {
      setAutoTried(true);
      window.location.href = hotspotLoginUrl(status.local_login_host!, status.hotspot_username!);
    }, 2500);
    return () => clearTimeout(timer);
  }, [status, autoTried]);

  return (
    <Box maw={480} mx="auto" mt="xl" px="md">
      <Paper withBorder p="lg" radius="md">
        {!status || status.status === 'pending' ? (
          <Stack align="center" py="lg">
            <IconClock size={40} color="var(--mantine-color-blue-6)" />
            <Title order={4}>Confirming your payment…</Title>
            <Text c="dimmed" size="sm" ta="center">This usually takes a few seconds. Please don't close this page.</Text>
          </Stack>
        ) : status.status === 'failed' ? (
          <Stack align="center" py="lg">
            <IconAlertTriangle size={40} color="var(--mantine-color-red-6)" />
            <Title order={4}>Something went wrong</Title>
            <Text c="dimmed" size="sm" ta="center">Your payment could not be confirmed. Please try again or contact support.</Text>
          </Stack>
        ) : (
          <Stack align="center" py="lg">
            <IconCheck size={40} color="var(--mantine-color-green-6)" />
            <Title order={4}>You're all set!</Title>
            <Text c="dimmed" size="sm" ta="center">Enter this code on the WiFi login page to connect.</Text>
            <Group gap="xs">
              <Code fz="xl" p="sm">{status.hotspot_username}</Code>
              <CopyButton value={status.hotspot_username ?? ''}>
                {({ copied, copy }) => (
                  <ActionIcon variant="light" color={copied ? 'green' : 'blue'} size="lg" onClick={copy}>
                    <IconCopy size={16} />
                  </ActionIcon>
                )}
              </CopyButton>
            </Group>
            <Text size="xs" c="dimmed">Username and password are the same code.</Text>
            {status.voucher_expires_at && (
              <Badge variant="light" color="blue">
                Valid until {new Date(status.voucher_expires_at).toLocaleString()}
              </Badge>
            )}
            {status.local_login_host && status.hotspot_username && (
              <>
                <Text size="sm" c="dimmed" ta="center">
                  {autoTried ? "Didn't connect automatically? Tap below." : 'Connecting you to WiFi automatically…'}
                </Text>
                <Button
                  fullWidth
                  leftSection={<IconWifi size={16} />}
                  onClick={() => { window.location.href = hotspotLoginUrl(status.local_login_host!, status.hotspot_username!); }}
                >
                  Connect Now
                </Button>
              </>
            )}
            <Divider w="100%" my="xs" />
            <Text size="xs" c="dimmed" ta="center">
              A copy has also been sent to your phone.
            </Text>
          </Stack>
        )}
      </Paper>
    </Box>
  );
}
