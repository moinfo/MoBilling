import { useState } from 'react';
import {
  Stack, Paper, Title, Text, Group, LoadingOverlay, Grid, Button, NavLink,
  SimpleGrid, Modal, TextInput, Badge, Divider, Center, Radio, Select, Alert,
  Checkbox, UnstyledButton,
} from '@mantine/core';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { notifications } from '@mantine/notifications';
import { useNavigate } from 'react-router-dom';
import {
  IconShoppingCart, IconRefresh, IconWorldWww, IconArrowRight, IconReceipt,
  IconCheck, IconPlus, IconArrowLeft,
} from '@tabler/icons-react';
import {
  getPortalCatalog, placePortalOrder, getPortalDomainTlds, getPortalDomainAddons,
  getPortalProductAddons, portalCheckDomain, CatalogGroup, CatalogProduct,
  DomainAddonRow, ProductAddonRow,
} from '../../api/portal';

const fmt = (n: number) => n.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 });

const cycleLabel: Record<string, string> = {
  once: 'One-time',
  monthly: 'Monthly',
  quarterly: 'Quarterly',
  half_yearly: 'Semi-Annually',
  yearly: 'Annually',
};

export default function PortalProductServices() {
  const navigate = useNavigate();
  const [activeGroup, setActiveGroup] = useState<string | null>(null);
  const [ordering, setOrdering] = useState<CatalogProduct | null>(null);

  const { data, isLoading } = useQuery({ queryKey: ['portal-catalog'], queryFn: getPortalCatalog });
  const groups: CatalogGroup[] = data?.data?.data ?? [];
  const current = groups.find((g) => g.name === (activeGroup ?? groups[0]?.name));

  return (
    <Stack gap="lg" pos="relative">
      <LoadingOverlay visible={isLoading} />
      <Group gap="xs">
        <IconShoppingCart size={22} />
        <Title order={3}>Shopping Cart</Title>
      </Group>

      <Grid gutter="lg">
        {/* ── Sidebar ── */}
        <Grid.Col span={{ base: 12, md: 3 }}>
          <Stack gap="lg">
            <Paper withBorder radius="md" p="xs">
              <Group gap="xs" px="sm" pt="sm" pb="xs">
                <IconShoppingCart size={16} />
                <Text fw={700}>Categories</Text>
              </Group>
              {groups.map((g) => {
                const active = g.name === (activeGroup ?? groups[0]?.name);
                return (
                  <NavLink key={g.name} label={g.name} active={active} variant="filled"
                    rightSection={<Badge size="xs" variant={active ? 'white' : 'light'}>{g.products.length}</Badge>}
                    style={{ borderRadius: 8 }}
                    onClick={() => setActiveGroup(g.name)} />
                );
              })}
            </Paper>

            <Paper withBorder radius="md" p="xs">
              <Group gap="xs" px="sm" pt="sm" pb="xs">
                <IconPlus size={16} />
                <Text fw={700}>Actions</Text>
              </Group>
              <NavLink label="Renew Domains" leftSection={<IconRefresh size={16} />}
                onClick={() => navigate('/portal/domains')} />
              <NavLink label="Register a New Domain" leftSection={<IconWorldWww size={16} />}
                onClick={() => navigate('/portal/domains?order=register')} />
              <NavLink label="Transfer in a Domain" leftSection={<IconArrowRight size={16} />}
                onClick={() => navigate('/portal/domains?order=transfer')} />
              <NavLink label="My Invoices" leftSection={<IconReceipt size={16} />}
                onClick={() => navigate('/portal/invoices')} />
            </Paper>
          </Stack>
        </Grid.Col>

        {/* ── Main area ── */}
        <Grid.Col span={{ base: 12, md: 9 }}>
          {!current ? (
            <Center py="xl"><Text c="dimmed">No products available.</Text></Center>
          ) : (
            <Stack gap="lg">
              <Title order={2}>{current.name}</Title>
              <SimpleGrid cols={{ base: 1, lg: 2 }} spacing="lg">
                {current.products.map((p) => (
                  <Paper key={p.id} withBorder radius="md" style={{ overflow: 'hidden' }}>
                    <Text fw={700} fz="lg" ta="center" py="md" bg="var(--mantine-color-default-hover)">
                      {p.name}
                    </Text>
                    <Divider />
                    <Group align="stretch" p="lg" gap="lg" wrap="nowrap">
                      <Stack gap={6} style={{ flex: 1 }}>
                        {p.features.length > 0 ? p.features.map((f, i) => (
                          <Group key={i} gap={6} wrap="nowrap">
                            <IconCheck size={13} color="var(--mantine-color-green-6)" style={{ flexShrink: 0 }} />
                            <Text size="sm">{f}</Text>
                          </Group>
                        )) : <Text size="sm" c="dimmed">—</Text>}
                      </Stack>
                      <Stack gap={4} align="center" justify="center" miw={150}>
                        <Text fw={800} fz="xl" ta="center">Tsh.{fmt(p.price)}</Text>
                        <Text size="sm" c="dimmed">{cycleLabel[p.billing_cycle ?? ''] ?? p.billing_cycle ?? ''}</Text>
                        <Button color="green" mt="xs" leftSection={<IconShoppingCart size={15} />}
                          onClick={() => setOrdering(p)}>
                          Order Now
                        </Button>
                      </Stack>
                    </Group>
                  </Paper>
                ))}
              </SimpleGrid>
            </Stack>
          )}
        </Grid.Col>
      </Grid>

      <ConfigureOrderModal product={ordering} onClose={() => setOrdering(null)}
        onDone={() => navigate('/portal/invoices')} />
    </Stack>
  );
}

function ConfigureOrderModal({ product, onClose, onDone }: {
  product: CatalogProduct | null; onClose: () => void; onDone: () => void;
}) {
  const qc = useQueryClient();
  const [mode, setMode] = useState<'register' | 'transfer' | 'existing'>('register');
  const [sld, setSld] = useState('');            // name part for register mode
  const [tld, setTld] = useState('co.tz');
  const [fullDomain, setFullDomain] = useState(''); // transfer/existing modes
  const [authInfo, setAuthInfo] = useState('');
  const [label, setLabel] = useState('');           // non-hosting reference
  const [checking, setChecking] = useState(false);
  const [checkResult, setCheckResult] = useState<{ ok: boolean; message: string } | null>(null);
  const [step, setStep] = useState<'choose' | 'configure'>('choose');
  const [years, setYears] = useState(1);
  const [selectedAddons, setSelectedAddons] = useState<string[]>([]);
  const [selectedProductAddons, setSelectedProductAddons] = useState<string[]>([]);

  const { data: tldsData } = useQuery({
    queryKey: ['portal-domain-tlds'],
    queryFn: getPortalDomainTlds,
    enabled: !!product?.needs_domain,
  });
  const tlds = tldsData?.data?.data ?? [];
  const { data: addonsData } = useQuery({
    queryKey: ['portal-domain-addons'],
    queryFn: getPortalDomainAddons,
    enabled: !!product?.needs_domain,
  });
  const addons: DomainAddonRow[] = addonsData?.data?.data ?? [];
  const { data: productAddonsData } = useQuery({
    queryKey: ['portal-product-addons', product?.id],
    queryFn: () => getPortalProductAddons(product!.id),
    enabled: !!product,
  });
  const productAddons: ProductAddonRow[] = productAddonsData?.data?.data ?? [];
  const productAddonsPrice = productAddons
    .filter((a) => selectedProductAddons.includes(a.id))
    .reduce((sum, a) => sum + Number(a.price), 0);
  const tldOptions = tlds.map((t) => ({ value: t.tld, label: `.${t.tld}` }));
  const activeTld = tlds.find((t) => t.tld === tld);

  const domain = mode === 'register'
    ? (sld.trim() ? `${sld.trim().toLowerCase().replace(/^www\./, '')}.${tld}` : '')
    : fullDomain.trim().toLowerCase().replace(/^www\./, '');

  const matchedTld = mode === 'register' ? activeTld : tlds.find((t) => domain.endsWith(`.${t.tld}`));
  const domainUnit = mode === 'register' ? (matchedTld?.register_price ?? 0)
    : mode === 'transfer' ? (matchedTld?.transfer_price ?? 0)
    : 0;
  const domainPrice = domainUnit * years;
  const addonsPrice = addons.filter((a) => selectedAddons.includes(a.id) && !a.is_free)
    .reduce((sum, a) => sum + Number(a.price), 0);

  const resetCheck = () => setCheckResult(null);

  const doCheck = async () => {
    if (!domain) return;
    setChecking(true);
    setCheckResult(null);
    try {
      const res = await portalCheckDomain(domain);
      const available = res.data.available;
      if (mode === 'register') {
        setCheckResult(available
          ? { ok: true, message: `${domain} is available — Tsh.${(activeTld?.register_price ?? 0).toLocaleString()} for the first year will be added to your order.` }
          : { ok: false, message: `${domain} is taken — try a different name or extension.` });
      } else {
        setCheckResult(!available
          ? { ok: true, message: `${domain} is registered — it can be transferred with a valid transfer code.` }
          : { ok: false, message: `${domain} is not registered — nothing to transfer.` });
      }
    } catch (e: any) {
      setCheckResult({ ok: false, message: e?.response?.data?.message ?? 'Check failed — try again.' });
    } finally {
      setChecking(false);
    }
  };

  const mutation = useMutation({
    mutationFn: () => placePortalOrder({
      product_service_id: product!.id,
      label: product!.needs_domain ? domain : (label.trim() || undefined),
      domain_mode: product!.needs_domain ? mode : undefined,
      auth_info: mode === 'transfer' ? authInfo : undefined,
      years: product!.needs_domain && mode !== 'existing' ? years : undefined,
      addons: product!.needs_domain && mode !== 'existing' ? selectedAddons : undefined,
      product_addon_ids: selectedProductAddons.length ? selectedProductAddons : undefined,
    }),
    onSuccess: (res: any) => {
      qc.invalidateQueries({ queryKey: ['portal-subscriptions'] });
      qc.invalidateQueries({ queryKey: ['portal-dashboard'] });
      qc.invalidateQueries({ queryKey: ['portal-domains'] });
      notifications.show({ title: 'Order placed', message: res?.data?.message, color: 'green', autoClose: 9000 });
      handleClose();
      onDone();
    },
    onError: (e: any) => notifications.show({
      message: e?.response?.data?.message ?? 'Order failed.', color: 'red',
    }),
  });

  const handleClose = () => {
    setMode('register'); setSld(''); setFullDomain(''); setAuthInfo(''); setLabel('');
    setCheckResult(null); setStep('choose'); setYears(1); setSelectedAddons([]);
    setSelectedProductAddons([]);
    onClose();
  };

  const domainValid = /^[a-z0-9][a-z0-9-]*(\.[a-z0-9-]+)+$/.test(domain);
  const canSubmit = product && (
    !product.needs_domain
      ? true
      : mode === 'existing'
        ? domainValid
        : (domainValid && checkResult?.ok === true && (mode !== 'transfer' || authInfo.trim().length > 0))
  );

  const total = (product?.price ?? 0)
    + (product?.needs_domain && mode !== 'existing' && checkResult?.ok ? domainPrice + addonsPrice : 0)
    + productAddonsPrice;
  const canContinue = product?.needs_domain && (
    mode === 'existing' ? domainValid
      : (domainValid && checkResult?.ok === true && (mode !== 'transfer' || authInfo.trim().length > 0)));
  const yearOptions = Array.from(
    { length: Math.max(1, (matchedTld?.years_max ?? 10) - (matchedTld?.years_min ?? 1) + 1) },
    (_, i) => String((matchedTld?.years_min ?? 1) + i),
  ).map((y) => ({ value: y, label: `${y} Year/s — Tsh.${fmt(domainUnit * Number(y))}` }));

  return (
    <Modal opened={!!product} onClose={handleClose} title={`Order — ${product?.name}`} centered size="lg">
      {product && (
        <Stack gap="sm">
          {product.needs_domain && step === 'configure' && mode !== 'existing' ? (
            <Paper withBorder radius="md" p="md" bg="var(--mantine-color-default-hover)">
              <Text fw={700}>Domains Configuration</Text>
              <Text size="xs" c="dimmed" mb="sm">
                Please review your domain name selection and any addons that are available for it.
              </Text>
              <Divider label={<Text c="blue" fw={600} size="sm">{domain}</Text>} labelPosition="center" mb="sm" />
              <Group grow mb="md">
                <div>
                  <Text size="xs" c="dimmed">Registration Period</Text>
                  <Select mt={4} data={yearOptions} value={String(years)}
                    onChange={(v) => setYears(Number(v) || 1)} />
                </div>
                <div>
                  <Text size="xs" c="dimmed">Hosting</Text>
                  <Text mt={10} size="sm" fw={600} c="green">[Has Hosting]</Text>
                </div>
              </Group>
              <Stack gap="sm">
                {addons.map((a) => {
                  const on = selectedAddons.includes(a.id);
                  return (
                    <Paper key={a.id} withBorder radius="md" style={{ overflow: 'hidden' }}>
                      <Stack gap={4} p="sm" align="center">
                        <Checkbox checked={on} label={<Text fw={700}>{a.name}</Text>}
                          onChange={() => setSelectedAddons((cur) =>
                            on ? cur.filter((x) => x !== a.id) : [...cur, a.id])} />
                        {a.description && <Text size="xs" c="dimmed" ta="center">{a.description}</Text>}
                      </Stack>
                      <Text ta="center" size="sm" fw={600} py={6} bg="var(--mantine-color-default-hover)">
                        {a.is_free ? 'FREE!' : `Tsh.${fmt(Number(a.price))}`} / 1 Year/s
                      </Text>
                      <UnstyledButton w="100%" py={8}
                        style={{ background: on ? 'var(--mantine-color-green-6)' : 'var(--mantine-color-gray-2)', textAlign: 'center' }}
                        onClick={() => setSelectedAddons((cur) =>
                          on ? cur.filter((x) => x !== a.id) : [...cur, a.id])}>
                        <Group gap={6} justify="center">
                          <IconShoppingCart size={14} color={on ? 'white' : 'gray'} />
                          <Text size="sm" fw={600} c={on ? 'white' : 'dimmed'}>
                            {on ? 'Added to Cart (Remove)' : 'Add to Cart'}
                          </Text>
                        </Group>
                      </UnstyledButton>
                    </Paper>
                  );
                })}
              </Stack>
            </Paper>
          ) : product.needs_domain ? (
            <Paper withBorder radius="md" p="md" bg="var(--mantine-color-default-hover)">
              <Text fw={700} mb="sm">Choose a Domain…</Text>
              <Radio.Group value={mode} onChange={(v) => { setMode(v as any); resetCheck(); }}>
                <Stack gap="sm">
                  <Paper withBorder p="sm" radius="md">
                    <Radio value="register" label="Register a new domain" fw={600} />
                    {mode === 'register' && (
                      <Group gap={6} mt="sm" wrap="nowrap" align="flex-end">
                        <Text size="sm" c="dimmed" pb={8}>www.</Text>
                        <TextInput placeholder="yourdomain" style={{ flex: 1 }} autoFocus
                          value={sld} onChange={(e) => { setSld(e.currentTarget.value); resetCheck(); }} />
                        <Select w={120} data={tldOptions} value={tld}
                          onChange={(v) => { setTld(v ?? 'co.tz'); resetCheck(); }} />
                        <Button loading={checking} disabled={!sld.trim()} onClick={doCheck}>Check</Button>
                      </Group>
                    )}
                  </Paper>

                  <Paper withBorder p="sm" radius="md">
                    <Radio value="transfer" label="Transfer your domain from another registrar" fw={600} />
                    {mode === 'transfer' && (
                      <Stack gap="xs" mt="sm">
                        <Group gap={6} wrap="nowrap" align="flex-end">
                          <TextInput placeholder="yourdomain.co.tz" style={{ flex: 1 }} autoFocus
                            value={fullDomain} onChange={(e) => { setFullDomain(e.currentTarget.value); resetCheck(); }} />
                          <Button loading={checking} disabled={!fullDomain.trim()} onClick={doCheck}>Check</Button>
                        </Group>
                        <TextInput label="Transfer code (EPP/auth-info)" required
                          value={authInfo} onChange={(e) => setAuthInfo(e.currentTarget.value)} />
                      </Stack>
                    )}
                  </Paper>

                  <Paper withBorder p="sm" radius="md">
                    <Radio value="existing" label="I will use my existing domain and update my nameservers" fw={600} />
                    {mode === 'existing' && (
                      <TextInput mt="sm" placeholder="yourdomain.co.tz" autoFocus
                        value={fullDomain} onChange={(e) => setFullDomain(e.currentTarget.value)} />
                    )}
                  </Paper>
                </Stack>
              </Radio.Group>

              {checkResult && (
                <Alert mt="sm" color={checkResult.ok ? 'green' : 'red'} variant="light">
                  {checkResult.message}
                </Alert>
              )}
            </Paper>
          ) : (
            <TextInput label="Reference / label (optional)" placeholder="e.g. project or domain name"
              value={label} onChange={(e) => setLabel(e.currentTarget.value)} />
          )}

          {productAddons.length > 0 && (
            <Paper withBorder radius="md" p="md" bg="var(--mantine-color-default-hover)">
              <Text fw={700}>Available Add-ons</Text>
              <Text size="xs" c="dimmed" mb="sm">Optional paid extras for this service — billed now and on each renewal.</Text>
              <Stack gap="sm">
                {productAddons.map((a) => {
                  const on = selectedProductAddons.includes(a.id);
                  const toggle = () => setSelectedProductAddons((cur) =>
                    on ? cur.filter((x) => x !== a.id) : [...cur, a.id]);
                  return (
                    <Paper key={a.id} withBorder radius="md" p="sm">
                      <Group justify="space-between" wrap="nowrap" align="flex-start">
                        <div style={{ flex: 1 }}>
                          <Checkbox checked={on} onChange={toggle} label={<Text fw={600}>{a.name}</Text>} />
                          {a.description && <Text size="xs" c="dimmed" mt={4}>{a.description}</Text>}
                        </div>
                        <Stack gap={0} align="flex-end">
                          <Text size="sm" fw={700}>Tsh.{fmt(Number(a.price))}</Text>
                          <Text size="xs" c="dimmed">{cycleLabel[a.billing_cycle ?? ''] ?? a.billing_cycle ?? ''}</Text>
                        </Stack>
                      </Group>
                    </Paper>
                  );
                })}
              </Stack>
            </Paper>
          )}

          <Paper withBorder p="sm" radius="md">
            <Group justify="space-between">
              <Text size="sm">{product.name}</Text>
              <Text size="sm" fw={600}>Tsh.{fmt(product.price)}</Text>
            </Group>
            {productAddons.filter((a) => selectedProductAddons.includes(a.id)).map((a) => (
              <Group key={a.id} justify="space-between" mt={4}>
                <Text size="sm">Add-on: {a.name}</Text>
                <Text size="sm" fw={600}>Tsh.{fmt(Number(a.price))}</Text>
              </Group>
            ))}
            {product.needs_domain && mode !== 'existing' && checkResult?.ok && (
              <>
                <Group justify="space-between" mt={4}>
                  <Text size="sm">{mode === 'register' ? 'Register' : 'Transfer'} {domain} — {years} year(s)</Text>
                  <Text size="sm" fw={600}>Tsh.{fmt(domainPrice)}</Text>
                </Group>
                {addons.filter((a) => selectedAddons.includes(a.id)).map((a) => (
                  <Group key={a.id} justify="space-between" mt={2}>
                    <Text size="xs" c="dimmed">{a.name}</Text>
                    <Text size="xs" c="dimmed">{a.is_free ? 'FREE' : `Tsh.${fmt(Number(a.price))}`}</Text>
                  </Group>
                ))}
              </>
            )}
            <Divider my={6} />
            <Group justify="space-between">
              <Text fw={700}>Total due now</Text>
              <Text fw={800}>Tsh.{fmt(total)}</Text>
            </Group>
            <Text size="xs" c="dimmed" mt={4}>
              An invoice is created now — your service{product.needs_domain && mode !== 'existing' ? ' and domain' : ''} activate
              automatically when it is paid.
            </Text>
          </Paper>

          <Group justify="flex-end">
            <Button variant="default" onClick={handleClose}>Cancel</Button>
            {product.needs_domain && step === 'choose' && mode !== 'existing' ? (
              <Button disabled={!canContinue} onClick={() => setStep('configure')}>
                Continue →
              </Button>
            ) : (
              <>
                {product.needs_domain && step === 'configure' && (
                  <Button variant="subtle" leftSection={<IconArrowLeft size={14} />}
                    onClick={() => setStep('choose')}>
                    Back
                  </Button>
                )}
                <Button color="green" disabled={!canSubmit} loading={mutation.isPending}
                  onClick={() => mutation.mutate()}>
                  Place Order
                </Button>
              </>
            )}
          </Group>
        </Stack>
      )}
    </Modal>
  );
}
