import { useState } from 'react';
import {
  Title, Group, Button, TextInput, Modal, Table, Badge, ActionIcon,
  Textarea, NumberInput, Select, Switch, MultiSelect, Stack, Text, Paper, Divider,
} from '@mantine/core';
import { modals } from '@mantine/modals';
import { notifications } from '@mantine/notifications';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { IconPlus, IconPencil, IconTrash } from '@tabler/icons-react';
import {
  getConfigOptionGroups, createConfigOptionGroup, updateConfigOptionGroup,
  deleteConfigOptionGroup, ConfigOptionGroup, ConfigOption, ConfigOptionType,
} from '../api/configOptions';
import { getProductServices } from '../api/productServices';

const typeOptions: { value: ConfigOptionType; label: string }[] = [
  { value: 'dropdown', label: 'Dropdown' },
  { value: 'radio', label: 'Radio' },
  { value: 'yesno', label: 'Yes / No' },
  { value: 'quantity', label: 'Quantity' },
];

const hasChoices = (t: ConfigOptionType) => t === 'dropdown' || t === 'radio';

const blankOption = (): ConfigOption => ({
  name: '', option_type: 'dropdown', unit_price: 0, sort_order: 0, choices: [],
});

export default function ConfigOptions() {
  const qc = useQueryClient();
  const [modalOpen, setModalOpen] = useState(false);
  const [editing, setEditing] = useState<ConfigOptionGroup | null>(null);

  // Group-level fields
  const [name, setName] = useState('');
  const [description, setDescription] = useState('');
  const [isActive, setIsActive] = useState(true);
  const [productIds, setProductIds] = useState<string[]>([]);
  const [options, setOptions] = useState<ConfigOption[]>([]);

  const { data } = useQuery({ queryKey: ['config-option-groups'], queryFn: () => getConfigOptionGroups() });
  const groups = data?.data?.data ?? [];

  const { data: productsData } = useQuery({
    queryKey: ['config-options-products'],
    queryFn: () => getProductServices({ type: 'product', per_page: 200 }),
  });
  const productOptions = (productsData?.data?.data ?? []).map((p: any) => ({ value: p.id, label: p.name }));

  const resetForm = () => {
    setName(''); setDescription(''); setIsActive(true); setProductIds([]); setOptions([]);
  };

  const openCreate = () => {
    setEditing(null); resetForm(); setModalOpen(true);
  };

  const openEdit = (g: ConfigOptionGroup) => {
    setEditing(g);
    setName(g.name);
    setDescription(g.description ?? '');
    setIsActive(g.is_active);
    setProductIds(g.product_service_ids ?? []);
    setOptions((g.options ?? []).map((o) => ({
      ...o,
      unit_price: o.unit_price ?? 0,
      choices: (o.choices ?? []).map((c) => ({ ...c })),
    })));
    setModalOpen(true);
  };

  const close = () => { setModalOpen(false); setEditing(null); resetForm(); };

  const saveMutation = useMutation({
    mutationFn: () => {
      const payload = {
        name, description, is_active: isActive, product_service_ids: productIds,
        options: options.map((o, i) => ({
          id: o.id,
          name: o.name,
          option_type: o.option_type,
          unit_price: hasChoices(o.option_type) ? null : Number(o.unit_price ?? 0),
          sort_order: i,
          choices: hasChoices(o.option_type)
            ? o.choices.map((c, ci) => ({ id: c.id, label: c.label, price: Number(c.price ?? 0), sort_order: ci }))
            : [],
        })),
      };
      return editing ? updateConfigOptionGroup(editing.id, payload) : createConfigOptionGroup(payload);
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['config-option-groups'] });
      close();
      notifications.show({ title: 'Success', message: editing ? 'Group updated' : 'Group created', color: 'green' });
    },
    onError: (e: any) => notifications.show({ message: e?.response?.data?.message ?? 'Save failed', color: 'red' }),
  });

  const deleteMutation = useMutation({
    mutationFn: (id: string) => deleteConfigOptionGroup(id),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['config-option-groups'] });
      notifications.show({ title: 'Deleted', message: 'Group deleted', color: 'green' });
    },
  });

  const confirmDelete = (g: ConfigOptionGroup) =>
    modals.openConfirmModal({
      title: 'Delete Option Group',
      children: `Delete "${g.name}"? Existing services already using it keep their configured copy.`,
      labels: { confirm: 'Delete', cancel: 'Cancel' },
      confirmProps: { color: 'red' },
      onConfirm: () => deleteMutation.mutate(g.id),
    });

  // ── Option list editing helpers ─────────────────────────────────────────────
  const updateOption = (idx: number, patch: Partial<ConfigOption>) =>
    setOptions((cur) => cur.map((o, i) => (i === idx ? { ...o, ...patch } : o)));
  const addOption = () => setOptions((cur) => [...cur, blankOption()]);
  const removeOption = (idx: number) => setOptions((cur) => cur.filter((_, i) => i !== idx));
  const addChoice = (idx: number) =>
    setOptions((cur) => cur.map((o, i) => (i === idx ? { ...o, choices: [...o.choices, { label: '', price: 0 }] } : o)));
  const updateChoice = (idx: number, ci: number, patch: Partial<{ label: string; price: number }>) =>
    setOptions((cur) => cur.map((o, i) => (i === idx
      ? { ...o, choices: o.choices.map((c, j) => (j === ci ? { ...c, ...patch } : c)) } : o)));
  const removeChoice = (idx: number, ci: number) =>
    setOptions((cur) => cur.map((o, i) => (i === idx ? { ...o, choices: o.choices.filter((_, j) => j !== ci) } : o)));

  const canSave = name.trim().length > 0
    && options.every((o) => o.name.trim() && (!hasChoices(o.option_type) || o.choices.length > 0)
      && (!hasChoices(o.option_type) || o.choices.every((c) => c.label.trim())));

  return (
    <>
      <Group justify="space-between" mb="md" wrap="wrap">
        <Title order={2}>Configurable Options</Title>
        <Button leftSection={<IconPlus size={16} />} onClick={openCreate}>Add Group</Button>
      </Group>

      <Text c="dimmed" size="sm" mb="md">
        Option groups (e.g. "Server Specs") bundle options — dropdown, radio, yes/no or quantity — that clients
        configure when ordering a product. Selected options are priced onto the order invoice and billed on each renewal.
      </Text>

      <Table.ScrollContainer minWidth={700}>
        <Table striped highlightOnHover>
          <Table.Thead>
            <Table.Tr>
              <Table.Th>Name</Table.Th>
              <Table.Th>Options</Table.Th>
              <Table.Th>Offered on</Table.Th>
              <Table.Th>Status</Table.Th>
              <Table.Th />
            </Table.Tr>
          </Table.Thead>
          <Table.Tbody>
            {groups.length === 0 && (
              <Table.Tr><Table.Td colSpan={5}><Text c="dimmed" ta="center" py="md">No option groups yet.</Text></Table.Td></Table.Tr>
            )}
            {groups.map((g) => (
              <Table.Tr key={g.id}>
                <Table.Td>{g.name}</Table.Td>
                <Table.Td>
                  <Group gap={4}>
                    {g.options.length ? g.options.map((o) => (
                      <Badge key={o.id} variant="light" size="sm">{o.name}</Badge>
                    )) : <Text c="dimmed" size="sm">—</Text>}
                  </Group>
                </Table.Td>
                <Table.Td>
                  {g.products.length ? (
                    <Group gap={4}>{g.products.map((p) => <Badge key={p.id} variant="light" color="grape" size="sm">{p.name}</Badge>)}</Group>
                  ) : <Text c="dimmed" size="sm">—</Text>}
                </Table.Td>
                <Table.Td>
                  <Badge color={g.is_active ? 'green' : 'gray'} variant="light">{g.is_active ? 'Active' : 'Inactive'}</Badge>
                </Table.Td>
                <Table.Td>
                  <Group gap={4} justify="flex-end" wrap="nowrap">
                    <ActionIcon variant="subtle" onClick={() => openEdit(g)}><IconPencil size={16} /></ActionIcon>
                    <ActionIcon variant="subtle" color="red" onClick={() => confirmDelete(g)}><IconTrash size={16} /></ActionIcon>
                  </Group>
                </Table.Td>
              </Table.Tr>
            ))}
          </Table.Tbody>
        </Table>
      </Table.ScrollContainer>

      <Modal opened={modalOpen} onClose={close} title={editing ? 'Edit Option Group' : 'New Option Group'} size="xl">
        <Stack gap="sm">
          <TextInput label="Group name" required placeholder="e.g. Server Specs"
            value={name} onChange={(e) => setName(e.currentTarget.value)} />
          <Textarea label="Description" autosize minRows={2}
            value={description} onChange={(e) => setDescription(e.currentTarget.value)} />
          <MultiSelect label="Offered on products" placeholder="Select products that use this group"
            data={productOptions} searchable clearable value={productIds} onChange={setProductIds} />
          <Switch label="Active" checked={isActive} onChange={(e) => setIsActive(e.currentTarget.checked)} />

          <Divider label="Options" labelPosition="left" mt="sm" />

          <Stack gap="sm">
            {options.map((o, idx) => (
              <Paper key={idx} withBorder p="sm" radius="md">
                <Group align="flex-end" wrap="nowrap" mb={hasChoices(o.option_type) ? 'sm' : 0}>
                  <TextInput label="Option name" required style={{ flex: 1 }} placeholder="e.g. RAM"
                    value={o.name} onChange={(e) => updateOption(idx, { name: e.currentTarget.value })} />
                  <Select label="Type" w={140} data={typeOptions} value={o.option_type}
                    onChange={(v) => updateOption(idx, { option_type: (v as ConfigOptionType) })} />
                  {!hasChoices(o.option_type) && (
                    <NumberInput label={o.option_type === 'quantity' ? 'Unit price' : 'Price'} w={140} min={0}
                      decimalScale={2} value={o.unit_price ?? 0}
                      onChange={(v) => updateOption(idx, { unit_price: Number(v) || 0 })} />
                  )}
                  <ActionIcon variant="subtle" color="red" mb={4} onClick={() => removeOption(idx)}>
                    <IconTrash size={16} />
                  </ActionIcon>
                </Group>

                {hasChoices(o.option_type) && (
                  <Stack gap={6} pl="sm">
                    {o.choices.map((c, ci) => (
                      <Group key={ci} align="flex-end" wrap="nowrap">
                        <TextInput label={ci === 0 ? 'Choice label' : undefined} required style={{ flex: 1 }}
                          placeholder="e.g. 8GB" value={c.label}
                          onChange={(e) => updateChoice(idx, ci, { label: e.currentTarget.value })} />
                        <NumberInput label={ci === 0 ? 'Price' : undefined} w={140} min={0} decimalScale={2}
                          value={c.price} onChange={(v) => updateChoice(idx, ci, { price: Number(v) || 0 })} />
                        <ActionIcon variant="subtle" color="red" mb={4} onClick={() => removeChoice(idx, ci)}>
                          <IconTrash size={16} />
                        </ActionIcon>
                      </Group>
                    ))}
                    <Button size="compact-sm" variant="light" leftSection={<IconPlus size={14} />}
                      onClick={() => addChoice(idx)} w="fit-content">
                      Add choice
                    </Button>
                  </Stack>
                )}
              </Paper>
            ))}
            <Button variant="light" leftSection={<IconPlus size={16} />} onClick={addOption} w="fit-content">
              Add option
            </Button>
          </Stack>

          <Group justify="flex-end" mt="sm">
            <Button variant="default" onClick={close}>Cancel</Button>
            <Button disabled={!canSave} loading={saveMutation.isPending} onClick={() => saveMutation.mutate()}>
              {editing ? 'Save' : 'Create'}
            </Button>
          </Group>
        </Stack>
      </Modal>
    </>
  );
}
