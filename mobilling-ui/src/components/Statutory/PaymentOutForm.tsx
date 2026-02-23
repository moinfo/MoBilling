import { NumberInput, Select, TextInput, Textarea, Button, Group, Stack } from '@mantine/core';
import { DateInput } from '@mantine/dates';
import { useForm } from '@mantine/form';
import dayjs from 'dayjs';

interface Props {
  billAmount: number;
  onSubmit: (values: any) => void;
  onCancel: () => void;
  loading?: boolean;
}

export default function PaymentOutForm({ billAmount, onSubmit, onCancel, loading }: Props) {
  const form = useForm({
    initialValues: {
      amount: billAmount,
      payment_date: new Date(),
      payment_method: 'bank',
      reference: '',
      notes: '',
    },
  });

  const handleSubmit = (values: any) => {
    onSubmit({
      ...values,
      payment_date: dayjs(values.payment_date).format('YYYY-MM-DD'),
    });
  };

  return (
    <form onSubmit={form.onSubmit(handleSubmit)}>
      <Stack>
        <Group grow>
          <NumberInput label="Amount" min={0.01} decimalScale={2} required {...form.getInputProps('amount')} />
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
          <TextInput label="Reference" placeholder="Transaction ref" {...form.getInputProps('reference')} />
        </Group>
        <Textarea label="Notes" {...form.getInputProps('notes')} />
        <Group justify="flex-end">
          <Button variant="light" onClick={onCancel}>Cancel</Button>
          <Button type="submit" color="green" loading={loading}>Record Payment</Button>
        </Group>
      </Stack>
    </form>
  );
}
