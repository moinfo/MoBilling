import { useState } from 'react';
import {
  Stack, Paper, Title, Text, Group, Badge, LoadingOverlay, Button, SimpleGrid,
  TextInput, NumberInput, Select, Alert, Table, ThemeIcon,
} from '@mantine/core';
import { useForm } from '@mantine/form';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { notifications } from '@mantine/notifications';
import { IconWorldWww, IconWallet, IconInfoCircle, IconSearch, IconRefresh } from '@tabler/icons-react';
import {
  getResellerStatus, checkResellerDomain, orderResellerDomain, renewResellerDomain,
} from '../../api/reseller';
import { getPortalDomains, PortalDomain } from '../../api/portal';
import { formatCurrency } from '../../utils/formatCurrency';

export default function PortalReseller() {
  const qc = useQueryClient();
  const [checkName, setCheckName] = useState('');
  const [checkResult, setCheckResult] = useState<{ name: string; available: boolean; pricing: { reseller_price: number; years_min: number; years_max: number } | null; message?: string } | null>(null);
  const [checking, setChecking] = useState(false);

  const { data, isLoading } = useQuery({ queryKey: ['reseller-status'], queryFn: getResellerStatus });
  const status = data?.data?.data;

  const { data: domainsData } = useQuery({
    queryKey: ['portal-domains'],
    queryFn: getPortalDomains,
    enabled: !!status?.is_reseller,
  });
  const domains: PortalDomain[] = domainsData?.data?.data ?? [];

  const orderForm = useForm({
    initialValues: { years: 1, action: 'register' as 'register' | 'transfer', auth_info: '' },
  });

  const orderMut = useMutation({
    mutationFn: () => orderResellerDomain({
      name: checkResult!.name,
      years: orderForm.values.years,
      action: orderForm.values.action,
      auth_info: orderForm.values.action === 'transfer' ? orderForm.values.auth_info : undefined,
    }),
    onSuccess: (res) => {
      notifications.show({ title: 'Order paid', message: res.data.message, color: 'green' });
      setCheckResult(null);
      setCheckName('');
      qc.invalidateQueries({ queryKey: ['reseller-status'] });
      qc.invalidateQueries({ queryKey: ['portal-domains'] });
    },
    onError: (e: any) => notifications.show({ message: e.response?.data?.message || 'Order failed.', color: 'red' }),
  });

  const renewMut = useMutation({
    mutationFn: ({ domainId, years }: { domainId: string; years: number }) => renewResellerDomain(domainId, years),
    onSuccess: (res) => {
      notifications.show({ title: 'Renewed', message: res.data.message, color: 'green' });
      qc.invalidateQueries({ queryKey: ['reseller-status'] });
      qc.invalidateQueries({ queryKey: ['portal-domains'] });
    },
    onError: (e: any) => notifications.show({ message: e.response?.data?.message || 'Renewal failed.', color: 'red' }),
  });

  const handleCheck = async () => {
    if (!checkName.trim()) return;
    setChecking(true);
    setCheckResult(null);
    try {
      const res = await checkResellerDomain(checkName.trim().toLowerCase());
      setCheckResult(res.data);
      orderForm.setFieldValue('action', 'register');
    } catch (e: any) {
      notifications.show({ message: e.response?.data?.message || 'Could not check availability.', color: 'red' });
    } finally {
      setChecking(false);
    }
  };

  if (isLoading) {
    return <Stack pos="relative" mih={200}><LoadingOverlay visible /></Stack>;
  }

  if (!status?.is_reseller) {
    return (
      <Stack gap="lg">
        <Group gap="xs">
          <IconWorldWww size={22} />
          <Title order={3}>Reseller</Title>
        </Group>
        <Alert icon={<IconInfoCircle size={18} />} color="blue" variant="light">
          You're not a domain reseller yet. As a reseller you can register, transfer and renew domains at our
          wholesale cost — the same price we pay the registry — paid straight from your wallet. Contact us to
          get set up with a reseller membership.
        </Alert>
      </Stack>
    );
  }

  const years = orderForm.values.years;
  const total = checkResult?.pricing ? checkResult.pricing.reseller_price * years : 0;

  return (
    <Stack gap="lg">
      <Group justify="space-between" align="center">
        <Group gap="xs">
          <IconWorldWww size={22} />
          <Title order={3}>Reseller</Title>
          <Badge color="grape" variant="light">
            {status.expire_date ? `Active until ${new Date(status.expire_date).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' })}` : 'Active'}
          </Badge>
        </Group>
        <Group gap={6}>
          <ThemeIcon variant="light" color="teal" size="sm"><IconWallet size={14} /></ThemeIcon>
          <Text size="sm" fw={600}>Wallet: {formatCurrency(status.wallet_balance)}</Text>
        </Group>
      </Group>

      <Paper withBorder p="md" radius="md">
        <Title order={5} mb="sm">Register or transfer a domain</Title>
        <Group align="flex-end" gap="sm" wrap="wrap">
          <TextInput
            label="Domain name" placeholder="example.co.tz" style={{ flex: 1, minWidth: 220 }}
            value={checkName} onChange={(e) => setCheckName(e.currentTarget.value)}
            onKeyDown={(e) => e.key === 'Enter' && handleCheck()}
          />
          <Button leftSection={<IconSearch size={14} />} loading={checking} onClick={handleCheck}>
            Check
          </Button>
        </Group>

        {checkResult && (
          <Paper withBorder p="sm" radius="md" mt="md" bg="var(--mantine-color-gray-0)">
            {!checkResult.pricing ? (
              <Text size="sm" c="red">{checkResult.message || `No reseller pricing for ${checkResult.name}.`}</Text>
            ) : !checkResult.available ? (
              <Text size="sm" c="red">{checkResult.name} is not available to register.</Text>
            ) : (
              <Stack gap="sm">
                <Text size="sm">
                  <b>{checkResult.name}</b> is available — wholesale price{' '}
                  <b>{formatCurrency(checkResult.pricing.reseller_price)}</b>/year.
                </Text>
                <Group grow>
                  <Select label="Action" data={[{ value: 'register', label: 'Register (new)' }, { value: 'transfer', label: 'Transfer in' }]}
                    {...orderForm.getInputProps('action')} />
                  <NumberInput label="Years" min={checkResult.pricing.years_min} max={checkResult.pricing.years_max}
                    {...orderForm.getInputProps('years')} />
                </Group>
                {orderForm.values.action === 'transfer' && (
                  <TextInput label="EPP / auth code" placeholder="Transfer code from the current registrar" required
                    {...orderForm.getInputProps('auth_info')} />
                )}
                <Group justify="space-between" align="center">
                  <Text size="sm" fw={700}>Total: {formatCurrency(total)}</Text>
                  <Button color="grape" loading={orderMut.isPending}
                    disabled={status.wallet_balance < total}
                    onClick={() => orderMut.mutate()}>
                    Pay from wallet
                  </Button>
                </Group>
                {status.wallet_balance < total && (
                  <Text size="xs" c="red">Insufficient wallet balance — top up your wallet first.</Text>
                )}
              </Stack>
            )}
          </Paper>
        )}
      </Paper>

      <Paper withBorder p="md" radius="md">
        <Title order={5} mb="sm">Wholesale pricing</Title>
        {status.tlds.length === 0 ? (
          <Text size="sm" c="dimmed">No TLDs are configured for reseller pricing yet — contact us.</Text>
        ) : (
          <SimpleGrid cols={{ base: 2, sm: 4 }}>
            {status.tlds.map((t) => (
              <div key={t.tld}>
                <Text size="xs" c="dimmed">.{t.tld}</Text>
                <Text size="sm" fw={600}>{formatCurrency(t.reseller_price)}/yr</Text>
              </div>
            ))}
          </SimpleGrid>
        )}
      </Paper>

      <Paper withBorder p="md" radius="md">
        <Title order={5} mb="sm">Renew my domains at wholesale</Title>
        {domains.length === 0 ? (
          <Text size="sm" c="dimmed">You don't have any domains yet.</Text>
        ) : (
          <Table>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Domain</Table.Th>
                <Table.Th>Status</Table.Th>
                <Table.Th>Expires</Table.Th>
                <Table.Th></Table.Th>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {domains.map((d) => {
                const tld = d.name.split('.').slice(1).join('.');
                const pricing = status.tlds.find((t) => t.tld === tld);
                return (
                  <Table.Tr key={d.id}>
                    <Table.Td fw={500}>{d.name}</Table.Td>
                    <Table.Td><Badge size="sm" variant="light">{d.status}</Badge></Table.Td>
                    <Table.Td>{d.expires_at ? new Date(d.expires_at).toLocaleDateString('en-GB') : '—'}</Table.Td>
                    <Table.Td>
                      {pricing ? (
                        <Button size="xs" variant="light" color="grape" leftSection={<IconRefresh size={13} />}
                          loading={renewMut.isPending}
                          disabled={status.wallet_balance < pricing.reseller_price}
                          onClick={() => renewMut.mutate({ domainId: d.id, years: 1 })}>
                          Renew 1yr — {formatCurrency(pricing.reseller_price)}
                        </Button>
                      ) : (
                        <Text size="xs" c="dimmed">No reseller price for .{tld}</Text>
                      )}
                    </Table.Td>
                  </Table.Tr>
                );
              })}
            </Table.Tbody>
          </Table>
        )}
      </Paper>
    </Stack>
  );
}
