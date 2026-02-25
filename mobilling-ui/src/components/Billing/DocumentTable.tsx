import { Table, Badge, ActionIcon, Text, Menu } from '@mantine/core';
import { IconEye, IconEdit, IconTrash, IconDots } from '@tabler/icons-react';
import { Document } from '../../api/documents';
import { formatCurrency } from '../../utils/formatCurrency';
import { formatDate } from '../../utils/formatDate';

interface Props {
  documents: Document[];
  onView: (doc: Document) => void;
  onEdit: (doc: Document) => void;
  onDelete: (doc: Document) => void;
}

const statusColors: Record<string, string> = {
  draft: 'gray',
  sent: 'blue',
  accepted: 'teal',
  rejected: 'red',
  paid: 'green',
  overdue: 'orange',
  partial: 'yellow',
};

export default function DocumentTable({ documents, onView, onEdit, onDelete }: Props) {
  if (documents.length === 0) {
    return <Text c="dimmed" ta="center" py="xl">No documents found</Text>;
  }

  return (
    <Table.ScrollContainer minWidth={650}>
      <Table striped highlightOnHover>
        <Table.Thead>
          <Table.Tr>
            <Table.Th>Number</Table.Th>
            <Table.Th>Client</Table.Th>
            <Table.Th>Date</Table.Th>
            <Table.Th>Total</Table.Th>
            <Table.Th>Status</Table.Th>
            <Table.Th w={80}>Actions</Table.Th>
          </Table.Tr>
        </Table.Thead>
      <Table.Tbody>
        {documents.map((doc) => (
          <Table.Tr key={doc.id} style={{ cursor: 'pointer' }} onClick={() => onView(doc)}>
            <Table.Td fw={500}>{doc.document_number}</Table.Td>
            <Table.Td>{doc.client?.name || '—'}</Table.Td>
            <Table.Td>{formatDate(doc.date)}</Table.Td>
            <Table.Td>{formatCurrency(doc.total)}</Table.Td>
            <Table.Td>
              <Badge color={statusColors[doc.status] || 'gray'} size="sm">
                {doc.status}
              </Badge>
            </Table.Td>
            <Table.Td onClick={(e) => e.stopPropagation()}>
              <Menu shadow="md" width={160}>
                <Menu.Target>
                  <ActionIcon variant="light"><IconDots size={16} /></ActionIcon>
                </Menu.Target>
                <Menu.Dropdown>
                  <Menu.Item leftSection={<IconEye size={14} />} onClick={() => onView(doc)}>View</Menu.Item>
                  <Menu.Item leftSection={<IconEdit size={14} />} onClick={() => onEdit(doc)}>Edit</Menu.Item>
                  <Menu.Item leftSection={<IconTrash size={14} />} color="red" onClick={() => onDelete(doc)}>Delete</Menu.Item>
                </Menu.Dropdown>
              </Menu>
            </Table.Td>
          </Table.Tr>
        ))}
      </Table.Tbody>
      </Table>
    </Table.ScrollContainer>
  );
}
