import { useState } from 'react';
import {
  Title, Group, Button, TextInput, Modal, Table, Badge, ActionIcon,
  Textarea, NumberInput, Select, Switch, MultiSelect, Stack, Text, Tooltip,
} from '@mantine/core';
import { useForm } from '@mantine/form';
import { modals } from '@mantine/modals';
import { notifications } from '@mantine/notifications';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { IconPlus, IconPencil, IconTrash, IconHistory } from '@tabler/icons-react';
import {
  getCoupons, createCoupon, updateCoupon, deleteCoupon, getCouponRedemptions,
  Coupon, CouponFormData,
} from '../api/coupons';
import { getProductServices } from '../api/productServices';

const emptyForm: CouponFormData = {
  code: '', description: '', type: 'percent', value: 0, applies_to: 'all',
  max_uses: null, min_order: null, starts_at: null, expires_at: null,
  recurring: false, is_active: true, product_service_ids: [],
};

// datetime-local <-> ISO helpers
const toLocal = (iso: string | null | undefined) => (iso ? iso.slice(0, 16) : '');
const fromLocal = (v: string) => (v ? new Date(v).toISOString() : null);

export default function Coupons() {
  const qc = useQueryClient();
  const [modalOpen, setModalOpen] = useState(false);
  const [editing, setEditing] = useState<Coupon | null>(null);
  const [redeemFor, setRedeemFor] = useState<Coupon | null>(null);

  const { data } = useQuery({ queryKey: ['coupons'], queryFn: () => getCoupons() });
  const coupons = data?.data?.data ?? [];

  const { data: productsData } = useQuery({
    queryKey: ['coupons-products'],
    queryFn: () => getProductServices({ type: 'product', per_page: 200 }),
  });
  const productOptions = (productsData?.data?.data ?? []).map((p: any) => ({ value: p.id, label: p.name }));

  const form = useForm<CouponFormData>({
    initialValues: emptyForm,
    validate: {
      code: (v) => (v.trim() ? null : 'Code is required'),
      value: (v) => (v >= 0 ? null : 'Value must be ≥ 0'),
    },
  });

  const openCreate = () => {
    setEditing(null);
    form.setValues(emptyForm);
    setModalOpen(true);
  };

  const openEdit = (c: Coupon) => {
    setEditing(c);
    form.setValues({
      code: c.code, description: c.description ?? '', type: c.type, value: Number(c.value),
      applies_to: c.applies_to, max_uses: c.max_uses, min_order: c.min_order,
      starts_at: c.starts_at, expires_at: c.expires_at, recurring: c.recurring,
      is_active: c.is_active, product_service_ids: c.product_service_ids ?? [],
    });
    setModalOpen(true);
  };

  const saveMutation = useMutation({
    mutationFn: (values: CouponFormData) =>
      editing ? updateCoupon(editing.id, values) : createCoupon(values),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['coupons'] });
      setModalOpen(false);
      setEditing(null);
      notifications.show({ title: 'Success', message: editing ? 'Coupon updated' : 'Coupon created', color: 'green' });
    },
    onError: (e: any) => notifications.show({ message: e?.response?.data?.message ?? 'Save failed', color: 'red' }),
  });

  const deleteMutation = useMutation({
    mutationFn: (id: string) => deleteCoupon(id),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['coupons'] });
      notifications.show({ title: 'Deleted', message: 'Coupon deleted', color: 'green' });
    },
  });

  const confirmDelete = (c: Coupon) =>
    modals.openConfirmModal({
      title: 'Delete Coupon',
      children: `Delete "${c.code}"? Orders that already used it keep their applied discount.`,
      labels: { confirm: 'Delete', cancel: 'Cancel' },
      confirmProps: { color: 'red' },
      onConfirm: () => deleteMutation.mutate(c.id),
    });

  const usesLabel = (c: Coupon) => `${c.uses}${c.max_uses != null ? ` / ${c.max_uses}` : ''}`;

  return (
    <>
      <Group justify="space-between" mb="md" wrap="wrap">
        <Title order={2}>Promotions / Coupon Codes</Title>
        <Button leftSection={<IconPlus size={16} />} onClick={openCreate}>Add New</Button>
      </Group>

      <Text c="dimmed" size="sm" mb="md">
        Discount codes clients enter at checkout. Percent or fixed amount, optionally limited to specific products,
        a minimum order, a usage cap, and an active window. Recurring coupons keep discounting renewals.
      </Text>

      <Table.ScrollContainer minWidth={860}>
        <Table striped highlightOnHover>
          <Table.Thead>
            <Table.Tr>
              <Table.Th>Code</Table.Th>
              <Table.Th>Discount</Table.Th>
              <Table.Th>Applies to</Table.Th>
              <Table.Th>Uses</Table.Th>
              <Table.Th>Expires</Table.Th>
              <Table.Th>Recurring</Table.Th>
              <Table.Th>Status</Table.Th>
              <Table.Th />
            </Table.Tr>
          </Table.Thead>
          <Table.Tbody>
            {coupons.length === 0 && (
              <Table.Tr><Table.Td colSpan={8}><Text c="dimmed" ta="center" py="md">No coupons yet.</Text></Table.Td></Table.Tr>
            )}
            {coupons.map((c) => (
              <Table.Tr key={c.id}>
                <Table.Td><Text fw={600}>{c.code}</Text></Table.Td>
                <Table.Td>{c.type === 'percent' ? `${Number(c.value)}%` : Number(c.value).toLocaleString(undefined, { minimumFractionDigits: 2 })}</Table.Td>
                <Table.Td>
                  {c.applies_to === 'all' ? <Text size="sm">All products</Text> : (
                    c.products.length ? (
                      <Group gap={4}>{c.products.map((p) => <Badge key={p.id} variant="light" size="sm">{p.name}</Badge>)}</Group>
                    ) : <Text c="dimmed" size="sm">— none linked —</Text>
                  )}
                </Table.Td>
                <Table.Td>{usesLabel(c)}</Table.Td>
                <Table.Td>{c.expires_at ? new Date(c.expires_at).toLocaleDateString() : <Text c="dimmed" size="sm">—</Text>}</Table.Td>
                <Table.Td>{c.recurring ? <Badge color="blue" variant="light">Renews</Badge> : <Text c="dimmed" size="sm">One-time</Text>}</Table.Td>
                <Table.Td>
                  <Badge color={c.is_active ? 'green' : 'gray'} variant="light">{c.is_active ? 'Active' : 'Inactive'}</Badge>
                </Table.Td>
                <Table.Td>
                  <Group gap={4} justify="flex-end" wrap="nowrap">
                    <Tooltip label="Redemption history"><ActionIcon variant="subtle" onClick={() => setRedeemFor(c)}><IconHistory size={16} /></ActionIcon></Tooltip>
                    <ActionIcon variant="subtle" onClick={() => openEdit(c)}><IconPencil size={16} /></ActionIcon>
                    <ActionIcon variant="subtle" color="red" onClick={() => confirmDelete(c)}><IconTrash size={16} /></ActionIcon>
                  </Group>
                </Table.Td>
              </Table.Tr>
            ))}
          </Table.Tbody>
        </Table>
      </Table.ScrollContainer>

      <Modal opened={modalOpen} onClose={() => { setModalOpen(false); setEditing(null); }}
        title={editing ? 'Edit Coupon' : 'New Coupon'} size="lg">
        <form onSubmit={form.onSubmit((v) => saveMutation.mutate({
          ...v,
          starts_at: fromLocal(toLocal(v.starts_at)),
          expires_at: fromLocal(toLocal(v.expires_at)),
        }))}>
          <Stack gap="sm">
            <Group grow>
              <TextInput label="Code" required placeholder="e.g. WELCOME10"
                {...form.getInputProps('code')}
                onChange={(e) => form.setFieldValue('code', e.currentTarget.value.toUpperCase())} />
              <Select label="Type" data={[{ value: 'percent', label: 'Percentage' }, { value: 'fixed', label: 'Fixed amount' }]}
                {...form.getInputProps('type')} />
              <NumberInput label={form.values.type === 'percent' ? 'Percent %' : 'Amount'}
                min={0} decimalScale={2} {...form.getInputProps('value')} />
            </Group>
            <Textarea label="Description" autosize minRows={1} {...form.getInputProps('description')} />
            <Group grow>
              <Select label="Applies to" data={[{ value: 'all', label: 'All products' }, { value: 'product', label: 'Specific products' }]}
                {...form.getInputProps('applies_to')} />
              <NumberInput label="Max uses (blank = unlimited)" min={1} allowDecimal={false}
                {...form.getInputProps('max_uses')} />
              <NumberInput label="Min order (blank = none)" min={0} decimalScale={2}
                {...form.getInputProps('min_order')} />
            </Group>
            {form.values.applies_to === 'product' && (
              <MultiSelect label="Eligible products" placeholder="Select products this coupon discounts"
                data={productOptions} searchable clearable {...form.getInputProps('product_service_ids')} />
            )}
            <Group grow>
              <TextInput type="datetime-local" label="Starts at (optional)"
                value={toLocal(form.values.starts_at)}
                onChange={(e) => form.setFieldValue('starts_at', e.currentTarget.value || null)} />
              <TextInput type="datetime-local" label="Expires at (optional)"
                value={toLocal(form.values.expires_at)}
                onChange={(e) => form.setFieldValue('expires_at', e.currentTarget.value || null)} />
            </Group>
            <Group>
              <Switch label="Recurring (discount renewals too)" {...form.getInputProps('recurring', { type: 'checkbox' })} />
              <Switch label="Active" {...form.getInputProps('is_active', { type: 'checkbox' })} />
            </Group>
            <Group justify="flex-end" mt="sm">
              <Button variant="default" onClick={() => { setModalOpen(false); setEditing(null); }}>Cancel</Button>
              <Button type="submit" loading={saveMutation.isPending}>{editing ? 'Save' : 'Create'}</Button>
            </Group>
          </Stack>
        </form>
      </Modal>

      <RedemptionsModal coupon={redeemFor} onClose={() => setRedeemFor(null)} />
    </>
  );
}

function RedemptionsModal({ coupon, onClose }: { coupon: Coupon | null; onClose: () => void }) {
  const { data } = useQuery({
    queryKey: ['coupon-redemptions', coupon?.id],
    queryFn: () => getCouponRedemptions(coupon!.id),
    enabled: !!coupon,
  });
  const rows = data?.data?.data ?? [];

  return (
    <Modal opened={!!coupon} onClose={onClose} title={`Redemptions — ${coupon?.code ?? ''}`} size="lg">
      <Table striped>
        <Table.Thead>
          <Table.Tr>
            <Table.Th>When</Table.Th>
            <Table.Th>Client</Table.Th>
            <Table.Th>Discount</Table.Th>
          </Table.Tr>
        </Table.Thead>
        <Table.Tbody>
          {rows.length === 0 && (
            <Table.Tr><Table.Td colSpan={3}><Text c="dimmed" ta="center" py="md">No redemptions yet.</Text></Table.Td></Table.Tr>
          )}
          {rows.map((r) => (
            <Table.Tr key={r.id}>
              <Table.Td>{new Date(r.created_at).toLocaleString()}</Table.Td>
              <Table.Td>{r.client_name ?? '—'}</Table.Td>
              <Table.Td>{Number(r.discount_amount).toLocaleString(undefined, { minimumFractionDigits: 2 })}</Table.Td>
            </Table.Tr>
          ))}
        </Table.Tbody>
      </Table>
    </Modal>
  );
}
