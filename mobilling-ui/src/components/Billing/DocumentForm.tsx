import { useState } from 'react';
import { Select, NumberInput, Textarea, Table, Button, Group, ActionIcon, Badge, Stack, Text, Combobox, TextInput, useCombobox } from '@mantine/core';
import { DateInput } from '@mantine/dates';
import { useForm } from '@mantine/form';
import { IconPlus, IconTrash } from '@tabler/icons-react';
import { Client } from '../../api/clients';
import { ProductService } from '../../api/productServices';
import { formatCurrency } from '../../utils/formatCurrency';
import dayjs from 'dayjs';

interface Props {
  clients: Client[];
  productServices: ProductService[];
  type: 'quotation' | 'proforma' | 'invoice';
  onSubmit: (values: any) => void;
  loading?: boolean;
  initialValues?: any;
}

const emptyItem = { product_service_id: '', item_type: 'product' as const, description: '', quantity: 1, price: 0, discount_type: 'flat' as const, discount_value: 0, tax_percent: 0, unit: '' };

function ProductServiceInput({ productServices, productServiceId, description, onChange }: {
  productServices: ProductService[];
  productServiceId: string;
  description: string;
  onChange: (id: string | null, customName: string | null) => void;
}) {
  const combobox = useCombobox({ onDropdownClose: () => combobox.resetSelectedOption() });
  const [, setSelectedId] = useState(productServiceId);
  const [search, setSearch] = useState(() => {
    if (productServiceId) {
      const found = productServices.find(ps => ps.id === productServiceId);
      return found ? `${found.name}${found.code ? ` (${found.code})` : ''}` : description;
    }
    return description || '';
  });

  const filtered = productServices.filter(ps =>
    ps.name.toLowerCase().includes(search.toLowerCase().trim()) ||
    (ps.code && ps.code.toLowerCase().includes(search.toLowerCase().trim()))
  );

  const options = filtered.map(ps => (
    <Combobox.Option value={ps.id} key={ps.id}>
      {ps.name}{ps.code ? ` (${ps.code})` : ''}
    </Combobox.Option>
  ));

  return (
    <Combobox
      store={combobox}
      onOptionSubmit={(val) => {
        const ps = productServices.find(p => p.id === val);
        if (ps) {
          setSearch(`${ps.name}${ps.code ? ` (${ps.code})` : ''}`);
          setSelectedId(ps.id);
          onChange(ps.id, null);
        }
        combobox.closeDropdown();
      }}
    >
      <Combobox.Target>
        <TextInput
          placeholder="Type or select item"
          size="sm"
          value={search}
          onChange={(e) => {
            const val = e.currentTarget.value;
            setSearch(val);
            setSelectedId('');
            combobox.openDropdown();
            combobox.updateSelectedOptionIndex();
            if (val.trim()) {
              onChange(null, val.trim());
            }
          }}
          onClick={() => combobox.openDropdown()}
          onFocus={() => combobox.openDropdown()}
          onBlur={() => combobox.closeDropdown()}
        />
      </Combobox.Target>
      <Combobox.Dropdown>
        <Combobox.Options mah={200} style={{ overflowY: 'auto' }}>
          {options.length > 0 ? options : <Combobox.Empty>No match — using as custom item</Combobox.Empty>}
        </Combobox.Options>
      </Combobox.Dropdown>
    </Combobox>
  );
}

export default function DocumentForm({ clients, productServices, type, onSubmit, loading, initialValues }: Props) {
  const form = useForm({
    initialValues: initialValues || {
      client_id: '',
      date: new Date(),
      due_date: null as Date | null,
      notes: '',
      items: [{ ...emptyItem }],
    },
  });

  const handleItemChange = (index: number, productServiceId: string | null, customName: string | null) => {
    if (productServiceId) {
      const selected = productServices.find(ps => ps.id === productServiceId);
      if (selected) {
        form.setFieldValue(`items.${index}.product_service_id`, productServiceId);
        form.setFieldValue(`items.${index}.price`, parseFloat(selected.price));
        form.setFieldValue(`items.${index}.tax_percent`, parseFloat(selected.tax_percent));
        form.setFieldValue(`items.${index}.item_type`, selected.type);
        form.setFieldValue(`items.${index}.description`, selected.name);
        form.setFieldValue(`items.${index}.unit`, selected.unit);
      }
    } else if (customName) {
      form.setFieldValue(`items.${index}.product_service_id`, '');
      form.setFieldValue(`items.${index}.description`, customName);
    }
  };

  const addItem = () => {
    form.insertListItem('items', { ...emptyItem });
  };

  const calcLineDiscount = (item: any) => {
    const base = item.quantity * item.price;
    return Math.min(item.discount_value || 0, base);
  };

  const calcLineTotal = (item: any) => {
    const base = item.quantity * item.price;
    const discounted = base - calcLineDiscount(item);
    const tax = discounted * ((item.tax_percent || 0) / 100);
    return discounted + tax;
  };

  const subtotal = form.values.items.reduce((sum: number, item: any) => sum + item.quantity * item.price, 0);
  const discountTotal = form.values.items.reduce((sum: number, item: any) => sum + calcLineDiscount(item), 0);
  const taxTotal = form.values.items.reduce((sum: number, item: any) => {
    const base = item.quantity * item.price;
    const discounted = base - calcLineDiscount(item);
    return sum + (discounted * ((item.tax_percent || 0) / 100));
  }, 0);
  const grandTotal = subtotal - discountTotal + taxTotal;

  const handleFormSubmit = (values: any) => {
    onSubmit({
      ...values,
      type,
      date: dayjs(values.date).format('YYYY-MM-DD'),
      due_date: values.due_date ? dayjs(values.due_date).format('YYYY-MM-DD') : null,
    });
  };

  return (
    <form onSubmit={form.onSubmit(handleFormSubmit)}>
      <Stack>
        <Select
          label="Client"
          placeholder="Select client"
          data={clients.map(c => ({ value: c.id, label: c.name }))}
          {...form.getInputProps('client_id')}
          searchable
          required
        />

        <Group grow>
          <DateInput label="Date" {...form.getInputProps('date')} required />
          <DateInput label="Due Date" minDate={new Date()} {...form.getInputProps('due_date')} clearable />
        </Group>

        <Text fw={600} mt="md">Line Items</Text>
        <Table>
          <Table.Thead>
            <Table.Tr>
              <Table.Th style={{ minWidth: 300 }}>Product / Service</Table.Th>
              <Table.Th>Type</Table.Th>
              <Table.Th w={80}>Qty</Table.Th>
              <Table.Th w={120}>Price</Table.Th>
              <Table.Th w={120}>Discount</Table.Th>
              <Table.Th w={80}>Tax %</Table.Th>
              <Table.Th w={120}>Total</Table.Th>
              <Table.Th w={40}></Table.Th>
            </Table.Tr>
          </Table.Thead>
          <Table.Tbody>
            {form.values.items.map((item: any, index: number) => (
              <Table.Tr key={index}>
                <Table.Td>
                  <ProductServiceInput
                    productServices={productServices}
                    productServiceId={item.product_service_id || ''}
                    description={item.description || ''}
                    onChange={(id, customName) => handleItemChange(index, id, customName)}
                  />
                </Table.Td>
                <Table.Td>
                  {item.item_type && (
                    <Badge color={item.item_type === 'product' ? 'blue' : 'green'} size="xs">
                      {item.item_type}
                    </Badge>
                  )}
                </Table.Td>
                <Table.Td>
                  <NumberInput min={0.01} size="xs" {...form.getInputProps(`items.${index}.quantity`)} />
                </Table.Td>
                <Table.Td>
                  <NumberInput min={0} size="xs" decimalScale={2} {...form.getInputProps(`items.${index}.price`)} />
                </Table.Td>
                <Table.Td>
                  <NumberInput
                    min={0}
                    size="xs"
                    decimalScale={2}
                    {...form.getInputProps(`items.${index}.discount_value`)}
                  />
                </Table.Td>
                <Table.Td>
                  <NumberInput min={0} max={100} size="xs" {...form.getInputProps(`items.${index}.tax_percent`)} />
                </Table.Td>
                <Table.Td>
                  <Text size="sm" fw={500}>{formatCurrency(calcLineTotal(item))}</Text>
                </Table.Td>
                <Table.Td>
                  {form.values.items.length > 1 && (
                    <ActionIcon color="red" size="sm" onClick={() => form.removeListItem('items', index)}>
                      <IconTrash size={14} />
                    </ActionIcon>
                  )}
                </Table.Td>
              </Table.Tr>
            ))}
          </Table.Tbody>
        </Table>

        <Button variant="light" leftSection={<IconPlus size={16} />} onClick={addItem} size="xs" w="fit-content">
          Add Item
        </Button>

        <Group justify="flex-end" gap="xl">
          <Stack gap={4} align="flex-end">
            <Text size="sm" c="dimmed">Subtotal: {formatCurrency(subtotal)}</Text>
            {discountTotal > 0 && (
              <Text size="sm" c="dimmed">Discount: -{formatCurrency(discountTotal)}</Text>
            )}
            <Text size="sm" c="dimmed">Tax: {formatCurrency(taxTotal)}</Text>
            <Text size="lg" fw={700}>Total: {formatCurrency(grandTotal)}</Text>
          </Stack>
        </Group>

        <Textarea label="Notes" {...form.getInputProps('notes')} />

        <Group justify="flex-end">
          <Button type="submit" loading={loading}>
            Save {type.charAt(0).toUpperCase() + type.slice(1)}
          </Button>
        </Group>
      </Stack>
    </form>
  );
}
