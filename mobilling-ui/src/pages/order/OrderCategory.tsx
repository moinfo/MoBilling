import { useMemo, useState } from 'react';
import {
  Stack, Paper, Title, Text, Group, Button, Badge, SimpleGrid, List, ThemeIcon,
  Alert, Radio, Checkbox, NumberInput, Select, TextInput, Divider, Loader, Box,
} from '@mantine/core';
import { useQuery, useMutation } from '@tanstack/react-query';
import { notifications } from '@mantine/notifications';
import { useNavigate, useParams, useSearchParams } from 'react-router-dom';
import {
  IconCheck, IconArrowLeft, IconAlertCircle, IconShoppingCart, IconTag,
} from '@tabler/icons-react';
import {
  getPortalCatalog, getPortalProductAddons, getPortalProductConfigOptions,
  getPortalDomainTlds, getPortalDomainAddons, validatePortalCoupon, placePortalOrder,
  type CatalogProduct, type OrderConfigOption,
} from '../../api/portal';
import {
  findCategory, productNameForPlan, formatTsh, cycleLabel,
} from '../../data/storefront';
import classes from './Order.module.css';

type DomainMode = 'register' | 'transfer' | 'existing';

export default function OrderCategory() {
  const { category: categorySlug } = useParams();
  const [searchParams, setSearchParams] = useSearchParams();
  const navigate = useNavigate();

  const category = findCategory(categorySlug);

  const [chosen, setChosen] = useState<CatalogProduct | null>(null);
  const [label, setLabel] = useState('');
  const [domainMode, setDomainMode] = useState<DomainMode>('register');
  const [authInfo, setAuthInfo] = useState('');
  const [years, setYears] = useState(1);
  const [domainAddonIds, setDomainAddonIds] = useState<string[]>([]);
  const [productAddonIds, setProductAddonIds] = useState<string[]>([]);
  const [configChoices, setConfigChoices] = useState<Record<string, string>>({});
  const [configQty, setConfigQty] = useState<Record<string, number>>({});
  const [configToggles, setConfigToggles] = useState<Record<string, boolean>>({});
  const [coupon, setCoupon] = useState(searchParams.get('coupon') ?? '');
  const [discount, setDiscount] = useState(0);
  const [couponMsg, setCouponMsg] = useState<string | null>(null);

  const { data: catalogRes, isLoading, isError } = useQuery({
    queryKey: ['portal-catalog'],
    queryFn: getPortalCatalog,
  });

  // The catalog groups by provisioning bucket ("cpanel", "whmcs"), so we ignore
  // its grouping and match products by name against the storefront map.
  const plansInCategory = useMemo(() => {
    if (!category) return [];
    const all = (catalogRes?.data?.data ?? []).flatMap((g) => g.products);
    return category.plans
      .map((p) => ({ plan: p, product: all.find((x) => x.name === p.product) }))
      .filter((row): row is { plan: typeof row.plan; product: CatalogProduct } => !!row.product);
  }, [catalogRes, category]);

  // Deep link from moinfo.co.tz: /order/<category>?plan=<slug>. Derived rather
  // than pushed into state, so ?plan= stays the single source of truth — and
  // "Change plan" just drops the param.
  const preselected = useMemo(() => {
    if (!category) return null;
    const wanted = productNameForPlan(category, searchParams.get('plan'));
    if (!wanted) return null;
    return plansInCategory.find((r) => r.product.name === wanted)?.product ?? null;
  }, [category, searchParams, plansInCategory]);

  const selected = chosen ?? preselected;

  const clearPlan = () => {
    setChosen(null);
    const params = new URLSearchParams(searchParams);
    params.delete('plan');
    setSearchParams(params, { replace: true });
  };

  const { data: addonsRes } = useQuery({
    queryKey: ['portal-product-addons', selected?.id],
    queryFn: () => getPortalProductAddons(selected!.id),
    enabled: !!selected,
  });
  const { data: configRes } = useQuery({
    queryKey: ['portal-config-options', selected?.id],
    queryFn: () => getPortalProductConfigOptions(selected!.id),
    enabled: !!selected,
  });
  const { data: tldRes } = useQuery({
    queryKey: ['portal-domain-tlds'],
    queryFn: getPortalDomainTlds,
    enabled: !!selected?.needs_domain,
  });
  const { data: domainAddonRes } = useQuery({
    queryKey: ['portal-domain-addons'],
    queryFn: getPortalDomainAddons,
    enabled: !!selected?.needs_domain,
  });

  const productAddons = addonsRes?.data?.data ?? [];
  const configGroups = configRes?.data?.data ?? [];
  const tlds = tldRes?.data?.data ?? [];
  const domainAddons = domainAddonRes?.data?.data ?? [];

  const tldFor = (domain: string) => {
    const suffix = domain.toLowerCase().split('.').slice(1).join('.');
    return tlds.find((t) => t.tld.replace(/^\./, '') === suffix);
  };
  const activeTld = tldFor(label);

  // Estimate only — the invoice the server writes is authoritative (it also
  // applies tax, which we deliberately don't guess at here).
  const estimate = useMemo(() => {
    if (!selected) return 0;
    let total = Number(selected.price);
    if (selected.needs_domain && domainMode !== 'existing' && activeTld) {
      const unit = domainMode === 'register' ? activeTld.register_price : activeTld.transfer_price;
      total += Number(unit) * years;
    }
    total += domainAddons
      .filter((a) => domainAddonIds.includes(a.id) && !a.is_free)
      .reduce((s, a) => s + Number(a.price), 0);
    total += productAddons
      .filter((a) => productAddonIds.includes(a.id))
      .reduce((s, a) => s + Number(a.price), 0);
    for (const g of configGroups) {
      for (const o of g.options) {
        if (o.option_type === 'dropdown' || o.option_type === 'radio') {
          const choice = o.choices.find((c) => c.id === configChoices[o.id]);
          if (choice) total += Number(choice.price);
        } else if (o.option_type === 'quantity') {
          total += Number(o.unit_price ?? 0) * (configQty[o.id] ?? 0);
        } else if (configToggles[o.id]) {
          total += Number(o.unit_price ?? 0);
        }
      }
    }
    return Math.max(0, total - discount);
  }, [selected, domainMode, activeTld, years, domainAddons, domainAddonIds,
      productAddons, productAddonIds, configGroups, configChoices, configQty,
      configToggles, discount]);

  const couponMutation = useMutation({
    mutationFn: () => validatePortalCoupon(coupon.trim(), selected!.id),
    onSuccess: (res) => {
      const d = res.data;
      setDiscount(d.valid ? Number(d.discount) : 0);
      setCouponMsg(d.message);
      notifications.show({ message: d.message, color: d.valid ? 'green' : 'red' });
    },
    onError: (e: any) => {
      setDiscount(0);
      setCouponMsg(e?.response?.data?.message ?? 'Could not check that code.');
      notifications.show({ message: couponMsg ?? 'Could not check that code.', color: 'red' });
    },
  });

  const buildConfigOptions = (): OrderConfigOption[] => {
    const out: OrderConfigOption[] = [];
    for (const g of configGroups) {
      for (const o of g.options) {
        if (o.option_type === 'dropdown' || o.option_type === 'radio') {
          if (configChoices[o.id]) out.push({ option_id: o.id, choice_id: configChoices[o.id] });
        } else if (o.option_type === 'quantity') {
          const q = configQty[o.id] ?? 0;
          if (q > 0) out.push({ option_id: o.id, quantity: q });
        } else if (configToggles[o.id]) {
          // yesno: presence in the payload means "on"
          out.push({ option_id: o.id });
        }
      }
    }
    return out;
  };

  const orderMutation = useMutation({
    mutationFn: () => placePortalOrder({
      product_service_id: selected!.id,
      label: label.trim() || undefined,
      domain_mode: selected!.needs_domain ? domainMode : undefined,
      auth_info: domainMode === 'transfer' ? authInfo.trim() || undefined : undefined,
      years: selected!.needs_domain && domainMode !== 'existing' ? years : undefined,
      addons: domainAddonIds.length ? domainAddonIds : undefined,
      product_addon_ids: productAddonIds.length ? productAddonIds : undefined,
      config_options: buildConfigOptions().length ? buildConfigOptions() : undefined,
      coupon_code: coupon.trim() || undefined,
    }),
    onSuccess: (res: any) => {
      notifications.show({
        title: 'Order placed',
        message: res?.data?.message,
        color: 'green',
        autoClose: 10000,
      });
      const id = res?.data?.data?.document_id;
      navigate(id ? `/portal/invoices/${id}` : '/portal/invoices');
    },
    onError: (e: any) => notifications.show({
      title: 'Could not place the order',
      message: e?.response?.data?.message ?? 'Something went wrong — please try again.',
      color: 'red',
      autoClose: 10000,
    }),
  });

  if (!category) {
    return (
      <Alert color="red" icon={<IconAlertCircle size={18} />} title="Unknown service">
        We don't have a service group called "{categorySlug}".{' '}
        <Text component="a" href="/order" td="underline">Browse everything we offer</Text>.
      </Alert>
    );
  }

  if (isLoading) return <Group justify="center" p="xl"><Loader /></Group>;

  if (isError) {
    return (
      <Alert color="red" icon={<IconAlertCircle size={18} />} title="Could not load the catalog">
        Please refresh, or contact support if this keeps happening.
      </Alert>
    );
  }

  if (!plansInCategory.length) {
    return (
      <Alert color="yellow" icon={<IconAlertCircle size={18} />} title="Nothing available here yet">
        {category.label} plans aren't published to the client portal on your account
        yet. Please contact us and we'll set this up for you.
      </Alert>
    );
  }

  const needsDomain = !!selected?.needs_domain;
  const domainInvalid = needsDomain && domainMode !== 'existing' && !!label.trim() && !activeTld;
  const canSubmit = !!selected
    && (!needsDomain || !!label.trim())
    && !domainInvalid
    && (domainMode !== 'transfer' || !!authInfo.trim());

  return (
    <Stack gap="lg" maw={980}>
      <Group gap="xs">
        <Button
          variant="subtle"
          size="compact-sm"
          leftSection={<IconArrowLeft size={16} />}
          onClick={() => (selected ? clearPlan() : navigate('/order'))}
        >
          {selected ? 'Change plan' : 'All services'}
        </Button>
      </Group>

      <div>
        <Title order={3}>{category.label}</Title>
        <Text c="dimmed" size="sm">{category.description}</Text>
      </div>

      {/* ── Step 1: pick a plan ─────────────────────────────────────────── */}
      {!selected && (
        <SimpleGrid cols={{ base: 1, sm: 2, lg: 3 }}>
          {plansInCategory.map(({ plan, product }) => (
            <Paper key={product.id} p="lg" radius="md" className={classes.planCard}>
              <Stack gap="sm" h="100%" justify="space-between">
                <div>
                  <Text fw={600}>{product.name}</Text>
                  <Group gap={4} align="baseline" mt={4}>
                    <Text className={classes.price}>{formatTsh(product.price)}</Text>
                    <Text className={classes.pricePeriod}>{cycleLabel(product.billing_cycle)}</Text>
                  </Group>
                  {product.needs_domain && (
                    <Badge size="sm" variant="light" mt="xs">Needs a domain</Badge>
                  )}
                  <List
                    spacing={4}
                    size="sm"
                    mt="md"
                    icon={<ThemeIcon color="green" size={16} radius="xl"><IconCheck size={11} /></ThemeIcon>}
                  >
                    {product.features.slice(0, 8).map((f, i) => <List.Item key={i}>{f}</List.Item>)}
                  </List>
                </div>
                <Button
                  mt="md"
                  fullWidth
                  onClick={() => { setChosen(product); setLabel(''); }}
                  data-plan={plan.slug}
                >
                  Choose {product.name}
                </Button>
              </Stack>
            </Paper>
          ))}
        </SimpleGrid>
      )}

      {/* ── Step 2: configure ───────────────────────────────────────────── */}
      {selected && (
        <>
          <Paper withBorder p="lg" radius="md">
            <Group justify="space-between" align="flex-start">
              <div>
                <Text fw={600}>{selected.name}</Text>
                <Text c="dimmed" size="sm">
                  {formatTsh(selected.price)}{cycleLabel(selected.billing_cycle)}
                </Text>
              </div>
              <Badge variant="light">Selected</Badge>
            </Group>
          </Paper>

          {needsDomain && (
            <Paper withBorder p="lg" radius="md">
              <Title order={5} mb="sm">Domain</Title>
              <Radio.Group
                value={domainMode}
                onChange={(v) => setDomainMode(v as DomainMode)}
                mb="md"
              >
                <Stack gap="xs">
                  <Radio value="register" label="Register a new domain" />
                  <Radio value="transfer" label="Transfer a domain to us" />
                  <Radio value="existing" label="Use a domain I already own" />
                </Stack>
              </Radio.Group>

              <TextInput
                label="Domain name"
                description="The domain this hosting account will be set up for."
                placeholder="mycompany.co.tz"
                value={label}
                onChange={(e) => setLabel(e.currentTarget.value)}
                error={domainInvalid ? "We don't currently offer that extension." : undefined}
                required
              />

              {domainMode === 'transfer' && (
                <TextInput
                  mt="sm"
                  label="Authorisation (EPP) code"
                  description="From your current registrar."
                  value={authInfo}
                  onChange={(e) => setAuthInfo(e.currentTarget.value)}
                  required
                />
              )}

              {domainMode !== 'existing' && (
                <>
                  <NumberInput
                    mt="sm"
                    label="Registration period (years)"
                    min={activeTld?.years_min ?? 1}
                    max={activeTld?.years_max ?? 10}
                    value={years}
                    onChange={(v) => setYears(Number(v) || 1)}
                  />
                  {activeTld && (
                    <Text size="sm" c="dimmed" mt={6}>
                      {formatTsh(
                        (domainMode === 'register'
                          ? activeTld.register_price
                          : activeTld.transfer_price) * years,
                      )} for {years} year{years > 1 ? 's' : ''}
                    </Text>
                  )}
                  {domainAddons.length > 0 && (
                    <Checkbox.Group
                      mt="md"
                      label="Domain extras"
                      value={domainAddonIds}
                      onChange={setDomainAddonIds}
                    >
                      <Stack gap="xs" mt="xs">
                        {domainAddons.map((a) => (
                          <Checkbox
                            key={a.id}
                            value={a.id}
                            label={`${a.name} — ${a.is_free ? 'Free' : formatTsh(a.price)}`}
                            description={a.description ?? undefined}
                          />
                        ))}
                      </Stack>
                    </Checkbox.Group>
                  )}
                </>
              )}
            </Paper>
          )}

          {!needsDomain && (
            <Paper withBorder p="lg" radius="md">
              <TextInput
                label="Reference (optional)"
                description="A short label so you can recognise this service later."
                placeholder="e.g. Company website"
                value={label}
                onChange={(e) => setLabel(e.currentTarget.value)}
              />
            </Paper>
          )}

          {configGroups.length > 0 && (
            <Paper withBorder p="lg" radius="md">
              <Title order={5} mb="sm">Configure</Title>
              <Stack gap="lg">
                {configGroups.map((g) => (
                  <div key={g.id}>
                    <Text fw={500} size="sm">{g.name}</Text>
                    {g.description && <Text c="dimmed" size="xs">{g.description}</Text>}
                    <Stack gap="sm" mt="xs">
                      {g.options.map((o) => {
                        if (o.option_type === 'dropdown') {
                          return (
                            <Select
                              key={o.id}
                              label={o.name}
                              placeholder="Choose"
                              value={configChoices[o.id] ?? null}
                              onChange={(v) =>
                                setConfigChoices((s) => ({ ...s, [o.id]: v ?? '' }))}
                              data={o.choices.map((c) => ({
                                value: c.id,
                                label: c.price > 0 ? `${c.label} (+${formatTsh(c.price)})` : c.label,
                              }))}
                            />
                          );
                        }
                        if (o.option_type === 'radio') {
                          return (
                            <Radio.Group
                              key={o.id}
                              label={o.name}
                              value={configChoices[o.id] ?? null}
                              onChange={(v) => setConfigChoices((s) => ({ ...s, [o.id]: v }))}
                            >
                              <Stack gap={4} mt={4}>
                                {o.choices.map((c) => (
                                  <Radio
                                    key={c.id}
                                    value={c.id}
                                    label={c.price > 0 ? `${c.label} (+${formatTsh(c.price)})` : c.label}
                                  />
                                ))}
                              </Stack>
                            </Radio.Group>
                          );
                        }
                        if (o.option_type === 'quantity') {
                          return (
                            <NumberInput
                              key={o.id}
                              label={o.name}
                              description={o.unit_price ? `${formatTsh(o.unit_price)} each` : undefined}
                              min={0}
                              value={configQty[o.id] ?? 0}
                              onChange={(v) =>
                                setConfigQty((s) => ({ ...s, [o.id]: Number(v) || 0 }))}
                            />
                          );
                        }
                        return (
                          <Checkbox
                            key={o.id}
                            label={o.unit_price
                              ? `${o.name} (+${formatTsh(o.unit_price)})`
                              : o.name}
                            checked={!!configToggles[o.id]}
                            onChange={(e) =>
                              setConfigToggles((s) => ({ ...s, [o.id]: e.currentTarget.checked }))}
                          />
                        );
                      })}
                    </Stack>
                  </div>
                ))}
              </Stack>
            </Paper>
          )}

          {productAddons.length > 0 && (
            <Paper withBorder p="lg" radius="md">
              <Title order={5} mb="sm">Add-ons</Title>
              <Checkbox.Group value={productAddonIds} onChange={setProductAddonIds}>
                <Stack gap="xs">
                  {productAddons.map((a) => (
                    <Checkbox
                      key={a.id}
                      value={a.id}
                      label={`${a.name} — ${formatTsh(a.price)}${cycleLabel(a.billing_cycle)}`}
                      description={a.description ?? undefined}
                    />
                  ))}
                </Stack>
              </Checkbox.Group>
            </Paper>
          )}

          <Paper withBorder p="lg" radius="md">
            <Title order={5} mb="sm">Promo code</Title>
            <Group align="flex-end" gap="sm">
              <TextInput
                style={{ flex: 1 }}
                placeholder="Enter code"
                value={coupon}
                onChange={(e) => { setCoupon(e.currentTarget.value); setDiscount(0); setCouponMsg(null); }}
                leftSection={<IconTag size={16} />}
              />
              <Button
                variant="light"
                onClick={() => couponMutation.mutate()}
                loading={couponMutation.isPending}
                disabled={!coupon.trim()}
              >
                Apply
              </Button>
            </Group>
            {couponMsg && (
              <Text size="sm" mt={6} c={discount > 0 ? 'green' : 'red'}>{couponMsg}</Text>
            )}
          </Paper>

          <Paper withBorder p="lg" radius="md">
            <Group justify="space-between">
              <Text fw={500}>{selected.name}</Text>
              <Text>{formatTsh(selected.price)}</Text>
            </Group>
            {discount > 0 && (
              <Group justify="space-between" mt={4}>
                <Text c="green" size="sm">Promo discount</Text>
                <Text c="green" size="sm">− {formatTsh(discount)}</Text>
              </Group>
            )}
            <Divider my="sm" />
            <Group justify="space-between">
              <Text fw={700}>Estimated total</Text>
              <Text fw={700} size="lg">{formatTsh(estimate)}</Text>
            </Group>
            <Text c="dimmed" size="xs" mt={4}>
              Excludes tax. Your invoice will show the exact amount.
            </Text>

            <Button
              mt="md"
              fullWidth
              size="md"
              leftSection={<IconShoppingCart size={18} />}
              onClick={() => orderMutation.mutate()}
              loading={orderMutation.isPending}
              disabled={!canSubmit}
            >
              Place order
            </Button>
            {needsDomain && !label.trim() && (
              <Text c="dimmed" size="xs" ta="center" mt={6}>
                Enter your domain name to continue.
              </Text>
            )}
          </Paper>
          <Box h={8} />
        </>
      )}
    </Stack>
  );
}
