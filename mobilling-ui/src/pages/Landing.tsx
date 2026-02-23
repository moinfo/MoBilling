import {
  Container, Title, Text, Button, Group, SimpleGrid, Paper, Box, Image,
  ThemeIcon, ActionIcon, Badge, Stack, Divider,
  useMantineColorScheme, useComputedColorScheme, useMantineTheme,
} from '@mantine/core';
import {
  IconFileInvoice, IconFileText, IconCalendarDue,
  IconCash, IconUsers, IconBuildingCommunity,
  IconSun, IconMoon, IconArrowRight, IconShieldCheck,
  IconDeviceMobile, IconChartBar,
} from '@tabler/icons-react';
import { Link } from 'react-router-dom';
import { motion } from 'framer-motion';

const features = [
  { icon: IconFileInvoice, color: 'blue', title: 'Invoicing', description: 'Professional invoices with automatic numbering, tax calculations, and real-time payment status.' },
  { icon: IconFileText, color: 'violet', title: 'Quotations & Proformas', description: 'Win business with polished quotes and proforma invoices that convert to final invoices in one click.' },
  { icon: IconCalendarDue, color: 'orange', title: 'Statutory Bills', description: 'Never miss NHIF, NSSF, PAYE, or VAT deadlines with automated tracking and due-date reminders.' },
  { icon: IconCash, color: 'green', title: 'Payment Tracking', description: 'Record M-Pesa, bank transfers, cash, and cheque payments — reconcile everything instantly.' },
  { icon: IconUsers, color: 'cyan', title: 'Client Management', description: 'Full client directory with KRA PINs, contacts, and complete billing history at a glance.' },
  { icon: IconBuildingCommunity, color: 'pink', title: 'Multi-tenant', description: 'Isolated workspaces per business — your data never mixes with anyone else\'s.' },
];

const stats = [
  { icon: IconShieldCheck, label: 'KRA Compliant' },
  { icon: IconDeviceMobile, label: 'M-Pesa Ready' },
  { icon: IconChartBar, label: 'Real-time Reports' },
];

export default function Landing() {
  const { toggleColorScheme } = useMantineColorScheme();
  const computedColorScheme = useComputedColorScheme('light');
  const theme = useMantineTheme();
  const dark = computedColorScheme === 'dark';

  return (
    <Box style={{ overflow: 'hidden' }}>
      {/* ── Header ── */}
      <Paper
        component="header"
        style={{
          position: 'sticky',
          top: 0,
          zIndex: 100,
          backdropFilter: 'blur(12px)',
          backgroundColor: dark
            ? 'rgba(26, 27, 30, 0.85)'
            : 'rgba(255, 255, 255, 0.85)',
          borderBottom: `1px solid ${dark ? theme.colors.dark[4] : theme.colors.gray[2]}`,
        }}
        shadow={undefined}
        p="sm"
      >
        <Container size="lg">
          <Group justify="space-between">
            <Group gap={8}>
              <Image src="/moinfotech-logo.png" h={36} w="auto" alt="MoBilling" />
              <Text size="xl" fw={800}>MoBilling</Text>
            </Group>
            <Group gap="xs">
              <ActionIcon variant="default" size="lg" onClick={toggleColorScheme} aria-label="Toggle color scheme">
                {dark ? <IconSun size={18} /> : <IconMoon size={18} />}
              </ActionIcon>
              <Button variant="subtle" component={Link} to="/login">Sign In</Button>
              <Button variant="gradient" gradient={{ from: 'blue', to: 'cyan' }} component={Link} to="/register">
                Get Started
              </Button>
            </Group>
          </Group>
        </Container>
      </Paper>

      {/* ── Hero ── */}
      <Box
        py={100}
        style={{
          background: dark
            ? `radial-gradient(ellipse at 50% 0%, ${theme.colors.blue[9]}22 0%, transparent 70%)`
            : `radial-gradient(ellipse at 50% 0%, ${theme.colors.blue[1]} 0%, transparent 70%)`,
        }}
      >
        <Container size="md">
          <motion.div
            initial={{ opacity: 0, y: 30 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.6 }}
            style={{ textAlign: 'center' }}
          >
            <Image
              src="/moinfotech-logo.png"
              h={80}
              w="auto"
              mx="auto"
              mb="lg"
              alt="MoBilling"
            />

            <Badge
              size="lg"
              variant="gradient"
              gradient={{ from: 'blue', to: 'cyan' }}
              mb="lg"
            >
              Built for Kenyan Businesses
            </Badge>

            <Title
              order={1}
              fw={900}
              style={{ fontSize: 'clamp(2rem, 5vw, 3.5rem)', lineHeight: 1.15 }}
            >
              Billing & Statutory{' '}
              <Text
                component="span"
                inherit
                variant="gradient"
                gradient={{ from: 'blue', to: 'cyan', deg: 90 }}
              >
                Compliance
              </Text>
              , Simplified
            </Title>

            <Text size="xl" c="dimmed" maw={560} mx="auto" mt="lg" lh={1.6}>
              Invoices, quotations, statutory bills, and payment tracking — all in one
              place. Stay compliant, get paid faster.
            </Text>

            <Group justify="center" mt={36}>
              <Button
                size="lg"
                variant="gradient"
                gradient={{ from: 'blue', to: 'cyan' }}
                rightSection={<IconArrowRight size={18} />}
                component={Link}
                to="/register"
              >
                Start Free
              </Button>
              <Button size="lg" variant="default" component={Link} to="/login">
                Sign In
              </Button>
            </Group>

            {/* Trust badges */}
            <Group justify="center" mt={48} gap="xl">
              {stats.map((s) => (
                <Group key={s.label} gap={8}>
                  <s.icon size={20} color={theme.colors.blue[5]} />
                  <Text size="sm" fw={500} c="dimmed">{s.label}</Text>
                </Group>
              ))}
            </Group>
          </motion.div>
        </Container>
      </Box>

      {/* ── Features ── */}
      <Container size="lg" py={80}>
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true }}
          transition={{ duration: 0.5 }}
        >
          <Stack align="center" mb={48}>
            <Badge variant="light" size="lg">Features</Badge>
            <Title order={2} ta="center">Everything you need to run your business</Title>
            <Text c="dimmed" ta="center" maw={500}>
              From generating invoices to tracking statutory obligations — MoBilling handles it all.
            </Text>
          </Stack>
        </motion.div>

        <SimpleGrid cols={{ base: 1, sm: 2, md: 3 }} spacing="xl">
          {features.map((f, i) => (
            <motion.div
              key={f.title}
              initial={{ opacity: 0, y: 24 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true, margin: '-40px' }}
              transition={{ duration: 0.4, delay: i * 0.08 }}
            >
              <Paper
                withBorder
                p="xl"
                radius="md"
                h="100%"
                style={{
                  transition: 'transform 150ms ease, box-shadow 150ms ease',
                  cursor: 'default',
                }}
                onMouseEnter={(e) => {
                  e.currentTarget.style.transform = 'translateY(-4px)';
                  e.currentTarget.style.boxShadow = theme.shadows.md;
                }}
                onMouseLeave={(e) => {
                  e.currentTarget.style.transform = 'translateY(0)';
                  e.currentTarget.style.boxShadow = '';
                }}
              >
                <ThemeIcon size={48} radius="md" variant="light" color={f.color}>
                  <f.icon size={26} />
                </ThemeIcon>
                <Text size="lg" fw={600} mt="md">{f.title}</Text>
                <Text size="sm" c="dimmed" mt={6} lh={1.6}>{f.description}</Text>
              </Paper>
            </motion.div>
          ))}
        </SimpleGrid>
      </Container>

      {/* ── Footer CTA ── */}
      <Box
        py={80}
        style={{
          background: dark
            ? `linear-gradient(135deg, ${theme.colors.blue[9]}33 0%, ${theme.colors.cyan[9]}22 100%)`
            : `linear-gradient(135deg, ${theme.colors.blue[0]} 0%, ${theme.colors.cyan[0]} 100%)`,
        }}
      >
        <Container size="sm" ta="center">
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            whileInView={{ opacity: 1, y: 0 }}
            viewport={{ once: true }}
            transition={{ duration: 0.5 }}
          >
            <Title order={2} size="2rem">Ready to simplify your billing?</Title>
            <Text c="dimmed" mt="sm" size="lg">
              Create a free account and start managing invoices, payments, and compliance in minutes.
            </Text>
            <Button
              size="lg"
              mt="xl"
              variant="gradient"
              gradient={{ from: 'blue', to: 'cyan' }}
              rightSection={<IconArrowRight size={18} />}
              component={Link}
              to="/register"
            >
              Create Free Account
            </Button>
          </motion.div>
        </Container>
      </Box>

      {/* ── Footer ── */}
      <Divider />
      <Container size="lg" py="md">
        <Group justify="space-between">
          <Text size="sm" c="dimmed">
            &copy; {new Date().getFullYear()} MoBilling. All rights reserved.
          </Text>
          <Text size="sm" c="dimmed">Billing & Statutory Compliance</Text>
        </Group>
      </Container>
    </Box>
  );
}
