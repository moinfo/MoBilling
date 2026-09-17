import { Card, Text, Group, Stack, Divider, Box, ThemeIcon, Avatar } from '@mantine/core';
import { IconWallet } from '@tabler/icons-react';
import { formatCurrency } from '../../utils/formatCurrency';
import type { BankAccountBalance } from '../../api/dashboard';

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

/**
 * Current running balance per bank account — opening_balance plus every
 * deposit, minus every withdraw/charge, through today. Deliberately not
 * `BankAccountBreakdown` (this period's deposits only) — this is "how much
 * is actually in the account right now."
 */
export default function BankBalances({ data }: { data: BankAccountBalance[] }) {
  const hasData = data.length > 0;
  const total = data.reduce((sum, row) => sum + row.balance, 0);

  return (
    <Card withBorder padding="lg" radius="md">
      <Group justify="space-between" align="flex-start" mb="lg">
        <Group gap="sm">
          <ThemeIcon size="xl" variant="light" color="teal" radius="md">
            <IconWallet size={22} />
          </ThemeIcon>
          <Box>
            <Text fw={700} size="md">Bank Balances</Text>
            <Text size="xs" c="dimmed" tt="uppercase" fw={500} style={{ letterSpacing: 0.5 }}>
              As of today
            </Text>
          </Box>
        </Group>
        <Box ta="right">
          <Text size="xs" c="dimmed" tt="uppercase" fw={700} style={{ letterSpacing: 0.8 }}>
            Total
          </Text>
          <Text fw={800} size="22px" c="teal.7" lh={1.2}>
            {formatCurrency(total)}
          </Text>
        </Box>
      </Group>

      <Divider mb="lg" />

      {!hasData ? (
        <Box ta="center" py="xl">
          <ThemeIcon size="xl" variant="light" color="gray" radius="xl" mb="sm">
            <IconWallet size={22} />
          </ThemeIcon>
          <Text c="dimmed" size="sm">No active bank accounts yet.</Text>
        </Box>
      ) : (
        <Stack gap="md">
          {data.map((row) => {
            const color = colorFor(row.bank_name);
            return (
              <Group key={row.id} justify="space-between" wrap="nowrap">
                <Group gap="sm" wrap="nowrap" style={{ minWidth: 0 }}>
                  <Avatar size="md" color={color} radius="xl">
                    {initials(row.bank_name)}
                  </Avatar>
                  <Box style={{ minWidth: 0 }}>
                    <Text size="sm" fw={600} truncate>{row.bank_name}</Text>
                    {row.account_number && (
                      <Text size="xs" c="dimmed" ff="monospace">{row.account_number}</Text>
                    )}
                  </Box>
                </Group>
                <Text fw={700} size="sm" style={{ whiteSpace: 'nowrap' }}>
                  {formatCurrency(row.balance)}
                </Text>
              </Group>
            );
          })}
        </Stack>
      )}
    </Card>
  );
}
