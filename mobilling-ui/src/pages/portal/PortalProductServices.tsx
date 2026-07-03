import { useState } from 'react';
import {
  Stack, Paper, Title, Text, Group, LoadingOverlay, Grid, Button, NavLink,
  SimpleGrid, Modal, TextInput, Badge, Divider, Center,
} from '@mantine/core';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { notifications } from '@mantine/notifications';
import { useNavigate } from 'react-router-dom';
import {
  IconShoppingCart, IconRefresh, IconWorldWww, IconArrowRight, IconReceipt,
  IconCheck, IconPlus,
} from '@tabler/icons-react';
import {
  getPortalCatalog, placePortalOrder, CatalogGroup, CatalogProduct,
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
  const [label, setLabel] = useState('');

  const mutation = useMutation({
    mutationFn: () => placePortalOrder({
      product_service_id: product!.id,
      label: label.trim() || undefined,
    }),
    onSuccess: (res: any) => {
      qc.invalidateQueries({ queryKey: ['portal-subscriptions'] });
      qc.invalidateQueries({ queryKey: ['portal-dashboard'] });
      notifications.show({ title: 'Order placed', message: res?.data?.message, color: 'green', autoClose: 9000 });
      setLabel('');
      onClose();
      onDone();
    },
    onError: (e: any) => notifications.show({
      message: e?.response?.data?.message ?? 'Order failed.', color: 'red',
    }),
  });

  const canSubmit = product && (!product.needs_domain || label.trim().length > 3);

  return (
    <Modal opened={!!product} onClose={onClose} title={`Order — ${product?.name}`} centered>
      {product && (
        <Stack gap="sm">
          {product.needs_domain ? (
            <TextInput label="Domain for this hosting service" placeholder="yourdomain.co.tz" required
              description="Your account is created for this domain automatically after payment."
              value={label} onChange={(e) => setLabel(e.currentTarget.value)} />
          ) : (
            <TextInput label="Reference / label (optional)" placeholder="e.g. project or domain name"
              value={label} onChange={(e) => setLabel(e.currentTarget.value)} />
          )}

          <Paper withBorder p="sm" radius="md">
            <Group justify="space-between">
              <Text size="sm">{product.name}</Text>
              <Text fw={700}>Tsh.{fmt(product.price)}</Text>
            </Group>
            <Text size="xs" c="dimmed" mt={2}>
              Billed {cycleLabel[product.billing_cycle ?? '']?.toLowerCase() ?? ''} — an invoice is created
              now and your service activates when it is paid.
            </Text>
          </Paper>

          <Group justify="flex-end">
            <Button variant="default" onClick={onClose}>Cancel</Button>
            <Button color="green" disabled={!canSubmit} loading={mutation.isPending}
              onClick={() => mutation.mutate()}>
              Place Order
            </Button>
          </Group>
        </Stack>
      )}
    </Modal>
  );
}
