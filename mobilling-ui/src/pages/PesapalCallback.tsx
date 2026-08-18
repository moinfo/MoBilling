import { useEffect, useState } from 'react';
import { useSearchParams, useNavigate } from 'react-router-dom';
import { Container, Paper, Stack, Text, Loader, ThemeIcon, Button, Group, CopyButton, Code } from '@mantine/core';
import { IconCheck, IconX, IconClock, IconCopy } from '@tabler/icons-react';
import api from '../api/axios';

type Status = 'loading' | 'completed' | 'pending' | 'failed';

export default function PesapalCallback() {
  const [searchParams] = useSearchParams();
  const navigate = useNavigate();
  const [status, setStatus] = useState<Status>('loading');
  const [type, setType] = useState<string | null>(null);
  const [licenseKey, setLicenseKey] = useState<string | null>(null);

  const orderTrackingId = searchParams.get('OrderTrackingId');

  useEffect(() => {
    if (!orderTrackingId) {
      setStatus('failed');
      return;
    }

    let cancelled = false;
    let attemptsLeft = 6; // license purchases only: give the IPN a little time to land

    const checkStatus = async () => {
      try {
        const res = await api.get('/pesapal/callback', {
          params: { OrderTrackingId: orderTrackingId },
        });
        if (cancelled) return;
        const data = res.data;
        setType(data.type);
        setLicenseKey(data.license_key || null);

        if (data.status === 'active' || data.status === 'completed') {
          setStatus('completed');
          return;
        }
        if (data.status === 'failed' || data.status === 'cancelled') {
          setStatus('failed');
          return;
        }
        setStatus('pending');

        // A license purchase has no account/dashboard to check back from
        // later — this page is the only place the key is ever shown, so
        // it's worth a few retries if the IPN just hasn't landed yet.
        if (data.type === 'license_purchase' && attemptsLeft > 0) {
          attemptsLeft -= 1;
          setTimeout(checkStatus, 3000);
        }
      } catch {
        if (!cancelled) setStatus('failed');
      }
    };

    checkStatus();
    return () => { cancelled = true; };
  }, [orderTrackingId]);

  const icon = status === 'completed'
    ? { Icon: IconCheck, color: 'green' }
    : status === 'failed'
    ? { Icon: IconX, color: 'red' }
    : { Icon: IconClock, color: 'yellow' };

  const isLicensePurchase = type === 'license_purchase';

  const title = status === 'loading' ? 'Verifying payment...'
    : status === 'completed' ? (isLicensePurchase ? 'Your license is ready!' : 'Payment successful!')
    : status === 'failed' ? 'Payment failed'
    : 'Payment is being processed';

  const description = status === 'loading' ? 'Please wait while we confirm your payment with Pesapal.'
    : status === 'completed'
      ? (isLicensePurchase ? 'Save this key — you\'ll need it during setup on your own server.' : 'Your payment has been confirmed. Thank you!')
    : status === 'failed'
      ? (isLicensePurchase ? 'The payment could not be completed. Please try again — no license was issued.' : 'The payment could not be completed. Please try again or contact support.')
    : isLicensePurchase
      ? 'This can take a few moments. If a license was issued, it\'ll appear below shortly — otherwise, contact support with your payment reference.'
      : 'Your payment is still being processed. This may take a few minutes. You can check back later.';

  const destination = type === 'sms_purchase' ? '/sms' : '/subscription';

  return (
    <Container size="sm" py={100}>
      <Paper withBorder p="xl" radius="md" ta="center">
        <Stack align="center" gap="md">
          {status === 'loading' ? (
            <Loader size="lg" />
          ) : (
            <ThemeIcon size={64} radius="xl" color={icon.color} variant="light">
              <icon.Icon size={32} />
            </ThemeIcon>
          )}

          <Text size="xl" fw={700}>{title}</Text>
          <Text c="dimmed" maw={400}>{description}</Text>

          {isLicensePurchase && status === 'completed' && licenseKey && (
            <Group gap="xs" mt="xs">
              <Code fz="md" px="sm" py={6}>{licenseKey}</Code>
              <CopyButton value={licenseKey}>
                {({ copied, copy }) => (
                  <Button size="xs" variant="light" color={copied ? 'teal' : 'blue'} leftSection={<IconCopy size={14} />} onClick={copy}>
                    {copied ? 'Copied' : 'Copy'}
                  </Button>
                )}
              </CopyButton>
            </Group>
          )}

          {status !== 'loading' && (
            <Group mt="md">
              {isLicensePurchase ? (
                <Button component="a" href="https://wa.me/255689011111" target="_blank">
                  Contact Support
                </Button>
              ) : (
                <>
                  <Button onClick={() => navigate(destination)}>
                    {type === 'sms_purchase' ? 'Go to SMS' : 'Go to Subscription'}
                  </Button>
                  <Button variant="default" onClick={() => navigate('/dashboard')}>
                    Dashboard
                  </Button>
                </>
              )}
            </Group>
          )}
        </Stack>
      </Paper>
    </Container>
  );
}
