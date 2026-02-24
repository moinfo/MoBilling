import { useEffect, useState } from 'react';
import { useSearchParams, useNavigate } from 'react-router-dom';
import { Container, Paper, Stack, Text, Loader, ThemeIcon, Button, Group } from '@mantine/core';
import { IconCheck, IconX, IconClock } from '@tabler/icons-react';
import api from '../api/axios';

type Status = 'loading' | 'completed' | 'pending' | 'failed';

export default function PesapalCallback() {
  const [searchParams] = useSearchParams();
  const navigate = useNavigate();
  const [status, setStatus] = useState<Status>('loading');
  const [type, setType] = useState<string | null>(null);

  const orderTrackingId = searchParams.get('OrderTrackingId');

  useEffect(() => {
    if (!orderTrackingId) {
      setStatus('failed');
      return;
    }

    const checkStatus = async () => {
      try {
        const res = await api.get('/pesapal/callback', {
          params: { OrderTrackingId: orderTrackingId },
        });
        const data = res.data;
        setType(data.type);

        if (data.status === 'active' || data.status === 'completed') {
          setStatus('completed');
        } else if (data.status === 'failed' || data.status === 'cancelled') {
          setStatus('failed');
        } else {
          setStatus('pending');
        }
      } catch {
        setStatus('failed');
      }
    };

    checkStatus();
  }, [orderTrackingId]);

  const icon = status === 'completed'
    ? { Icon: IconCheck, color: 'green' }
    : status === 'failed'
    ? { Icon: IconX, color: 'red' }
    : { Icon: IconClock, color: 'yellow' };

  const title = status === 'loading' ? 'Verifying payment...'
    : status === 'completed' ? 'Payment successful!'
    : status === 'failed' ? 'Payment failed'
    : 'Payment is being processed';

  const description = status === 'loading' ? 'Please wait while we confirm your payment with Pesapal.'
    : status === 'completed' ? 'Your payment has been confirmed. Thank you!'
    : status === 'failed' ? 'The payment could not be completed. Please try again or contact support.'
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

          {status !== 'loading' && (
            <Group mt="md">
              <Button onClick={() => navigate(destination)}>
                {type === 'sms_purchase' ? 'Go to SMS' : 'Go to Subscription'}
              </Button>
              <Button variant="default" onClick={() => navigate('/dashboard')}>
                Dashboard
              </Button>
            </Group>
          )}
        </Stack>
      </Paper>
    </Container>
  );
}
