import { Table, Badge, ActionIcon, Text, Menu, Group, Tooltip, Loader, Center } from '@mantine/core';
import { IconEye, IconEdit, IconTrash, IconDots, IconBell, IconX, IconRefresh } from '@tabler/icons-react';
import { Document } from '../../api/documents';
import { formatCurrency } from '../../utils/formatCurrency';
import { formatDate } from '../../utils/formatDate';
import { usePermissions } from '../../hooks/usePermissions';

interface Props {
  documents: Document[];
  onView: (doc: Document) => void;
  onEdit: (doc: Document) => void;
  onDelete: (doc: Document) => void;
  onRemind?: (doc: Document) => void;
  onCancel?: (doc: Document) => void;
  onUncancel?: (doc: Document) => void;
  startIndex?: number;
  loading?: boolean;
}

const statusColors: Record<string, string> = {
  draft: 'gray',
  sent: 'blue',
  accepted: 'teal',
  rejected: 'red',
  paid: 'green',
  overdue: 'orange',
  partial: 'yellow',
  cancelled: 'red',
};

const stageLabels: Record<string, string> = {
  late_fee_applied: 'Late fee added',
  reminder_7d: '7-day reminder sent',
  termination_warning: 'Termination warning sent',
};

export default function DocumentTable({ documents, onView, onEdit, onDelete, onRemind, onCancel, onUncancel, startIndex = 1, loading }: Props) {
  const { can } = usePermissions();
  if (loading) {
    return <Center py="xl"><Loader /></Center>;
  }
  if (documents.length === 0) {
    return <Text c="dimmed" ta="center" py="xl">No documents found</Text>;
  }

  return (
    <Table.ScrollContainer minWidth={650}>
      <Table striped highlightOnHover>
        <Table.Thead>
          <Table.Tr>
            <Table.Th w={50}>#</Table.Th>
            <Table.Th>Number</Table.Th>
            <Table.Th>Client</Table.Th>
            <Table.Th>Date</Table.Th>
            <Table.Th>Total</Table.Th>
            <Table.Th>Status</Table.Th>
            <Table.Th w={80}>Actions</Table.Th>
          </Table.Tr>
        </Table.Thead>
      <Table.Tbody>
        {documents.map((doc, index) => {
          const isCancelled = doc.status === 'cancelled';
          const isUnpaid = !isCancelled && doc.status !== 'paid' && doc.status !== 'draft';
          return (
            <Table.Tr key={doc.id} style={{ cursor: 'pointer', opacity: isCancelled ? 0.5 : 1 }} onClick={() => onView(doc)}>
              <Table.Td><Text size="sm" c="dimmed">{startIndex + index}</Text></Table.Td>
              <Table.Td fw={500} td={isCancelled ? 'line-through' : undefined}>{doc.document_number}</Table.Td>
              <Table.Td td={isCancelled ? 'line-through' : undefined}>{doc.client?.name || '—'}</Table.Td>
              <Table.Td>{formatDate(doc.date)}</Table.Td>
              <Table.Td td={isCancelled ? 'line-through' : undefined}>{formatCurrency(doc.total)}</Table.Td>
              <Table.Td>
                <Group gap={6}>
                  <Badge color={statusColors[doc.status] || 'gray'} size="sm">
                    {doc.status}
                  </Badge>
                  {doc.reminder_count > 0 && (
                    <Tooltip label={doc.overdue_stage ? stageLabels[doc.overdue_stage] || doc.overdue_stage : `${doc.reminder_count} reminder(s) sent`}>
                      <Badge variant="light" color="orange" size="sm" leftSection={<IconBell size={10} />}>
                        {doc.reminder_count}
                      </Badge>
                    </Tooltip>
                  )}
                </Group>
              </Table.Td>
              <Table.Td onClick={(e) => e.stopPropagation()}>
                <Menu shadow="md" width={180}>
                  <Menu.Target>
                    <ActionIcon variant="light"><IconDots size={16} /></ActionIcon>
                  </Menu.Target>
                  <Menu.Dropdown>
                    <Menu.Item leftSection={<IconEye size={14} />} onClick={() => onView(doc)}>View</Menu.Item>
                    {can('documents.update') && (
                      <Menu.Item leftSection={<IconEdit size={14} />} onClick={() => onEdit(doc)}>Edit</Menu.Item>
                    )}
                    {can('documents.send') && onRemind && isUnpaid && (
                      <Menu.Item
                        leftSection={<IconBell size={14} />}
                        color="orange"
                        onClick={() => onRemind(doc)}
                      >
                        Send Reminder
                      </Menu.Item>
                    )}
                    {can('documents.update') && onCancel && isUnpaid && (
                      <Menu.Item
                        leftSection={<IconX size={14} />}
                        color="red"
                        onClick={() => onCancel(doc)}
                      >
                        Cancel
                      </Menu.Item>
                    )}
                    {can('documents.update') && onUncancel && isCancelled && (
                      <Menu.Item
                        leftSection={<IconRefresh size={14} />}
                        color="green"
                        onClick={() => onUncancel(doc)}
                      >
                        Restore
                      </Menu.Item>
                    )}
                    {can('documents.delete') && (
                      <Menu.Item leftSection={<IconTrash size={14} />} color="red" onClick={() => onDelete(doc)}>Delete</Menu.Item>
                    )}
                  </Menu.Dropdown>
                </Menu>
              </Table.Td>
            </Table.Tr>
          );
        })}
      </Table.Tbody>
      </Table>
    </Table.ScrollContainer>
  );
}
