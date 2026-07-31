import { useMemo, useState } from 'react';
import {
  Stack, Paper, Title, Text, Group, Button, TextInput, NumberInput, Radio,
  Divider, Badge, Alert, Table, Loader,
} from '@mantine/core';
import { useQuery, useMutation } from '@tanstack/react-query';
import { notifications } from '@mantine/notifications';
import { useNavigate, useSearchParams } from 'react-router-dom';
import {
  IconArrowLeft, IconSearch, IconCheck, IconX, IconAlertCircle, IconWorldWww,
} from '@tabler/icons-react';
import {
  getPortalDomainTlds, portalCheckDomain, portalOrderDomain,
} from '../../api/portal';
import { formatTsh } from '../../data/storefront';

type Action = 'register' | 'transfer';

export default function OrderDomain() {
  const [searchParams] = useSearchParams();
  const navigate = useNavigate();

  const initialAction = searchParams.get('action') === 'transfer' ? 'transfer' : 'register';
  const [action, setAction] = useState<Action>(initialAction);
  const [domain, setDomain] = useState(searchParams.get('query') ?? '');
  const [years, setYears] = useState(1);
  const [authInfo, setAuthInfo] = useState('');
  const [checked, setChecked] = useState<{ name: string; available: boolean } | null>(null);

  const { data: tldRes, isLoading: tldsLoading } = useQuery({
    queryKey: ['portal-domain-tlds'],
    queryFn: getPortalDomainTlds,
  });
  const tlds = tldRes?.data?.data ?? [];

  const activeTld = useMemo(() => {
    const suffix = domain.toLowerCase().split('.').slice(1).join('.');
    return tlds.find((t) => t.tld.replace(/^\./, '') === suffix);
  }, [domain, tlds]);

  const price = activeTld
    ? (action === 'register' ? activeTld.register_price : activeTld.transfer_price) * years
    : 0;

  const checkMutation = useMutation({
    mutationFn: () => portalCheckDomain(domain.trim().toLowerCase()),
    onSuccess: (res: any) => {
      // /portal/domains/check returns { name, available, pricing } flat.
      setChecked({
        name: res?.data?.name ?? domain.trim().toLowerCase(),
        available: !!res?.data?.available,
      });
    },
    onError: (e: any) => {
      setChecked(null);
      notifications.show({
        message: e?.response?.data?.message ?? 'Could not check that domain right now.',
        color: 'red',
      });
    },
  });

  const orderMutation = useMutation({
    mutationFn: () => portalOrderDomain({
      name: domain.trim().toLowerCase(),
      years,
      action,
      auth_info: action === 'transfer' ? authInfo.trim() : undefined,
    }),
    onSuccess: (res: any) => {
      notifications.show({
        title: action === 'register' ? 'Domain ordered' : 'Transfer started',
        message: res?.data?.message ?? 'Pay the invoice to complete your order.',
        color: 'green',
        autoClose: 10000,
      });
      const id = res?.data?.data?.document_id;
      navigate(id ? `/portal/invoices/${id}` : '/portal/domains');
    },
    onError: (e: any) => notifications.show({
      title: 'Could not complete the order',
      message: e?.response?.data?.message ?? 'Something went wrong — please try again.',
      color: 'red',
      autoClose: 10000,
    }),
  });

  const looksLikeDomain = /^[a-z0-9-]+(\.[a-z0-9-]+)+$/i.test(domain.trim());
  const unsupportedTld = looksLikeDomain && !tldsLoading && !activeTld;
  const isChecked = checked?.name === domain.trim().toLowerCase();
  // Registering needs a free name; transferring needs one that already exists.
  const availabilityOk = isChecked
    && (action === 'register' ? checked!.available : !checked!.available);
  const canOrder = looksLikeDomain && !!activeTld && availabilityOk
    && (action !== 'transfer' || !!authInfo.trim());

  return (
    <Stack gap="lg" maw={860}>
      <Group gap="xs">
        <Button
          variant="subtle"
          size="compact-sm"
          leftSection={<IconArrowLeft size={16} />}
          onClick={() => navigate('/order')}
        >
          All services
        </Button>
      </Group>

      <div>
        <Title order={3}>Domains</Title>
        <Text c="dimmed" size="sm">Register a new domain or move an existing one to us.</Text>
      </div>

      <Paper withBorder p="lg" radius="md">
        <Radio.Group
          value={action}
          onChange={(v) => { setAction(v as Action); setChecked(null); }}
          mb="md"
        >
          <Group gap="lg">
            <Radio value="register" label="Register a new domain" />
            <Radio value="transfer" label="Transfer to us" />
          </Group>
        </Radio.Group>

        <Group align="flex-end" gap="sm">
          <TextInput
            style={{ flex: 1 }}
            label="Domain name"
            placeholder="mycompany.co.tz"
            value={domain}
            onChange={(e) => { setDomain(e.currentTarget.value); setChecked(null); }}
            onKeyDown={(e) => {
              if (e.key === 'Enter' && looksLikeDomain) checkMutation.mutate();
            }}
            leftSection={<IconWorldWww size={16} />}
            error={unsupportedTld ? "We don't currently offer that extension." : undefined}
          />
          <Button
            leftSection={<IconSearch size={16} />}
            onClick={() => checkMutation.mutate()}
            loading={checkMutation.isPending}
            disabled={!looksLikeDomain || unsupportedTld}
          >
            Check
          </Button>
        </Group>

        {isChecked && (
          <Alert
            mt="md"
            color={availabilityOk ? 'green' : 'red'}
            icon={availabilityOk ? <IconCheck size={18} /> : <IconX size={18} />}
          >
            {action === 'register'
              ? (checked!.available
                ? `${checked!.name} is available — ${formatTsh(price)} for ${years} year${years > 1 ? 's' : ''}.`
                : `${checked!.name} is already taken. Try another name.`)
              : (!checked!.available
                ? `${checked!.name} is registered and can be transferred to us.`
                : `${checked!.name} isn't registered — there's nothing to transfer.`)}
          </Alert>
        )}

        {activeTld && (
          <NumberInput
            mt="md"
            label={action === 'register' ? 'Registration period (years)' : 'Extend by (years)'}
            min={activeTld.years_min}
            max={activeTld.years_max}
            value={years}
            onChange={(v) => setYears(Number(v) || 1)}
          />
        )}

        {action === 'transfer' && (
          <TextInput
            mt="md"
            label="Authorisation (EPP) code"
            description="Get this from your current registrar."
            value={authInfo}
            onChange={(e) => setAuthInfo(e.currentTarget.value)}
            required
          />
        )}

        {activeTld && (
          <>
            <Divider my="md" />
            <Group justify="space-between">
              <Text fw={700}>Total</Text>
              <Text fw={700} size="lg">{formatTsh(price)}</Text>
            </Group>
            <Text c="dimmed" size="xs" mt={4}>
              Excludes tax. Your invoice will show the exact amount.
            </Text>
          </>
        )}

        <Button
          mt="md"
          fullWidth
          size="md"
          onClick={() => orderMutation.mutate()}
          loading={orderMutation.isPending}
          disabled={!canOrder}
        >
          {action === 'register' ? 'Register domain' : 'Start transfer'}
        </Button>
        {looksLikeDomain && !isChecked && (
          <Text c="dimmed" size="xs" ta="center" mt={6}>
            Check availability first.
          </Text>
        )}
      </Paper>

      <Paper withBorder p="lg" radius="md">
        <Title order={5} mb="sm">Our domain pricing</Title>
        {tldsLoading ? <Group justify="center" p="md"><Loader size="sm" /></Group> : (
          tlds.length === 0 ? (
            <Alert color="yellow" icon={<IconAlertCircle size={18} />}>
              No domain extensions are configured on your account yet.
            </Alert>
          ) : (
            <Table striped highlightOnHover>
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Extension</Table.Th>
                  <Table.Th>Register</Table.Th>
                  <Table.Th>Transfer</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {tlds.map((t) => (
                  <Table.Tr key={t.tld}>
                    <Table.Td>
                      <Badge variant="light">{t.tld.startsWith('.') ? t.tld : `.${t.tld}`}</Badge>
                    </Table.Td>
                    <Table.Td>{formatTsh(t.register_price)}/yr</Table.Td>
                    <Table.Td>{formatTsh(t.transfer_price)}/yr</Table.Td>
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>
          )
        )}
      </Paper>
    </Stack>
  );
}
