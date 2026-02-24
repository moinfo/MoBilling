import { useState } from 'react';
import { NumberInput, Select, TextInput, Textarea, Button, Group, Stack, FileInput } from '@mantine/core';
import { DateInput } from '@mantine/dates';
import { useForm } from '@mantine/form';
import { IconUpload } from '@tabler/icons-react';
import dayjs from 'dayjs';

interface Props {
  billAmount: number;
  paidAmount?: number;
  onSubmit: (values: any) => void;
  onCancel: () => void;
  loading?: boolean;
}

export default function PaymentOutForm({ billAmount, paidAmount = 0, onSubmit, onCancel, loading }: Props) {
  const [receipt, setReceipt] = useState<File | null>(null);
  const remaining = Math.max(0, billAmount - paidAmount);

  const form = useForm({
    initialValues: {
      amount: remaining,
      payment_date: new Date(),
      payment_method: 'bank',
      control_number: '',
      reference: '',
      notes: '',
    },
    validate: {
      amount: (v: number) => {
        if (v <= 0) return 'Amount must be positive';
        if (v > remaining) return `Cannot exceed remaining balance (${remaining.toLocaleString()})`;
        return null;
      },
    },
  });

  const handleSubmit = (values: any) => {
    onSubmit({
      ...values,
      payment_date: dayjs(values.payment_date).format('YYYY-MM-DD'),
      receipt,
    });
  };

  return (
    <form onSubmit={form.onSubmit(handleSubmit)}>
      <Stack>
        <Group grow>
          <NumberInput
            label="Amount"
            description={paidAmount > 0 ? `Remaining: ${remaining.toLocaleString()} of ${billAmount.toLocaleString()}` : undefined}
            min={0.01}
            max={remaining}
            decimalScale={2}
            required
            {...form.getInputProps('amount')}
          />
          <DateInput label="Payment Date" required {...form.getInputProps('payment_date')} />
        </Group>
        <Group grow>
          <Select label="Method" data={[
            { value: 'bank', label: 'Bank Transfer' },
            { value: 'mpesa', label: 'M-Pesa' },
            { value: 'cash', label: 'Cash' },
            { value: 'card', label: 'Card' },
            { value: 'other', label: 'Other' },
          ]} {...form.getInputProps('payment_method')} />
          <TextInput label="Control Number" placeholder="e.g., 991234567890" {...form.getInputProps('control_number')} />
        </Group>
        <TextInput label="Reference" placeholder="Transaction ref" {...form.getInputProps('reference')} />
        <FileInput
          label="Receipt Attachment"
          placeholder="Upload receipt (PDF, JPG, PNG)"
          accept="application/pdf,image/jpeg,image/png"
          leftSection={<IconUpload size={16} />}
          clearable
          value={receipt}
          onChange={setReceipt}
        />
        <Textarea label="Notes" {...form.getInputProps('notes')} />
        <Group justify="flex-end">
          <Button variant="light" onClick={onCancel}>Cancel</Button>
          <Button type="submit" color="green" loading={loading}>Record Payment</Button>
        </Group>
      </Stack>
    </form>
  );
}
