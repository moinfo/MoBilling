import { Modal, Table, Group, Text, Badge } from '@mantine/core';
import dayjs from 'dayjs';
import type { StaffPenaltiesSummary } from '../../api/dashboard';
import { formatCurrency } from '../../utils/formatCurrency';

const typeLabel = (penalty: string, report: string) =>
  `${penalty === 'late' ? 'Late' : 'Missing'} ${report} report`;

/**
 * The itemised list behind the running report-deduction figure in MyMonth.
 *
 * This is all that survives of the old "My Report Deductions" dashboard card:
 * the card's headline number duplicated the attendance+reports total sitting
 * next to it, so only the detail — which report, which day, how much — was
 * worth keeping, and it belongs behind a click rather than on the dashboard.
 */
export default function ReportDeductionsModal(
  { data, opened, onClose }: { data: StaffPenaltiesSummary; opened: boolean; onClose: () => void },
) {
  return (
    <Modal opened={opened} onClose={onClose} size="lg"
      title={`Report deductions · ${data.month_label}`}>
      <Table.ScrollContainer minWidth={420}>
        <Table verticalSpacing={6} highlightOnHover>
          <Table.Thead>
            <Table.Tr>
              <Table.Th>Date</Table.Th>
              <Table.Th>Reason</Table.Th>
              <Table.Th ta="right">Amount</Table.Th>
            </Table.Tr>
          </Table.Thead>
          <Table.Tbody>
            {data.items.map((p) => (
              <Table.Tr key={p.id}>
                <Table.Td>{dayjs(p.period_date).format('D MMM YYYY')}</Table.Td>
                <Table.Td>
                  <Group gap={6} wrap="nowrap">
                    <Badge size="xs" variant="light" color={p.penalty_type === 'late' ? 'orange' : 'red'}>
                      {p.penalty_type}
                    </Badge>
                    <Text size="sm">{p.notes ?? typeLabel(p.penalty_type, p.report_type)}</Text>
                  </Group>
                </Table.Td>
                <Table.Td ta="right" fw={600} c="red">−{formatCurrency(p.amount)}</Table.Td>
              </Table.Tr>
            ))}
          </Table.Tbody>
        </Table>
      </Table.ScrollContainer>
    </Modal>
  );
}
