import { Paper, Group, Text, ThemeIcon } from '@mantine/core';
import { ReactNode } from 'react';

interface Props {
  label: string;
  value: string | number;
  icon: ReactNode;
  color?: string;
  subtitle?: string;
}

export default function StatCard({ label, value, icon, color = 'blue', subtitle }: Props) {
  return (
    <Paper withBorder p="md" radius="md">
      <Group justify="space-between" wrap="nowrap">
        <div>
          <Text size="xs" c="dimmed" tt="uppercase" fw={700}>{label}</Text>
          <Text fw={700} size="xl" mt={4}>{value}</Text>
          {subtitle && <Text size="xs" c="dimmed" mt={2}>{subtitle}</Text>}
        </div>
        <ThemeIcon color={color} variant="light" size="xl" radius="md">
          {icon}
        </ThemeIcon>
      </Group>
    </Paper>
  );
}
