import { useEffect, useState } from 'react';
import {
  Stack, Paper, Title, Text, Group, Badge, LoadingOverlay, Button, SimpleGrid,
  TextInput, NumberInput, Select, Table, ThemeIcon, List, Checkbox, Alert,
} from '@mantine/core';
import { useForm } from '@mantine/form';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { notifications } from '@mantine/notifications';
import { useNavigate } from 'react-router-dom';
import {
  IconWorldWww, IconWallet, IconSearch, IconRefresh,
  IconDiscount2, IconBolt, IconCheck, IconBuildingStore, IconInfoCircle,
} from '@tabler/icons-react';
import {
  getResellerStatus, subscribeReseller, checkResellerDomain, orderResellerDomain, renewResellerDomain,
  getResellerApplication, submitResellerApplication, ResellerApplicationCategory,
} from '../../api/reseller';
import { getPortalDomains, PortalDomain, getPortalProfile } from '../../api/portal';
import { formatCurrency } from '../../utils/formatCurrency';

const CATEGORY_OPTIONS: { value: ResellerApplicationCategory; label: string }[] = [
  { value: 'domain', label: 'Domain registration' },
  { value: 'hosting', label: 'Website hosting' },
  { value: 'email', label: 'Business email hosting' },
  { value: 'linode', label: 'Cloud servers (Linode)' },
];

function WhiteLabelResellerCard() {
  const qc = useQueryClient();
  const { data, isLoading } = useQuery({ queryKey: ['reseller-application'], queryFn: getResellerApplication });
  const { data: profileData } = useQuery({ queryKey: ['portal-profile-for-reseller-app'], queryFn: getPortalProfile });
  const application = data?.data?.data ?? null;

  const form = useForm({
    initialValues: {
      brand_name: '',
      requested_domain: '',
      categories: [] as ResellerApplicationCategory[],
      contact_name: '',
      contact_email: '',
      contact_phone: '',
    },
    validate: {
      brand_name: (v) => (v.trim() ? null : 'Brand name is required'),
      requested_domain: (v) => (/^(?!-)[a-z0-9-]{1,63}(?<!-)(\.(?!-)[a-z0-9-]{1,63}(?<!-))+$/i.test(v.trim()) ? null : 'Enter a valid domain, e.g. shop.example.com'),
      categories: (v) => (v.length ? null : 'Select at least one'),
      contact_name: (v) => (v.trim() ? null : 'Contact name is required'),
      contact_email: (v) => (/^\S+@\S+\.\S+$/.test(v) ? null : 'Enter a valid email'),
    },
  });

  useEffect(() => {
    const user = (profileData?.data as any)?.user;
    if (user && !form.values.contact_name && !application) {
      form.setValues({
        contact_name: user.name ?? '',
        contact_email: user.email ?? '',
        contact_phone: user.phone ?? '',
      });
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [profileData, application]);

  const submitMut = useMutation({
    mutationFn: () => submitResellerApplication({
      ...form.values,
      requested_domain: form.values.requested_domain.trim().toLowerCase(),
      contact_phone: form.values.contact_phone || undefined,
    }),
    onSuccess: (res) => {
      notifications.show({ title: 'Application submitted', message: res.data.message, color: 'green' });
      qc.invalidateQueries({ queryKey: ['reseller-application'] });
    },
    onError: (e: any) => notifications.show({ message: e.response?.data?.message || 'Could not submit your application.', color: 'red' }),
  });

  if (isLoading) {
    return <Stack pos="relative" mih={120}><LoadingOverlay visible /></Stack>;
  }

  return (
    <Paper withBorder p="lg" radius="md">
      <Group gap="xs" mb="sm">
        <IconBuildingStore size={20} />
        <Title order={4}>White-Label Reseller Program</Title>
      </Group>
      <Text size="sm" c="dimmed" mb="md">
        Get your own fully-branded billing platform — your own domain, your own admin login, your own clients and
        pricing — selling domains, hosting, email and cloud servers. You buy at our cost price through a prepaid
        wallet; your customers pay you at whatever price you set.
      </Text>

      {application ? (
        <Alert
          icon={<IconInfoCircle size={16} />}
          color={application.status === 'pending' ? 'yellow' : application.status === 'rejected' ? 'red' : 'green'}
          title={
            application.status === 'pending' ? 'Application pending review'
              : application.status === 'approved' ? 'Application approved'
              : application.status === 'provisioned' ? 'Your reseller account is live'
              : 'Application not approved'
          }
        >
          <Text size="sm">
            Brand: <b>{application.brand_name}</b> &middot; Domain: <b>{application.requested_domain}</b>
          </Text>
          {application.staff_note && application.status === 'rejected' && (
            <Text size="sm" mt={4}>Reason: {application.staff_note}</Text>
          )}
          {application.status === 'provisioned' && (
            <Text size="sm" mt={4}>Your team will share your login details separately.</Text>
          )}
        </Alert>
      ) : (
        <form onSubmit={form.onSubmit(() => submitMut.mutate())}>
          <Stack gap="sm">
            <SimpleGrid cols={{ base: 1, sm: 2 }}>
              <TextInput label="Brand name" placeholder="e.g. Acme Hosting" required {...form.getInputProps('brand_name')} />
              <TextInput label="Domain you'll use" placeholder="e.g. billing.acme.com" required {...form.getInputProps('requested_domain')} />
            </SimpleGrid>
            <Checkbox.Group label="What will you sell?" {...form.getInputProps('categories')}>
              <Group mt="xs" gap="md">
                {CATEGORY_OPTIONS.map((c) => (
                  <Checkbox key={c.value} value={c.value} label={c.label} />
                ))}
              </Group>
            </Checkbox.Group>
            <SimpleGrid cols={{ base: 1, sm: 3 }}>
              <TextInput label="Contact name" required {...form.getInputProps('contact_name')} />
              <TextInput label="Contact email" required {...form.getInputProps('contact_email')} />
              <TextInput label="Contact phone" {...form.getInputProps('contact_phone')} />
            </SimpleGrid>
            <Button type="submit" color="grape" leftSection={<IconBuildingStore size={16} />} loading={submitMut.isPending} mt="xs">
              Submit application
            </Button>
          </Stack>
        </form>
      )}
    </Paper>
  );
}

export default function PortalReseller() {
  const qc = useQueryClient();
  const navigate = useNavigate();
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

  const subscribeMut = useMutation({
    mutationFn: subscribeReseller,
    onSuccess: (res) => {
      notifications.show({ title: 'Invoice created', message: res.data.message, color: 'green', autoClose: 8000 });
      qc.invalidateQueries({ queryKey: ['reseller-status'] });
      navigate(`/pay/${res.data.data.document_id}`);
    },
    onError: (e: any) => notifications.show({ message: e.response?.data?.message || 'Could not create the membership invoice.', color: 'red' }),
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
    const price = status?.membership_price ?? 0;
    return (
      <Stack gap="lg">
        <Group gap="xs">
          <IconWorldWww size={22} />
          <Title order={3}>Become a Domain Reseller</Title>
        </Group>

        <Paper withBorder p="lg" radius="md">
          <Text size="sm" mb="md">
            As a reseller you buy .tz and other domains at our own <b>wholesale cost</b> — the same price we
            pay the registry — instead of retail. Perfect if you register or renew domains for your own clients.
          </Text>
          <List spacing="xs" size="sm" icon={<ThemeIcon color="grape" variant="light" size={20} radius="xl"><IconCheck size={13} /></ThemeIcon>}>
            <List.Item icon={<ThemeIcon color="grape" variant="light" size={20} radius="xl"><IconDiscount2 size={13} /></ThemeIcon>}>
              Wholesale pricing on domain registration, transfer and renewal
            </List.Item>
            <List.Item icon={<ThemeIcon color="grape" variant="light" size={20} radius="xl"><IconBolt size={13} /></ThemeIcon>}>
              Pay the membership fee any way you like — card, mobile money, bank transfer, or wallet credit
            </List.Item>
            <List.Item icon={<ThemeIcon color="grape" variant="light" size={20} radius="xl"><IconRefresh size={13} /></ThemeIcon>}>
              Renews automatically every year while your membership stays active
            </List.Item>
          </List>

          <Group justify="space-between" align="center" mt="lg">
            <div>
              <Text size="xs" c="dimmed">Annual membership fee</Text>
              <Text size="lg" fw={700}>{formatCurrency(price)}<Text span size="xs" c="dimmed"> /year</Text></Text>
            </div>
            <Group gap={6}>
              <ThemeIcon variant="light" color="teal" size="sm"><IconWallet size={14} /></ThemeIcon>
              <Text size="sm" c="dimmed">Wallet: {formatCurrency(status?.wallet_balance ?? 0)}</Text>
            </Group>
          </Group>

          <Button fullWidth mt="md" size="md" color="grape" leftSection={<IconWorldWww size={16} />}
            loading={subscribeMut.isPending} disabled={!status?.membership_price || subscribeMut.isPending}
            onClick={() => subscribeMut.mutate()}>
            Become a Reseller — {formatCurrency(price)}
          </Button>
          <Text size="xs" c="dimmed" ta="center" mt={6}>
            You'll get an invoice you can pay by card, mobile money, bank transfer, or wallet credit.
          </Text>
        </Paper>

        <Paper withBorder p="md" radius="md">
          <Title order={5} mb="sm">Wholesale prices you'll get</Title>
          {!status?.tlds.length ? (
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

        <WhiteLabelResellerCard />
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

      <WhiteLabelResellerCard />
    </Stack>
  );
}
