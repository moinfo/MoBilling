import { Button, Group, NumberInput, Select, Stack, TextInput, Textarea, Anchor, Text, FileInput, Checkbox, Divider, Alert } from '@mantine/core';
import { DateInput } from '@mantine/dates';
import { useForm } from '@mantine/form';
import { IconUpload, IconCash } from '@tabler/icons-react';
import { usePaymentMethods } from '../../hooks/usePaymentMethods';
import dayjs from 'dayjs';
import { Expense } from '../../api/expenses';
import { ExpenseCategory } from '../../api/expenseCategories';

interface Props {
  expense?: Expense | null;
  categories: ExpenseCategory[];
  onSubmit: (values: any) => void;
  loading?: boolean;
  // Parent passes the tenant's petty cash account id (once fetched).
  // When null, the "Paid from petty cash" toggle is hidden.
  pettyCashAccountId?: string | null;
}

export default function ExpenseForm({ expense, categories, onSubmit, loading, pettyCashAccountId }: Props) {
  const { methods: paymentMethods } = usePaymentMethods();
  const form = useForm({
    initialValues: {
      description: expense?.description || '',
      sub_expense_category_id: expense?.sub_expense_category_id || '',
      amount: expense ? parseFloat(expense.amount) : 0,
      expense_date: expense ? new Date(expense.expense_date) : new Date(),
      payment_method: expense?.payment_method || 'cash',
      control_number: expense?.control_number || '',
      reference: expense?.reference || '',
      notes: expense?.notes || '',
      attachment: null as File | null,
      paid_from_petty_cash: !!expense?.petty_cash_account_id,
      given_by_name: expense?.given_by_name || '',
      received_by_name: expense?.received_by_name || '',
    },
  });

  // Build grouped select data: parent category as group, sub-categories as items
  const categorySelectData = categories
    .filter((cat) => cat.is_active && cat.sub_categories?.length > 0)
    .map((cat) => ({
      group: cat.name,
      items: cat.sub_categories
        .filter((sub) => sub.is_active)
        .map((sub) => ({
          value: sub.id,
          label: sub.name,
        })),
    }));

  const handleSubmit = (values: typeof form.values) => {
    onSubmit({
      ...values,
      sub_expense_category_id: values.sub_expense_category_id || null,
      expense_date: dayjs(values.expense_date).format('YYYY-MM-DD'),
      // Only attach the petty cash linkage if the user toggled it on AND
      // the parent provided an account id. Otherwise leave it null.
      petty_cash_account_id: values.paid_from_petty_cash && pettyCashAccountId ? pettyCashAccountId : null,
      given_by_name: values.paid_from_petty_cash ? values.given_by_name : undefined,
      received_by_name: values.paid_from_petty_cash ? values.received_by_name : undefined,
    });
  };

  return (
    <form onSubmit={form.onSubmit(handleSubmit)}>
      <Stack>
        <TextInput label="Description" required placeholder="What is this expense for?" {...form.getInputProps('description')} />

        <Select
          label="Sub Category"
          placeholder="Select category"
          data={categorySelectData}
          searchable
          clearable
          {...form.getInputProps('sub_expense_category_id')}
        />

        <Group grow>
          <NumberInput label="Amount" required min={0.01} decimalScale={2} {...form.getInputProps('amount')} />
          <DateInput label="Expense Date" required {...form.getInputProps('expense_date')} />
        </Group>

        <Group grow>
          <Select
            label="Payment Method"
            required
            data={paymentMethods}
            {...form.getInputProps('payment_method')}
          />
          <TextInput label="Control Number" placeholder="e.g., 991234567890" {...form.getInputProps('control_number')} />
        </Group>

        <TextInput label="Reference" placeholder="Receipt no, transaction ref, etc." {...form.getInputProps('reference')} />
        <Textarea label="Notes" {...form.getInputProps('notes')} />

        <FileInput
          label="Attachment (receipt)"
          placeholder="Upload receipt or document"
          leftSection={<IconUpload size={16} />}
          accept="image/*,.pdf,.doc,.docx,.xls,.xlsx"
          {...form.getInputProps('attachment')}
        />
        {expense?.attachment_url && !form.values.attachment && (
          <Text size="sm">
            Current file:{' '}
            <Anchor href={expense.attachment_url} target="_blank" size="sm">
              View attachment
            </Anchor>
          </Text>
        )}

        {pettyCashAccountId && (
          <>
            <Divider my="xs" />
            <Checkbox
              label={<Group gap="xs"><IconCash size={14} /> <span>Paid from petty cash</span></Group>}
              {...form.getInputProps('paid_from_petty_cash', { type: 'checkbox' })}
            />
            {form.values.paid_from_petty_cash && (
              <Stack gap="xs">
                <Group grow>
                  <TextInput label="Given by" placeholder="Name of giver / custodian" {...form.getInputProps('given_by_name')} />
                  <TextInput label="Received by" placeholder="Name of receiver / vendor" {...form.getInputProps('received_by_name')} />
                </Group>
                <Alert color="blue" variant="light">
                  After saving, you'll be able to download a printable voucher PDF for both parties to sign, then upload the scanned copy back.
                </Alert>
                {expense?.voucher_attachment_url && (
                  <Text size="sm">
                    Signed voucher on file:{' '}
                    <Anchor href={expense.voucher_attachment_url} target="_blank" size="sm">
                      View signed voucher
                    </Anchor>
                  </Text>
                )}
              </Stack>
            )}
          </>
        )}

        <Group justify="flex-end">
          <Button type="submit" loading={loading}>
            {expense ? 'Update Expense' : 'Create Expense'}
          </Button>
        </Group>
      </Stack>
    </form>
  );
}
