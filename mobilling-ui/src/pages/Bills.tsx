import { useState } from 'react';
import { Title, Group, Button, TextInput, Modal, Pagination } from '@mantine/core';
import { useDebouncedValue } from '@mantine/hooks';
import { modals } from '@mantine/modals';
import { notifications } from '@mantine/notifications';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { IconPlus, IconSearch } from '@tabler/icons-react';
import { getBills, createBill, updateBill, deleteBill, createPaymentOut, Bill, BillFormData } from '../api/bills';
import BillTable from '../components/Statutory/BillTable';
import BillForm from '../components/Statutory/BillForm';
import PaymentOutForm from '../components/Statutory/PaymentOutForm';

export default function Bills() {
  const queryClient = useQueryClient();
  const [search, setSearch] = useState('');
  const [debouncedSearch] = useDebouncedValue(search, 300);
  const [page, setPage] = useState(1);
  const [formOpen, setFormOpen] = useState(false);
  const [editing, setEditing] = useState<Bill | null>(null);
  const [payingBill, setPayingBill] = useState<Bill | null>(null);

  const { data } = useQuery({
    queryKey: ['bills', debouncedSearch, page],
    queryFn: () => getBills({ search: debouncedSearch || undefined, page }),
  });

  const bills = data?.data?.data || [];
  const meta = data?.data?.meta;

  const createMutation = useMutation({
    mutationFn: (values: BillFormData) => createBill(values),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['bills'] });
      setFormOpen(false);
      notifications.show({ title: 'Success', message: 'Bill created', color: 'green' });
    },
    onError: () => notifications.show({ title: 'Error', message: 'Failed to create bill', color: 'red' }),
  });

  const updateMutation = useMutation({
    mutationFn: (values: BillFormData) => updateBill(editing!.id, values),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['bills'] });
      setFormOpen(false);
      setEditing(null);
      notifications.show({ title: 'Success', message: 'Bill updated', color: 'green' });
    },
    onError: () => notifications.show({ title: 'Error', message: 'Failed to update bill', color: 'red' }),
  });

  const deleteMutation = useMutation({
    mutationFn: (id: string) => deleteBill(id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['bills'] });
      notifications.show({ title: 'Success', message: 'Bill deleted', color: 'green' });
    },
  });

  const payMutation = useMutation({
    mutationFn: (values: any) => createPaymentOut(values),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['bills'] });
      queryClient.invalidateQueries({ queryKey: ['payments-out'] });
      setPayingBill(null);
      notifications.show({ title: 'Success', message: 'Payment recorded', color: 'green' });
    },
    onError: () => notifications.show({ title: 'Error', message: 'Payment failed', color: 'red' }),
  });

  const handleEdit = (bill: Bill) => {
    setEditing(bill);
    setFormOpen(true);
  };

  const handleDelete = (bill: Bill) => {
    modals.openConfirmModal({
      title: 'Delete Bill',
      children: `Delete "${bill.name}"?`,
      labels: { confirm: 'Delete', cancel: 'Cancel' },
      confirmProps: { color: 'red' },
      onConfirm: () => deleteMutation.mutate(bill.id),
    });
  };

  const handleSubmit = (values: BillFormData) => {
    if (editing) updateMutation.mutate(values);
    else createMutation.mutate(values);
  };

  return (
    <>
      <Group justify="space-between" mb="md" wrap="wrap">
        <Title order={2}>Bills</Title>
        <Button leftSection={<IconPlus size={16} />} onClick={() => { setEditing(null); setFormOpen(true); }}>
          Add Bill
        </Button>
      </Group>

      <TextInput
        placeholder="Search bills..."
        leftSection={<IconSearch size={16} />}
        value={search}
        onChange={(e) => { setSearch(e.currentTarget.value); setPage(1); }}
        mb="md"
        maw={300}
      />

      <BillTable
        bills={bills}
        onEdit={handleEdit}
        onDelete={handleDelete}
        onMarkPaid={(bill) => setPayingBill(bill)}
      />

      {meta && meta.last_page > 1 && (
        <Group justify="center" mt="md">
          <Pagination total={meta.last_page} value={page} onChange={setPage} />
        </Group>
      )}

      {/* Bill Create/Edit Modal */}
      <Modal
        opened={formOpen}
        onClose={() => { setFormOpen(false); setEditing(null); }}
        title={editing ? 'Edit Bill' : 'New Bill'}
        size="lg"
      >
        <BillForm
          initialValues={editing ? {
            name: editing.name,
            bill_category_id: editing.bill_category_id || null,
            issue_date: editing.issue_date ? new Date(editing.issue_date) : null,
            amount: parseFloat(editing.amount),
            cycle: editing.cycle,
            due_date: new Date(editing.due_date),
            remind_days_before: editing.remind_days_before,
            is_active: editing.is_active,
            notes: editing.notes || '',
          } : undefined}
          onSubmit={handleSubmit}
          loading={createMutation.isPending || updateMutation.isPending}
        />
      </Modal>

      {/* Payment Modal */}
      <Modal
        opened={!!payingBill}
        onClose={() => setPayingBill(null)}
        title={`Mark "${payingBill?.name}" as Paid`}
      >
        {payingBill && (
          <PaymentOutForm
            billAmount={parseFloat(payingBill.amount)}
            paidAmount={payingBill.payments?.reduce((sum, p) => sum + parseFloat(p.amount), 0) || 0}
            onCancel={() => setPayingBill(null)}
            onSubmit={(values) => payMutation.mutate({ ...values, bill_id: payingBill.id })}
            loading={payMutation.isPending}
          />
        )}
      </Modal>
    </>
  );
}
