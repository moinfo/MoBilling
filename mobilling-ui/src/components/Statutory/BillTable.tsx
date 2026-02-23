import { Table, Badge, ActionIcon, Group, Text } from '@mantine/core';
import { IconEdit, IconTrash, IconCash } from '@tabler/icons-react';
import { Bill } from '../../api/bills';
import { formatCurrency } from '../../utils/formatCurrency';
import { formatDate } from '../../utils/formatDate';

interface Props {
  bills: Bill[];
  onEdit: (bill: Bill) => void;
  onDelete: (bill: Bill) => void;
  onMarkPaid: (bill: Bill) => void;
}

export default function BillTable({ bills, onEdit, onDelete, onMarkPaid }: Props) {
  if (bills.length === 0) {
    return <Text c="dimmed" ta="center" py="xl">No bills found</Text>;
  }

  const getDueStatus = (bill: Bill) => {
    if (bill.is_overdue) return { color: 'red', label: 'Overdue' };
    const daysUntil = Math.ceil((new Date(bill.due_date).getTime() - Date.now()) / 86400000);
    if (daysUntil <= bill.remind_days_before) return { color: 'orange', label: 'Due Soon' };
    return { color: 'green', label: 'Upcoming' };
  };

  return (
    <Table striped highlightOnHover>
      <Table.Thead>
        <Table.Tr>
          <Table.Th>Name</Table.Th>
          <Table.Th>Category</Table.Th>
          <Table.Th>Amount</Table.Th>
          <Table.Th>Cycle</Table.Th>
          <Table.Th>Due Date</Table.Th>
          <Table.Th>Status</Table.Th>
          <Table.Th w={120}>Actions</Table.Th>
        </Table.Tr>
      </Table.Thead>
      <Table.Tbody>
        {bills.map((bill) => {
          const status = getDueStatus(bill);
          return (
            <Table.Tr key={bill.id}>
              <Table.Td fw={500}>{bill.name}</Table.Td>
              <Table.Td>{bill.category}</Table.Td>
              <Table.Td>{formatCurrency(bill.amount)}</Table.Td>
              <Table.Td>{bill.cycle.replace('_', ' ')}</Table.Td>
              <Table.Td>{formatDate(bill.due_date)}</Table.Td>
              <Table.Td>
                <Badge color={status.color} size="sm">{status.label}</Badge>
              </Table.Td>
              <Table.Td>
                <Group gap="xs">
                  <ActionIcon variant="light" color="green" onClick={() => onMarkPaid(bill)} title="Mark Paid">
                    <IconCash size={16} />
                  </ActionIcon>
                  <ActionIcon variant="light" onClick={() => onEdit(bill)}>
                    <IconEdit size={16} />
                  </ActionIcon>
                  <ActionIcon variant="light" color="red" onClick={() => onDelete(bill)}>
                    <IconTrash size={16} />
                  </ActionIcon>
                </Group>
              </Table.Td>
            </Table.Tr>
          );
        })}
      </Table.Tbody>
    </Table>
  );
}
