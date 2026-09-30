import { useState } from 'react';
import { Stack, Paper, Title, Text, Group, Badge, Table, Button, NumberInput, Alert } from '@mantine/core';
import { useQuery, useMutation } from '@tanstack/react-query';
import { notifications } from '@mantine/notifications';
import { IconWallet, IconInfoCircle } from '@tabler/icons-react';
import { getWallet, topupWalletPesapal } from '../api/wallet';
import { formatCurrency } from '../utils/formatCurrency';

const TYPE_COLOR: Record<string, string> = { topup: 'green', debit: 'red', refund: 'blue' };

/** A white-label reseller tenant's own prepaid wallet — balance, ledger, top up. */
export default function Wallet() {
  const [amount, setAmount] = useState<number | ''>(50000);
  const { data, isLoading, refetch } = useQuery({ queryKey: ['wallet'], queryFn: getWallet });
  const wallet = data?.data?.data;

  const topupMut = useMutation({
    mutationFn: () => topupWalletPesapal(Number(amount)),
    onSuccess: (res) => {
      if (res.data.data.redirect_url) {
        window.location.href = res.data.data.redirect_url;
      } else {
        notifications.show({ message: res.data.message, color: 'green' });
        refetch();
      }
    },
    onError: (e: any) => notifications.show({ message: e.response?.data?.message || 'Could not start the top-up.', color: 'red' }),
  });

  if (!isLoading && wallet && !wallet.is_wallet_gated) {
    return (
      <Stack gap="lg">
        <Group gap="xs"><IconWallet size={22} /><Title order={3}>Wallet</Title></Group>
        <Alert icon={<IconInfoCircle size={16} />} color="gray">This account does not use a prepaid wallet.</Alert>
      </Stack>
    );
  }

  return (
    <Stack gap="lg">
      <Group gap="xs"><IconWallet size={22} /><Title order={3}>Wallet</Title></Group>

      <Paper withBorder p="lg" radius="md">
        <Text size="xs" c="dimmed">Balance</Text>
        <Text size="xl" fw={700}>{formatCurrency(wallet?.balance ?? 0)}</Text>
        <Text size="xs" c="dimmed" mt={4}>
          Fulfillment (hosting/email provisioning, domain registration) is auto-charged from this wallet at our cost
          price. If the balance is too low, the order is held until you top up.
        </Text>

        {wallet?.pesapal_configured ? (
          <Group mt="md" align="flex-end">
            <NumberInput label="Top up amount" value={amount} onChange={(v) => setAmount(v as number)} min={1000} step={5000} style={{ width: 200 }} />
            <Button loading={topupMut.isPending} onClick={() => topupMut.mutate()} leftSection={<IconWallet size={16} />}>
              Top up via Pesapal
            </Button>
          </Group>
        ) : (
          <Alert icon={<IconInfoCircle size={16} />} color="yellow" mt="md">
            Online top-up isn't available yet — set up your own Pesapal account in Settings, or contact your provider
            to top up your wallet.
          </Alert>
        )}
      </Paper>

      <Paper withBorder p="md" radius="md">
        <Title order={5} mb="sm">Recent activity</Title>
        {!wallet?.ledger?.length ? (
          <Text size="sm" c="dimmed">No wallet activity yet.</Text>
        ) : (
          <Table>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Date</Table.Th>
                <Table.Th>Type</Table.Th>
                <Table.Th>Amount</Table.Th>
                <Table.Th>Balance after</Table.Th>
                <Table.Th>Notes</Table.Th>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {wallet.ledger.map((row) => (
                <Table.Tr key={row.id}>
                  <Table.Td>{new Date(row.created_at).toLocaleString()}</Table.Td>
                  <Table.Td><Badge size="sm" color={TYPE_COLOR[row.type]} variant="light">{row.type}</Badge></Table.Td>
                  <Table.Td>{formatCurrency(row.amount)}</Table.Td>
                  <Table.Td>{formatCurrency(row.balance_after)}</Table.Td>
                  <Table.Td><Text size="xs" c="dimmed">{row.notes}</Text></Table.Td>
                </Table.Tr>
              ))}
            </Table.Tbody>
          </Table>
        )}
      </Paper>
    </Stack>
  );
}
