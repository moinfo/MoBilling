import {
  Container, Title, Text, Button, Group, SimpleGrid, Paper, Box, Image,
  ThemeIcon, ActionIcon, Badge, Stack, Divider, Card, List, Anchor,
  Loader, Center, Burger, Drawer,
  useMantineColorScheme, useComputedColorScheme, useMantineTheme,
} from '@mantine/core';
import { useDisclosure } from '@mantine/hooks';
import {
  IconFileInvoice, IconFileText, IconCalendarDue,
  IconCash, IconUsers, IconBuildingCommunity,
  IconSun, IconMoon, IconArrowRight, IconShieldCheck,
  IconDeviceMobile, IconChartBar, IconCheck,
  IconMail, IconPhone, IconMapPin, IconBrandWhatsapp,
  IconWorld,
} from '@tabler/icons-react';
import { Link } from 'react-router-dom';
import { useQuery } from '@tanstack/react-query';
import { motion } from 'framer-motion';
import { getPublicPlans, SubscriptionPlan } from '../api/subscription';

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

const planColors = ['blue', 'teal', 'violet', 'orange'];

export default function Landing() {
  const { toggleColorScheme } = useMantineColorScheme();
  const computedColorScheme = useComputedColorScheme('light');
  const theme = useMantineTheme();
  const dark = computedColorScheme === 'dark';
  const [drawerOpened, { toggle: toggleDrawer, close: closeDrawer }] = useDisclosure(false);

  return (
    <Box style={{ overflow: 'hidden' }}>
      {/* ── Top Contact Bar ── */}
      <Box
        py={6}
        bg={dark ? theme.colors.dark[8] : theme.colors.blue[6]}
        style={{ color: 'white' }}
        visibleFrom="sm"
      >
        <Container size="lg">
          <Group justify="space-between">
            <Group gap="lg">
              <Anchor href="mailto:info@moinfo.co.tz" size="xs" c="white" underline="never">
                <Group gap={4}><IconMail size={13} /> info@moinfo.co.tz</Group>
              </Anchor>
              <Anchor href="tel:+255689011111" size="xs" c="white" underline="never">
                <Group gap={4}><IconPhone size={13} /> +255 689 011 111</Group>
              </Anchor>
            </Group>
            <Anchor href="https://wa.me/255689011111" target="_blank" size="xs" c="white" underline="never">
              <Group gap={4}><IconBrandWhatsapp size={13} /> WhatsApp</Group>
            </Anchor>
          </Group>
        </Container>
      </Box>

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
              <Image src="/moinfotech-logo.png" h={32} w="auto" alt="MoBilling" />
              <Text size="lg" fw={800}>MoBilling</Text>
            </Group>

            {/* Desktop nav */}
            <Group gap="xs" visibleFrom="sm">
              <ActionIcon variant="default" size="lg" onClick={toggleColorScheme} aria-label="Toggle color scheme">
                {dark ? <IconSun size={18} /> : <IconMoon size={18} />}
              </ActionIcon>
              <Button variant="subtle" component={Link} to="/login">Sign In</Button>
              <Button variant="gradient" gradient={{ from: 'blue', to: 'cyan' }} component={Link} to="/register">
                Get Started
              </Button>
            </Group>

            {/* Mobile burger */}
            <Group gap="xs" hiddenFrom="sm">
              <ActionIcon variant="default" size="lg" onClick={toggleColorScheme} aria-label="Toggle color scheme">
                {dark ? <IconSun size={18} /> : <IconMoon size={18} />}
              </ActionIcon>
              <Burger opened={drawerOpened} onClick={toggleDrawer} size="sm" />
            </Group>
          </Group>
        </Container>
      </Paper>

      {/* Mobile navigation drawer */}
      <Drawer opened={drawerOpened} onClose={closeDrawer} size="xs" title="MoBilling" zIndex={200} padding="md">
        <Stack gap="sm">
          <Button fullWidth variant="subtle" component={Link} to="/login" onClick={closeDrawer}>Sign In</Button>
          <Button fullWidth variant="gradient" gradient={{ from: 'blue', to: 'cyan' }} component={Link} to="/register" onClick={closeDrawer}>
            Get Started
          </Button>
          <Divider my="xs" />
          <Group gap={6}>
            <IconMail size={14} />
            <Anchor href="mailto:info@moinfo.co.tz" size="sm">info@moinfo.co.tz</Anchor>
          </Group>
          <Group gap={6}>
            <IconPhone size={14} />
            <Anchor href="tel:+255689011111" size="sm">+255 689 011 111</Anchor>
          </Group>
          <Group gap={6}>
            <IconBrandWhatsapp size={14} />
            <Anchor href="https://wa.me/255689011111" target="_blank" size="sm">WhatsApp</Anchor>
          </Group>
        </Stack>
      </Drawer>

      {/* ── Hero ── */}
      <Box
        py={{ base: 48, sm: 100 }}
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
              h={{ base: 56, sm: 80 }}
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
              Built for East African Businesses
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

            <Text size="lg" c="dimmed" maw={560} mx="auto" mt="lg" lh={1.6}>
              Invoices, quotations, statutory bills, and payment tracking — all in one
              place. Stay compliant, get paid faster.
            </Text>

            <Group justify="center" mt={{ base: 24, sm: 36 }} wrap="wrap">
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
            <Group justify="center" mt={40} gap="lg" wrap="wrap">
              {stats.map((s) => (
                <Group key={s.label} gap={6}>
                  <s.icon size={18} color={theme.colors.blue[5]} />
                  <Text size="xs" fw={500} c="dimmed">{s.label}</Text>
                </Group>
              ))}
            </Group>
          </motion.div>
        </Container>
      </Box>

      {/* ── Features ── */}
      <Container size="lg" py={{ base: 48, sm: 80 }}>
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

      {/* ── Pricing ── */}
      <PricingSection dark={dark} theme={theme} />

      {/* ── Footer CTA ── */}
      <Box
        py={{ base: 48, sm: 80 }}
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
            <Title order={2} style={{ fontSize: 'clamp(1.4rem, 3vw, 2rem)' }}>Ready to simplify your billing?</Title>
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

      {/* ── Contact ── */}
      <Container size="lg" py={{ base: 48, sm: 80 }}>
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true }}
          transition={{ duration: 0.5 }}
        >
          <Stack align="center" mb={48}>
            <Badge variant="light" size="lg">Contact</Badge>
            <Title order={2} ta="center">Get in touch</Title>
            <Text c="dimmed" ta="center" maw={500}>
              Have questions or need help getting started? Reach out to our team.
            </Text>
          </Stack>
        </motion.div>

        <SimpleGrid cols={{ base: 1, sm: 2, md: 4 }} spacing="xl">
          {[
            {
              icon: IconMail,
              color: 'blue',
              title: 'Email',
              value: 'info@moinfo.co.tz',
              href: 'mailto:info@moinfo.co.tz',
            },
            {
              icon: IconPhone,
              color: 'green',
              title: 'Phone',
              value: '+255 689 011 111',
              href: 'tel:+255689011111',
            },
            {
              icon: IconBrandWhatsapp,
              color: 'teal',
              title: 'WhatsApp',
              value: '+255 689 011 111',
              href: 'https://wa.me/255689011111',
            },
            {
              icon: IconMapPin,
              color: 'orange',
              title: 'Location',
              value: 'Njuweni Hotel, 1st Floor, Room 134, Kibaha, Tanzania',
              href: undefined,
            },
          ].map((c) => (
            <motion.div
              key={c.title}
              initial={{ opacity: 0, y: 20 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true }}
              transition={{ duration: 0.4 }}
            >
              <Paper withBorder p="xl" radius="md" ta="center" h="100%">
                <ThemeIcon size={48} radius="xl" variant="light" color={c.color} mx="auto">
                  <c.icon size={24} />
                </ThemeIcon>
                <Text fw={600} mt="md">{c.title}</Text>
                {c.href ? (
                  <Anchor href={c.href} target={c.href.startsWith('http') ? '_blank' : undefined} size="sm" mt={4}>
                    {c.value}
                  </Anchor>
                ) : (
                  <Text size="sm" c="dimmed" mt={4}>{c.value}</Text>
                )}
              </Paper>
            </motion.div>
          ))}
        </SimpleGrid>
      </Container>

      {/* ── Footer ── */}
      <Divider />
      <Box py="xl" bg={dark ? theme.colors.dark[7] : theme.colors.gray[0]}>
        <Container size="lg">
          <SimpleGrid cols={{ base: 1, sm: 3 }} spacing="xl">
            <Stack gap={6}>
              <Group gap={8}>
                <Image src="/moinfotech-logo.png" h={28} w="auto" alt="MoBilling" />
                <Text fw={700}>MoBilling</Text>
              </Group>
              <Text size="sm" c="dimmed" maw={280}>
                Billing & Statutory Compliance platform for East African businesses.
              </Text>
            </Stack>

            <Stack gap={4}>
              <Text size="sm" fw={600} mb={4}>Quick Links</Text>
              <Anchor component={Link} to="/login" size="sm" c="dimmed">Sign In</Anchor>
              <Anchor component={Link} to="/register" size="sm" c="dimmed">Create Account</Anchor>
            </Stack>

            <Stack gap={4}>
              <Text size="sm" fw={600} mb={4}>Contact</Text>
              <Group gap={6}>
                <IconMail size={14} color="var(--mantine-color-dimmed)" />
                <Anchor href="mailto:info@moinfo.co.tz" size="sm" c="dimmed">info@moinfo.co.tz</Anchor>
              </Group>
              <Group gap={6}>
                <IconPhone size={14} color="var(--mantine-color-dimmed)" />
                <Anchor href="tel:+255689011111" size="sm" c="dimmed">+255 689 011 111</Anchor>
              </Group>
              <Group gap={6}>
                <IconMapPin size={14} color="var(--mantine-color-dimmed)" />
                <Text size="sm" c="dimmed">Kibaha, Tanzania</Text>
              </Group>
            </Stack>
          </SimpleGrid>

          <Divider my="lg" />

          <Stack gap={4} align="stretch">
            <Group justify="space-between" wrap="wrap" gap="xs">
              <Text size="xs" c="dimmed">
                &copy; {new Date().getFullYear()} MoBilling. All rights reserved.
              </Text>
              <Group gap={6}>
                <Text size="xs" c="dimmed">Powered by</Text>
                <Anchor href="https://moinfotech.co.tz" target="_blank" size="xs" fw={600}>
                  <Group gap={4}>
                    <IconWorld size={14} />
                    Moinfotech
                  </Group>
                </Anchor>
              </Group>
            </Group>
          </Stack>
        </Container>
      </Box>
    </Box>
  );
}

function PricingSection({ dark, theme }: { dark: boolean; theme: any }) {
  const { data, isLoading } = useQuery({
    queryKey: ['public-plans'],
    queryFn: getPublicPlans,
  });

  const plans: SubscriptionPlan[] = data?.data?.data || [];

  if (isLoading) {
    return (
      <Box py={{ base: 48, sm: 80 }} bg={dark ? theme.colors.dark[7] : theme.colors.gray[0]}>
        <Center><Loader /></Center>
      </Box>
    );
  }

  if (plans.length === 0) return null;

  return (
    <Box py={{ base: 48, sm: 80 }} bg={dark ? theme.colors.dark[7] : theme.colors.gray[0]}>
      <Container size="lg">
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true }}
          transition={{ duration: 0.5 }}
        >
          <Stack align="center" mb={48}>
            <Badge variant="light" size="lg">Pricing</Badge>
            <Title order={2} ta="center">Simple, transparent pricing</Title>
            <Text c="dimmed" ta="center" maw={500}>
              Start with a free trial. Choose a plan that fits your business when you're ready.
            </Text>
          </Stack>
        </motion.div>

        <SimpleGrid cols={{ base: 1, sm: 2, md: plans.length >= 4 ? 4 : plans.length }}>
          {plans.map((plan, i) => {
            const color = planColors[i % planColors.length];
            return (
              <motion.div
                key={plan.id}
                initial={{ opacity: 0, y: 24 }}
                whileInView={{ opacity: 1, y: 0 }}
                viewport={{ once: true, margin: '-40px' }}
                transition={{ duration: 0.4, delay: i * 0.1 }}
              >
                <Card
                  withBorder
                  padding="xl"
                  radius="md"
                  h="100%"
                  style={{ borderTop: `3px solid var(--mantine-color-${color}-6)` }}
                >
                  <Stack gap="md" justify="space-between" h="100%">
                    <div>
                      <Text fw={700} size="lg">{plan.name}</Text>
                      {plan.description && (
                        <Text size="sm" c="dimmed" mt={4}>{plan.description}</Text>
                      )}

                      <Group gap={4} align="baseline" mt="md">
                        <Text style={{ fontSize: 'clamp(1.4rem, 4vw, 2rem)' }} fw={800} lh={1}>
                          TZS {Number(plan.price).toLocaleString()}
                        </Text>
                      </Group>
                      <Text size="sm" c="dimmed">
                        per {plan.billing_cycle_days} days
                      </Text>

                      {plan.features && plan.features.length > 0 && (
                        <List
                          spacing={6}
                          size="sm"
                          mt="md"
                          icon={
                            <ThemeIcon size={18} radius="xl" color={color} variant="light">
                              <IconCheck size={11} />
                            </ThemeIcon>
                          }
                        >
                          {plan.features.map((f, fi) => <List.Item key={fi}>{f}</List.Item>)}
                        </List>
                      )}
                    </div>

                    <Button
                      fullWidth
                      size="md"
                      color={color}
                      component={Link}
                      to="/register"
                      rightSection={<IconArrowRight size={16} />}
                    >
                      Get Started
                    </Button>
                  </Stack>
                </Card>
              </motion.div>
            );
          })}
        </SimpleGrid>
      </Container>
    </Box>
  );
}
