import { Stack, Paper, Title, Text, SimpleGrid, Group, ThemeIcon, UnstyledButton } from '@mantine/core';
import { useNavigate } from 'react-router-dom';
import {
  IconWorld, IconMail, IconServer, IconDeviceDesktop, IconUsers, IconPalette,
  IconWorldWww, IconChevronRight,
} from '@tabler/icons-react';
import { STOREFRONT } from '../../data/storefront';

const ICONS: Record<string, typeof IconWorld> = {
  'web-hosting': IconWorld,
  'email-hosting': IconMail,
  vps: IconServer,
  'dedicated-server': IconDeviceDesktop,
  'reseller-hosting': IconUsers,
  'website-design': IconPalette,
};

export default function OrderIndex() {
  const navigate = useNavigate();

  const tiles = [
    ...STOREFRONT.map((c) => ({
      slug: c.slug, label: c.label, description: c.description, to: `/order/${c.slug}`,
      Icon: ICONS[c.slug] ?? IconWorld,
    })),
    {
      slug: 'domain',
      label: 'Domains',
      description: 'Register a new domain or transfer one to us.',
      to: '/order/domain',
      Icon: IconWorldWww,
    },
  ];

  return (
    <Stack gap="lg" maw={980}>
      <div>
        <Title order={3}>Order a service</Title>
        <Text c="dimmed" size="sm">Pick what you need — you'll get an invoice to pay right away.</Text>
      </div>

      <SimpleGrid cols={{ base: 1, sm: 2, lg: 3 }}>
        {tiles.map(({ slug, label, description, to, Icon }) => (
          <UnstyledButton key={slug} onClick={() => navigate(to)}>
            <Paper withBorder p="lg" radius="md" h="100%">
              <Group justify="space-between" align="flex-start" wrap="nowrap">
                <Group align="flex-start" wrap="nowrap" gap="sm">
                  <ThemeIcon variant="light" size="lg" radius="md"><Icon size={20} /></ThemeIcon>
                  <div>
                    <Text fw={600}>{label}</Text>
                    <Text c="dimmed" size="sm">{description}</Text>
                  </div>
                </Group>
                <IconChevronRight size={18} opacity={0.5} />
              </Group>
            </Paper>
          </UnstyledButton>
        ))}
      </SimpleGrid>
    </Stack>
  );
}
