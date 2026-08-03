import { useMemo, useState } from 'react';
import {
  Alert, Badge, Button, Card, Checkbox, Divider, Grid, Group, Loader, NumberInput,
  Paper, Radio, SegmentedControl, Select, Stack, Text, TextInput, Title,
} from '@mantine/core';
import { useDebouncedValue } from '@mantine/hooks';
import { notifications } from '@mantine/notifications';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useNavigate } from 'react-router-dom';
import {
  IconShoppingCart, IconWorldWww, IconPackage, IconCheck, IconTicket,
} from '@tabler/icons-react';
import {
  getOrderCatalog, getOrderDomainTlds, getOrderDomainAddons,
  getOrderProductAddons, getOrderConfigOptions, validateOrderCoupon, placeOrder,
} from '../api/orders';
import { getClients, type Client } from '../api/clients';
import { orderDomain } from '../api/domains';
import type { CatalogProduct } from '../api/portal';
import { formatCurrency } from '../utils/formatCurrency';

/**
 * Admin "Add New Order" (WHMCS-style): staff pick a client, then order a
 * product/service (optionally with a bundled domain, add-ons, options and a
 * promo code) or a standalone domain. Both flows produce a pending service +
 * an invoice the client pays to activate.
 */
export default function Orders() {
  const [clientId, setClientId] = useState<string | null>(null);
  const [clientSearch, setClientSearch] = useState('');
  const [debouncedSearch] = useDebouncedValue(clientSearch, 300);
  const [kind, setKind] = useState<'product' | 'domain'>('product');

  const { data: clientsRes, isLoading: clientsLoading } = useQuery({
    queryKey: ['order-clients', debouncedSearch],
    queryFn: () => getClients({ search: debouncedSearch || undefined, per_page: 30 }),
  });
  const clients: Client[] = clientsRes?.data?.data ?? [];

  const clientOptions = useMemo(
    () => clients.map((c) => ({ value: c.id, label: c.name + (c.email ? ` — ${c.email}` : '') })),
    [clients],
  );

  return (
    <Stack>
      <Group justify="space-between">
        <Title order={3}>
          <Group gap="xs"><IconShoppingCart size={22} /> Add New Order</Group>
        </Title>
      </Group>

      <Paper withBorder p="md" radius="md">
        <Grid align="flex-end">
          <Grid.Col span={{ base: 12, sm: 6 }}>
            <Select
              label="Client"
              placeholder="Search client…"
              searchable
              clearable
              value={clientId}
              onChange={setClientId}
              data={clientOptions}
              searchValue={clientSearch}
              onSearchChange={setClientSearch}
              nothingFoundMessage={clientsLoading ? 'Searching…' : 'No client found'}
              // options come from the server-side search; don't re-filter locally
              filter={({ options }) => options}
            />
          </Grid.Col>
          <Grid.Col span={{ base: 12, sm: 6 }}>
            <SegmentedControl
              value={kind}
              onChange={(v) => setKind(v as 'product' | 'domain')}
              data={[
                { value: 'product', label: 'Product / Service' },
                { value: 'domain', label: 'Domain only' },
              ]}
            />
          </Grid.Col>
        </Grid>
      </Paper>

      {!clientId ? (
        <Paper withBorder p="xl" radius="md">
          <Text c="dimmed" ta="center">Select a client to place an order on their behalf.</Text>
        </Paper>
      ) : kind === 'product' ? (
        <ProductOrderForm clientId={clientId} />
      ) : (
        <DomainOrderForm clientId={clientId} />
      )}
    </Stack>
  );
}

// ── Product / service order ───────────────────────────────────────────────────

function ProductOrderForm({ clientId }: { clientId: string }) {
  const navigate = useNavigate();
  const queryClient = useQueryClient();

  const [productId, setProductId] = useState<string | null>(null);
  const [label, setLabel] = useState('');
  const [domainMode, setDomainMode] = useState<'existing' | 'register' | 'transfer'>('existing');
  const [authInfo, setAuthInfo] = useState('');
  const [years, setYears] = useState<number>(1);
  const [domainAddonIds, setDomainAddonIds] = useState<string[]>([]);
  const [productAddonIds, setProductAddonIds] = useState<string[]>([]);
  const [configSel, setConfigSel] = useState<Record<string, { choice_id?: string; quantity?: number; on?: boolean }>>({});
  const [couponCode, setCouponCode] = useState('');
  const [couponInfo, setCouponInfo] = useState<{ valid: boolean; discount: number; message: string } | null>(null);

  const { data: catalogRes, isLoading } = useQuery({ queryKey: ['order-catalog'], queryFn: getOrderCatalog });
  const groups = catalogRes?.data?.data ?? [];
  const products: (CatalogProduct & { group: string })[] = useMemo(
    () => groups.flatMap((g) => g.products.map((p) => ({ ...p, group: g.name }))),
    [groups],
  );
  const product = products.find((p) => p.id === productId) ?? null;
  const needsDomain = product?.needs_domain ?? false;

  const { data: tldsRes } = useQuery({
    queryKey: ['order-tlds'], queryFn: getOrderDomainTlds, enabled: needsDomain,
  });
  const tlds = tldsRes?.data?.data ?? [];
  const { data: domainAddonsRes } = useQuery({
    queryKey: ['order-domain-addons'], queryFn: getOrderDomainAddons,
    enabled: needsDomain && domainMode !== 'existing',
  });
  const domainAddons = domainAddonsRes?.data?.data ?? [];
  const { data: addonsRes } = useQuery({
    queryKey: ['order-product-addons', productId],
    queryFn: () => getOrderProductAddons(productId!),
    enabled: !!productId,
  });
  const productAddons = addonsRes?.data?.data ?? [];
  const { data: configRes } = useQuery({
    queryKey: ['order-config-options', productId],
    queryFn: () => getOrderConfigOptions(productId!),
    enabled: !!productId,
  });
  const configGroups = configRes?.data?.data ?? [];

  const domain = label.trim().toLowerCase();
  const tldRow = useMemo(() => {
    if (!domain.includes('.')) return null;
    const tld = domain.split('.').slice(1).join('.');
    return tlds.find((t) => t.tld === tld) ?? null;
  }, [domain, tlds]);

  // Estimated total mirroring the server computation (server recomputes; this
  // is display only).
  const estimate = useMemo(() => {
    if (!product) return 0;
    let total = product.price;
    if (needsDomain && domainMode !== 'existing' && tldRow) {
      total += (domainMode === 'register' ? tldRow.register_price : tldRow.transfer_price) * years;
      total += domainAddons.filter((a) => domainAddonIds.includes(a.id) && !a.is_free)
        .reduce((s, a) => s + Number(a.price), 0);
    }
    total += productAddons.filter((a) => productAddonIds.includes(a.id))
      .reduce((s, a) => s + Number(a.price), 0);
    for (const g of configGroups) {
      for (const o of g.options) {
        const sel = configSel[o.id];
        if (!sel) continue;
        if (o.option_type === 'dropdown' || o.option_type === 'radio') {
          const c = o.choices.find((ch) => ch.id === sel.choice_id);
          if (c) total += Number(c.price);
        } else if (o.option_type === 'quantity' && sel.quantity) {
          total += Number(o.unit_price ?? 0) * sel.quantity;
        } else if (o.option_type === 'yesno' && sel.on) {
          total += Number(o.unit_price ?? 0);
        }
      }
    }
    if (couponInfo?.valid) total -= couponInfo.discount;
    return Math.max(total, 0);
  }, [product, needsDomain, domainMode, tldRow, years, domainAddons, domainAddonIds,
      productAddons, productAddonIds, configGroups, configSel, couponInfo]);

  const checkCoupon = async () => {
    if (!couponCode.trim() || !productId) return;
    try {
      const res = await validateOrderCoupon(clientId, couponCode.trim(), productId);
      setCouponInfo(res.data);
    } catch {
      setCouponInfo({ valid: false, discount: 0, message: 'Could not validate the code.' });
    }
  };

  const placeMutation = useMutation({
    mutationFn: () => {
      const config_options = Object.entries(configSel)
        .filter(([, v]) => v.choice_id || v.quantity || v.on)
        .map(([option_id, v]) => ({
          option_id,
          choice_id: v.choice_id,
          quantity: v.quantity,
        }));
      return placeOrder({
        client_id: clientId,
        product_service_id: productId!,
        label: label.trim() || undefined,
        domain_mode: needsDomain ? domainMode : undefined,
        auth_info: domainMode === 'transfer' ? authInfo : undefined,
        years: needsDomain && domainMode !== 'existing' ? years : undefined,
        addons: domainAddonIds.length ? domainAddonIds : undefined,
        product_addon_ids: productAddonIds.length ? productAddonIds : undefined,
        config_options: config_options.length ? config_options : undefined,
        coupon_code: couponInfo?.valid ? couponCode.trim() : undefined,
      });
    },
    onSuccess: (res) => {
      queryClient.invalidateQueries({ queryKey: ['invoices'] });
      notifications.show({
        title: `Order placed — ${res.data.data.document_number}`,
        message: res.data.message,
        color: 'teal', icon: <IconCheck size={16} />, autoClose: 8000,
      });
      navigate('/invoices');
    },
    onError: (e: unknown) => {
      const msg = (e as { response?: { data?: { message?: string } } })?.response?.data?.message;
      notifications.show({ message: msg ?? 'Order failed.', color: 'red' });
    },
  });

  if (isLoading) return <Group justify="center" py="xl"><Loader /></Group>;

  return (
    <Grid>
      <Grid.Col span={{ base: 12, md: 8 }}>
        <Stack>
          <Paper withBorder p="md" radius="md">
            <Stack gap="sm">
              <Select
                label="Product / Service"
                placeholder="Choose a product"
                searchable
                value={productId}
                onChange={(v) => {
                  setProductId(v);
                  setProductAddonIds([]); setConfigSel({}); setCouponInfo(null);
                }}
                data={groups.map((g) => ({
                  group: g.name,
                  items: g.products.map((p) => ({
                    value: p.id,
                    label: `${p.name} — ${formatCurrency(p.price)}${p.billing_cycle ? ` / ${p.billing_cycle}` : ''}`,
                  })),
                }))}
                leftSection={<IconPackage size={16} />}
              />
              {product && (
                <TextInput
                  label={needsDomain ? 'Domain for this hosting service' : 'Label (optional)'}
                  placeholder={needsDomain ? 'example.co.tz' : 'e.g. project name'}
                  value={label}
                  onChange={(e) => setLabel(e.currentTarget.value)}
                  required={needsDomain}
                />
              )}
              {needsDomain && (
                <>
                  <Radio.Group
                    label="Domain option"
                    value={domainMode}
                    onChange={(v) => setDomainMode(v as typeof domainMode)}
                  >
                    <Group mt={4}>
                      <Radio value="existing" label="Use existing domain" />
                      <Radio value="register" label="Register new" />
                      <Radio value="transfer" label="Transfer in" />
                    </Group>
                  </Radio.Group>
                  {domainMode !== 'existing' && (
                    <Group align="flex-end">
                      <NumberInput
                        label="Years" w={100} min={tldRow?.years_min ?? 1} max={tldRow?.years_max ?? 10}
                        value={years} onChange={(v) => setYears(Number(v) || 1)}
                      />
                      {tldRow && (
                        <Badge variant="light" mb={6}>
                          .{tldRow.tld}: {formatCurrency(domainMode === 'register' ? tldRow.register_price : tldRow.transfer_price)}/yr
                        </Badge>
                      )}
                      {domain.includes('.') && !tldRow && tlds.length > 0 && (
                        <Badge color="red" variant="light" mb={6}>TLD not offered</Badge>
                      )}
                    </Group>
                  )}
                  {domainMode === 'transfer' && (
                    <TextInput
                      label="EPP / Auth code" value={authInfo} required
                      onChange={(e) => setAuthInfo(e.currentTarget.value)}
                    />
                  )}
                  {domainMode !== 'existing' && domainAddons.length > 0 && (
                    <Checkbox.Group label="Domain add-ons" value={domainAddonIds} onChange={setDomainAddonIds}>
                      <Stack gap={6} mt={4}>
                        {domainAddons.map((a) => (
                          <Checkbox key={a.id} value={a.id}
                            label={`${a.name}${a.is_free ? ' (free)' : ` — ${formatCurrency(a.price)}`}`} />
                        ))}
                      </Stack>
                    </Checkbox.Group>
                  )}
                </>
              )}
            </Stack>
          </Paper>

          {productAddons.length > 0 && (
            <Paper withBorder p="md" radius="md">
              <Checkbox.Group label="Add-ons" value={productAddonIds} onChange={setProductAddonIds}>
                <Stack gap={6} mt={4}>
                  {productAddons.map((a) => (
                    <Checkbox key={a.id} value={a.id}
                      label={`${a.name} — ${formatCurrency(a.price)}${a.billing_cycle ? ` / ${a.billing_cycle}` : ''}`}
                      description={a.description ?? undefined} />
                  ))}
                </Stack>
              </Checkbox.Group>
            </Paper>
          )}

          {configGroups.length > 0 && (
            <Paper withBorder p="md" radius="md">
              <Stack gap="sm">
                <Text fw={600} size="sm">Configurable options</Text>
                {configGroups.map((g) => (
                  <div key={g.id}>
                    <Text size="sm" c="dimmed">{g.name}</Text>
                    <Stack gap="xs" mt={4}>
                      {g.options.map((o) => {
                        const sel = configSel[o.id] ?? {};
                        if (o.option_type === 'dropdown' || o.option_type === 'radio') {
                          return (
                            <Select key={o.id} label={o.name} clearable
                              value={sel.choice_id ?? null}
                              onChange={(v) => setConfigSel((s) => ({ ...s, [o.id]: { choice_id: v ?? undefined } }))}
                              data={o.choices.map((c) => ({
                                value: c.id, label: `${c.label} — ${formatCurrency(c.price)}`,
                              }))} />
                          );
                        }
                        if (o.option_type === 'quantity') {
                          return (
                            <NumberInput key={o.id} min={0} max={10000}
                              label={`${o.name} (${formatCurrency(o.unit_price ?? 0)} each)`}
                              value={sel.quantity ?? 0}
                              onChange={(v) => setConfigSel((s) => ({ ...s, [o.id]: { quantity: Number(v) || undefined } }))} />
                          );
                        }
                        return (
                          <Checkbox key={o.id}
                            label={`${o.name}${o.unit_price ? ` — ${formatCurrency(o.unit_price)}` : ''}`}
                            checked={!!sel.on}
                            onChange={(e) => setConfigSel((s) => ({ ...s, [o.id]: { on: e.currentTarget.checked } }))} />
                        );
                      })}
                    </Stack>
                  </div>
                ))}
              </Stack>
            </Paper>
          )}
        </Stack>
      </Grid.Col>

      <Grid.Col span={{ base: 12, md: 4 }}>
        <Card withBorder radius="md" p="md">
          <Stack gap="sm">
            <Text fw={600}>Summary</Text>
            {product ? (
              <>
                <Group justify="space-between">
                  <Text size="sm">{product.name}</Text>
                  <Text size="sm" fw={600}>{formatCurrency(product.price)}</Text>
                </Group>
                {product.billing_cycle && <Text size="xs" c="dimmed">Billed {product.billing_cycle}</Text>}
              </>
            ) : (
              <Text size="sm" c="dimmed">No product selected.</Text>
            )}
            <Divider />
            <Group gap="xs" align="flex-end">
              <TextInput
                label="Promo code" size="xs" style={{ flex: 1 }}
                leftSection={<IconTicket size={14} />}
                value={couponCode}
                onChange={(e) => { setCouponCode(e.currentTarget.value); setCouponInfo(null); }}
              />
              <Button size="xs" variant="light" onClick={checkCoupon} disabled={!couponCode.trim() || !productId}>
                Apply
              </Button>
            </Group>
            {couponInfo && (
              <Alert color={couponInfo.valid ? 'teal' : 'red'} p="xs">
                <Text size="xs">{couponInfo.message}</Text>
              </Alert>
            )}
            <Divider />
            <Group justify="space-between">
              <Text fw={700}>Estimated total</Text>
              <Text fw={700}>{formatCurrency(estimate)}</Text>
            </Group>
            <Button
              leftSection={<IconShoppingCart size={16} />}
              disabled={!productId || (needsDomain && !domain) || (domainMode === 'transfer' && !authInfo.trim())}
              loading={placeMutation.isPending}
              onClick={() => placeMutation.mutate()}
            >
              Place Order
            </Button>
            <Text size="xs" c="dimmed">
              Creates a pending service and an invoice; payment activates the service.
            </Text>
          </Stack>
        </Card>
      </Grid.Col>
    </Grid>
  );
}

// ── Standalone domain order ───────────────────────────────────────────────────

function DomainOrderForm({ clientId }: { clientId: string }) {
  const navigate = useNavigate();
  const [name, setName] = useState('');
  const [action, setAction] = useState<'register' | 'transfer'>('register');
  const [years, setYears] = useState(1);
  const [authInfo, setAuthInfo] = useState('');

  const { data: tldsRes } = useQuery({ queryKey: ['order-tlds'], queryFn: getOrderDomainTlds });
  const tlds = tldsRes?.data?.data ?? [];
  const domain = name.trim().toLowerCase();
  const tldRow = domain.includes('.')
    ? tlds.find((t) => t.tld === domain.split('.').slice(1).join('.')) ?? null
    : null;
  const unit = tldRow ? (action === 'register' ? tldRow.register_price : tldRow.transfer_price) : 0;

  const orderMutation = useMutation({
    mutationFn: () => orderDomain({
      name: domain, client_id: clientId, years, action,
      auth_info: action === 'transfer' ? authInfo : undefined,
    }),
    onSuccess: () => {
      notifications.show({
        title: 'Domain order placed',
        message: `${domain} — an invoice was created; payment triggers the ${action}.`,
        color: 'teal', icon: <IconCheck size={16} />, autoClose: 8000,
      });
      navigate('/domains');
    },
    onError: (e: unknown) => {
      const msg = (e as { response?: { data?: { message?: string } } })?.response?.data?.message;
      notifications.show({ message: msg ?? 'Order failed.', color: 'red' });
    },
  });

  return (
    <Grid>
      <Grid.Col span={{ base: 12, md: 8 }}>
        <Paper withBorder p="md" radius="md">
          <Stack gap="sm">
            <TextInput
              label="Domain name" placeholder="example.co.tz" required
              leftSection={<IconWorldWww size={16} />}
              value={name} onChange={(e) => setName(e.currentTarget.value)}
            />
            <SegmentedControl
              value={action}
              onChange={(v) => setAction(v as 'register' | 'transfer')}
              data={[{ value: 'register', label: 'Register' }, { value: 'transfer', label: 'Transfer in' }]}
            />
            <Group align="flex-end">
              <NumberInput
                label="Years" w={100} min={tldRow?.years_min ?? 1} max={tldRow?.years_max ?? 10}
                value={years} onChange={(v) => setYears(Number(v) || 1)}
              />
              {tldRow && <Badge variant="light" mb={6}>.{tldRow.tld}: {formatCurrency(unit)}/yr</Badge>}
              {domain.includes('.') && !tldRow && tlds.length > 0 && (
                <Badge color="red" variant="light" mb={6}>TLD not offered — add pricing in Settings → Domains</Badge>
              )}
            </Group>
            {action === 'transfer' && (
              <TextInput
                label="EPP / Auth code" required value={authInfo}
                onChange={(e) => setAuthInfo(e.currentTarget.value)}
              />
            )}
          </Stack>
        </Paper>
      </Grid.Col>
      <Grid.Col span={{ base: 12, md: 4 }}>
        <Card withBorder radius="md" p="md">
          <Stack gap="sm">
            <Text fw={600}>Summary</Text>
            <Group justify="space-between">
              <Text size="sm">{domain || '—'} × {years} yr</Text>
              <Text size="sm" fw={600}>{formatCurrency(unit * years)}</Text>
            </Group>
            <Button
              leftSection={<IconShoppingCart size={16} />}
              disabled={!tldRow || (action === 'transfer' && !authInfo.trim())}
              loading={orderMutation.isPending}
              onClick={() => orderMutation.mutate()}
            >
              Place Order
            </Button>
            <Text size="xs" c="dimmed">
              Creates a pending domain and an invoice; payment triggers the {action} at the registry.
            </Text>
          </Stack>
        </Card>
      </Grid.Col>
    </Grid>
  );
}
