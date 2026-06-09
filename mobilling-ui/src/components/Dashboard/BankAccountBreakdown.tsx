import { Card, Text, Group, Stack, Divider, Box, ThemeIcon, Progress, Avatar, Tooltip } from '@mantine/core';
import { IconBuildingBank, IconAlertCircle } from '@tabler/icons-react';
import { formatCurrency } from '../../utils/formatCurrency';
import type { SystemRecordBankTotal } from '../../api/dashboard';

// Take initials from the bank name for the avatar, max 2 chars.
const initials = (name: string) =>
  name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((w) => w[0])
    .join('')
    .toUpperCase() || '—';

// Deterministic-ish color per bank so the same bank picks the same color
// every render. Hash the name → pick from a fixed palette.
const palette = ['violet', 'grape', 'indigo', 'cyan', 'teal', 'green', 'orange', 'pink'];
const colorFor = (name: string) => {
  let h = 0;
  for (let i = 0; i < name.length; i++) h = (h * 31 + name.charCodeAt(i)) | 0;
  return palette[Math.abs(h) % palette.length];
};

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
    <Card withBorder padding="lg" radius="md">
      {/* Header */}
      <Group justify="space-between" align="flex-start" mb="lg">
        <Group gap="sm">
          <ThemeIcon size="xl" variant="light" color="violet" radius="md">
            <IconBuildingBank size={22} />
          </ThemeIcon>
          <Box>
            <Text fw={700} size="md">By Bank Account</Text>
            <Text size="xs" c="dimmed" tt="uppercase" fw={500} style={{ letterSpacing: 0.5 }}>
              {periodLabel}
            </Text>
          </Box>
        </Group>
        <Box ta="right">
          <Text size="xs" c="dimmed" tt="uppercase" fw={700} style={{ letterSpacing: 0.8 }}>
            Total
          </Text>
          <Text fw={800} size="22px" c="violet.7" lh={1.2}>
            {formatCurrency(total)}
          </Text>
        </Box>
      </Group>

      <Divider mb="lg" />

      {/* Content */}
      {!hasData ? (
        <Box ta="center" py="xl">
          <ThemeIcon size="xl" variant="light" color="gray" radius="xl" mb="sm">
            <IconBuildingBank size={22} />
          </ThemeIcon>
          <Text c="dimmed" size="sm">No system records recorded this month.</Text>
        </Box>
      ) : (
        <Stack gap="md">
          {data.map((row) => {
            const isUntagged = row.bank_account_id === null;
            const pct = total > 0 ? (row.total / total) * 100 : 0;
            const color = isUntagged ? 'yellow' : colorFor(row.bank_name);

            return (
              <Box key={row.bank_account_id ?? 'untagged'}>
                <Group justify="space-between" mb={6} wrap="nowrap">
                  <Group gap="sm" wrap="nowrap" style={{ minWidth: 0 }}>
                    {isUntagged ? (
                      <Tooltip label="Records with no bank account assigned">
                        <ThemeIcon size="md" variant="light" color="yellow" radius="xl">
                          <IconAlertCircle size={16} />
                        </ThemeIcon>
                      </Tooltip>
                    ) : (
                      <Avatar size="md" color={color} radius="xl">
                        {initials(row.bank_name)}
                      </Avatar>
                    )}
                    <Box style={{ minWidth: 0 }}>
                      <Text size="sm" fw={600} truncate c={isUntagged ? 'yellow.8' : undefined}>
                        {row.bank_name}
                      </Text>
                      {row.account_number ? (
                        <Text size="xs" c="dimmed" ff="monospace">{row.account_number}</Text>
                      ) : (
                        isUntagged && (
                          <Text size="xs" c="dimmed" fs="italic">Cash or unspecified channel</Text>
                        )
                      )}
                    </Box>
                  </Group>
                  <Box ta="right" style={{ whiteSpace: 'nowrap' }}>
                    <Text fw={700} size="sm" c={isUntagged ? 'yellow.8' : undefined}>
                      {formatCurrency(row.total)}
                    </Text>
                    <Text size="xs" c="dimmed">{pct.toFixed(1)}%</Text>
                  </Box>
                </Group>
                <Progress value={pct} size="xs" color={color} radius="xl" />
              </Box>
            );
          })}
        </Stack>
      )}
    </Card>
  );
}
