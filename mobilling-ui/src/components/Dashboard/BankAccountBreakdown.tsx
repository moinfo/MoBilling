import { Card, Text, Group, Stack, Divider, Box } from '@mantine/core';
import { IconBuildingBank } from '@tabler/icons-react';
import { formatCurrency } from '../../utils/formatCurrency';
import type { SystemRecordBankTotal } from '../../api/dashboard';

export default function BankAccountBreakdown({
  data,
  total,
  periodLabel,
}: {
  data: SystemRecordBankTotal[];
  total: number;
  periodLabel: string;
}) {
  const hasData = data.length > 0;

  return (
    <Card withBorder padding="lg">
      <Group justify="space-between" align="flex-start" mb="md">
        <Group gap="xs">
          <IconBuildingBank size={20} />
          <Box>
            <Text fw={600}>By Bank Account</Text>
            <Text size="xs" c="dimmed">{periodLabel}</Text>
          </Box>
        </Group>
        <Box ta="right">
          <Text size="xs" c="dimmed" tt="uppercase" fw={600} style={{ letterSpacing: 0.5 }}>
            Total
          </Text>
          <Text fw={700} size="xl" c="violet.7">
            {formatCurrency(total)}
          </Text>
        </Box>
      </Group>

      <Divider mb="md" />

      {!hasData ? (
        <Text c="dimmed" size="sm">No system records recorded this month.</Text>
      ) : (
        <Stack gap="xs">
          {data.map((row) => {
            const isUntagged = row.bank_account_id === null;
            return (
              <Group key={row.bank_account_id ?? 'untagged'} justify="space-between" wrap="nowrap">
                <Box style={{ minWidth: 0 }}>
                  <Text size="sm" fw={500} truncate>
                    {row.bank_name}
                  </Text>
                  {row.account_number && (
                    <Text size="xs" c="dimmed">{row.account_number}</Text>
                  )}
                  {isUntagged && (
                    <Text size="xs" c="dimmed" fs="italic">
                      Records not assigned to a bank account
                    </Text>
                  )}
                </Box>
                <Text fw={700} size="sm" c={isUntagged ? 'gray.7' : undefined}>
                  {formatCurrency(row.total)}
                </Text>
              </Group>
            );
          })}
        </Stack>
      )}
    </Card>
  );
}
