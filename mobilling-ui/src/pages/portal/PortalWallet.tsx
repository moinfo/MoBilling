import { useState } from 'react';
import {
  Stack, Paper, Title, Text, Group, Badge, Table, Button, Modal, NumberInput, Center, Loader,
} from '@mantine/core';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { notifications } from '@mantine/notifications';
import { useNavigate } from 'react-router-dom';
import { IconWallet, IconPlus, IconArrowUpRight, IconArrowDownRight } from '@tabler/icons-react';
import { getPortalCredit, portalCreditTopup } from '../../api/portal';
import { formatCurrency } from '../../utils/formatCurrency';
import dayjs from 'dayjs';

const TYPE_LABEL: Record<string, string> = {
  deposit: 'Deposit',
  topup_consumed: 'Add Funds',
  applied_to_invoice: 'Applied to invoice',
  auto_renew: 'Auto-renew charge',
  refund: 'Refund',
  adjustment: 'Adjustment',
};

/** Client's own wallet: balance, deposit ledger, and a way to add funds. */
export default function PortalWallet() {
  const navigate = useNavigate();
  const qc = useQueryClient();
  const [topupOpen, setTopupOpen] = useState(false);
  const [amount, setAmount] = useState<number | ''>(20000);

  const { data, isLoading } = useQuery({ queryKey: ['portal-credit'], queryFn: getPortalCredit });
  const wallet = data?.data?.data;

  const topupMutation = useMutation({
    mutationFn: () => portalCreditTopup(Number(amount)),
    onSuccess: (res: any) => {
      qc.invalidateQueries({ queryKey: ['portal-credit'] });
      notifications.show({ title: 'Invoice created', message: res?.data?.message, color: 'green', autoClose: 8000 });
      setTopupOpen(false);
      navigate(`/pay/${res?.data?.data?.document_id}`);
    },
    onError: (e: any) => notifications.show({
      message: e?.response?.data?.message ?? 'Could not create the top-up invoice.', color: 'red',
    }),
  });

  if (isLoading) return <Center py="xl"><Loader /></Center>;

  return (
    <Stack gap="md">
      <Group justify="space-between">
        <Title order={3}>
          <Group gap="xs"><IconWallet size={22} /> Wallet</Group>
        </Title>
        <Button leftSection={<IconPlus size={16} />} onClick={() => setTopupOpen(true)}>
          Add Funds
        </Button>
      </Group>

      <Paper withBorder p="xl" radius="md">
        <Text size="sm" c="dimmed" tt="uppercase" fw={700}>Available balance</Text>
        <Text fz={40} fw={800} mt={4}>{formatCurrency(wallet?.balance ?? 0)}</Text>
        <Text size="xs" c="dimmed" mt={4}>
          Used automatically for auto-renew, or apply it to any unpaid invoice.
        </Text>
      </Paper>

      <Paper withBorder radius="md">
        <Group p="sm" pb={0}>
          <Text fw={600} size="sm">Recent activity</Text>
        </Group>
        {!wallet?.ledger?.length ? (
          <Center py="xl"><Text c="dimmed" size="sm">No wallet activity yet.</Text></Center>
        ) : (
          <Table.ScrollContainer minWidth={520}>
            <Table verticalSpacing="xs" fz="sm">
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Date</Table.Th>
                  <Table.Th>Type</Table.Th>
                  <Table.Th>Notes</Table.Th>
                  <Table.Th ta="right">Amount</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {wallet.ledger.map((row: any) => {
                  const positive = row.amount >= 0;
                  return (
                    <Table.Tr key={row.id}>
                      <Table.Td c="dimmed">{dayjs(row.created_at).format('DD MMM YYYY, HH:mm')}</Table.Td>
                      <Table.Td>
                        <Badge size="sm" variant="light" color={positive ? 'teal' : 'red'}
                          leftSection={positive ? <IconArrowUpRight size={12} /> : <IconArrowDownRight size={12} />}>
                          {TYPE_LABEL[row.type] ?? row.type}
                        </Badge>
                      </Table.Td>
                      <Table.Td c="dimmed">{row.notes ?? '—'}</Table.Td>
                      <Table.Td ta="right" fw={600} c={positive ? 'teal' : 'red'}>
                        {positive ? '+' : ''}{formatCurrency(row.amount)}
                      </Table.Td>
                    </Table.Tr>
                  );
                })}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        )}
      </Paper>

      <Modal opened={topupOpen} onClose={() => setTopupOpen(false)} title="Add Funds" centered>
        <Stack gap="sm">
          <Text size="sm" c="dimmed">
            An invoice is created for this amount — your wallet is credited automatically the moment it's paid.
          </Text>
          <NumberInput
            label="Amount (TZS)" required min={5000} max={10000000} step={5000}
            thousandSeparator="," value={amount} onChange={(v) => setAmount(v === '' ? '' : Number(v))}
          />
          <Group justify="flex-end" mt="xs">
            <Button variant="default" onClick={() => setTopupOpen(false)}>Cancel</Button>
            <Button disabled={!amount || Number(amount) < 5000} loading={topupMutation.isPending}
              onClick={() => topupMutation.mutate()}>
              Create Invoice
            </Button>
          </Group>
        </Stack>
      </Modal>
    </Stack>
  );
}
