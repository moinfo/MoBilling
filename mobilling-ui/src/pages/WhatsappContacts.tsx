import { useState } from 'react';
import {
  Title, Stack, Group, Button, Badge, Table, Text, ActionIcon, Tooltip,
  Select, TextInput, SimpleGrid, Card, ThemeIcon, Anchor, Tabs,
} from '@mantine/core';
import {
  IconBrandWhatsapp, IconPlus, IconEdit, IconTrash, IconStar, IconStarFilled,
  IconUserCheck, IconSearch, IconUsers, IconChartBar, IconSpeakerphone, IconPhone,
} from '@tabler/icons-react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { usePermissions } from '../hooks/usePermissions';
import { notifications } from '@mantine/notifications';
import {
  getContacts, getStats, deleteContact, updateContact,
  LABEL_META, LABEL_ORDER, SOURCE_META, WhatsappContact, WaSource,
} from '../api/whatsappContacts';
import { getCampaigns, deleteCampaign } from '../api/whatsappCampaigns';
import { WhatsappCampaign } from '../api/whatsappCampaigns';
import WhatsappContactForm from '../components/WhatsApp/WhatsappContactForm';
import ConvertToClientModal from '../components/WhatsApp/ConvertToClientModal';
import CampaignForm from '../components/WhatsApp/CampaignForm';
import FollowupDrawer from '../components/WhatsApp/FollowupDrawer';
import { formatCurrency } from '../utils/formatCurrency';

const LABEL_OPTIONS = [
  { value: '', label: 'All Stages' },
  ...LABEL_ORDER.map((v) => ({ value: v, label: LABEL_META[v].label })),
];
const SOURCE_OPTIONS = [
  { value: '', label: 'All Sources' },
  ...(Object.keys(SOURCE_META) as WaSource[]).map((v) => ({ value: v, label: SOURCE_META[v] })),
];

export default function WhatsappContacts() {
  const qc = useQueryClient();
  const { can } = usePermissions();
  const [tab, setTab] = useState<string>('contacts');
  const [search, setSearch] = useState('');
  const [labelFilter, setLabelFilter] = useState('');
  const [sourceFilter, setSourceFilter] = useState('');
  const [formOpened, setFormOpened] = useState(false);
  const [editContact, setEditContact] = useState<WhatsappContact | null>(null);
  const [convertContact, setConvertContact] = useState<WhatsappContact | null>(null);
  const [campaignFormOpened, setCampaignFormOpened] = useState(false);
  const [editCampaign, setEditCampaign] = useState<WhatsappCampaign | null>(null);
  const [followupContact, setFollowupContact] = useState<WhatsappContact | null>(null);

  const params: Record<string, string> = {};
  if (search) params.search = search;
  if (labelFilter) params.label = labelFilter;
  if (sourceFilter) params.source = sourceFilter;

  const { data: contactsData, isLoading } = useQuery({
    queryKey: ['whatsapp-contacts', params],
    queryFn: () => getContacts(params),
  });

  const { data: statsData } = useQuery({
    queryKey: ['whatsapp-stats'],
    queryFn: getStats,
  });

  const { data: campaignsData } = useQuery({
    queryKey: ['whatsapp-campaigns'],
    queryFn: getCampaigns,
  });

  const contacts = contactsData?.data ?? [];
  const stats = statsData?.data;
  const campaigns = campaignsData?.data ?? [];

  const deleteMutation = useMutation({
    mutationFn: deleteContact,
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['whatsapp-contacts'] });
      qc.invalidateQueries({ queryKey: ['whatsapp-stats'] });
      notifications.show({ message: 'Contact deleted', color: 'red' });
    },
  });

  const deleteCampaignMutation = useMutation({
    mutationFn: deleteCampaign,
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['whatsapp-campaigns'] });
      notifications.show({ message: 'Campaign deleted', color: 'red' });
    },
  });

  const toggleImportant = (contact: WhatsappContact) => {
    updateContact(contact.id, { is_important: !contact.is_important }).then(() => {
      qc.invalidateQueries({ queryKey: ['whatsapp-contacts'] });
    });
  };

  return (
    <Stack>
      <Group justify="space-between">
        <Group gap="xs">
          <ThemeIcon color="green" variant="light" size="lg" radius="xl">
            <IconBrandWhatsapp size={20} />
          </ThemeIcon>
          <Title order={2}>WhatsApp Marketing</Title>
        </Group>
        {tab === 'contacts' && can('whatsapp_contacts.create') && (
          <Button leftSection={<IconPlus size={16} />} color="green" onClick={() => { setEditContact(null); setFormOpened(true); }}>
            Add Contact
          </Button>
        )}
        {tab === 'campaigns' && can('whatsapp_campaigns.create') && (
          <Button leftSection={<IconPlus size={16} />} color="green" onClick={() => { setEditCampaign(null); setCampaignFormOpened(true); }}>
            New Campaign
          </Button>
        )}
      </Group>

      {/* Stats */}
      {stats && (
        <SimpleGrid cols={{ base: 2, sm: 4 }}>
          <Card withBorder padding="sm" radius="md">
            <Group gap="xs">
              <ThemeIcon color="blue" variant="light"><IconUsers size={16} /></ThemeIcon>
              <div>
                <Text size="xs" c="dimmed">Total Contacts</Text>
                <Text fw={700}>{stats.total}</Text>
              </div>
            </Group>
          </Card>
          <Card withBorder padding="sm" radius="md">
            <Group gap="xs">
              <ThemeIcon color="green" variant="light"><IconUserCheck size={16} /></ThemeIcon>
              <div>
                <Text size="xs" c="dimmed">Converted to Clients</Text>
                <Text fw={700}>{stats.converted}</Text>
              </div>
            </Group>
          </Card>
          <Card withBorder padding="sm" radius="md">
            <Group gap="xs">
              <ThemeIcon color="violet" variant="light"><IconBrandWhatsapp size={16} /></ThemeIcon>
              <div>
                <Text size="xs" c="dimmed">From WhatsApp Ads</Text>
                <Text fw={700}>{stats.by_source?.whatsapp_ad ?? 0}</Text>
              </div>
            </Group>
          </Card>
          <Card withBorder padding="sm" radius="md">
            <Group gap="xs">
              <ThemeIcon color="orange" variant="light"><IconChartBar size={16} /></ThemeIcon>
              <div>
                <Text size="xs" c="dimmed">Conversion Rate</Text>
                <Text fw={700}>
                  {stats.total > 0 ? `${Math.round((stats.converted / stats.total) * 100)}%` : '0%'}
                </Text>
              </div>
            </Group>
          </Card>
        </SimpleGrid>
      )}

      <Tabs value={tab} onChange={(v) => setTab(v ?? 'contacts')}>
        <Tabs.List>
          {can('whatsapp_contacts.read') && <Tabs.Tab value="contacts" leftSection={<IconUsers size={14} />}>Contacts</Tabs.Tab>}
          {can('whatsapp_campaigns.read') && (
            <Tabs.Tab value="campaigns" leftSection={<IconSpeakerphone size={14} />}>
              Ad Campaigns {campaigns.length > 0 && <Badge size="xs" ml={4}>{campaigns.length}</Badge>}
            </Tabs.Tab>
          )}
        </Tabs.List>

        {/* Contacts Tab */}
        <Tabs.Panel value="contacts" pt="md">
          <Stack gap="sm">
            {/* Pipeline badges */}
            <Group gap="xs" wrap="wrap">
              {LABEL_ORDER.map((l) => (
                <Badge
                  key={l}
                  color={LABEL_META[l].color}
                  variant={labelFilter === l ? 'filled' : 'light'}
                  style={{ cursor: 'pointer' }}
                  onClick={() => setLabelFilter(labelFilter === l ? '' : l)}
                >
                  {LABEL_META[l].label} ({stats?.by_label?.[l] ?? 0})
                </Badge>
              ))}
            </Group>

            <Group>
              <TextInput
                placeholder="Search name or phone..."
                leftSection={<IconSearch size={14} />}
                value={search}
                onChange={(e) => setSearch(e.currentTarget.value)}
                w={220}
              />
              <Select data={LABEL_OPTIONS} value={labelFilter} onChange={(v) => setLabelFilter(v ?? '')} w={160} />
              <Select data={SOURCE_OPTIONS} value={sourceFilter} onChange={(v) => setSourceFilter(v ?? '')} w={160} />
            </Group>

            <Table.ScrollContainer minWidth={750}>
              <Table highlightOnHover>
                <Table.Thead>
                  <Table.Tr>
                    <Table.Th w={40}>#</Table.Th>
                    <Table.Th></Table.Th>
                    <Table.Th>Name</Table.Th>
                    <Table.Th>Phone</Table.Th>
                    <Table.Th>Services</Table.Th>
                    <Table.Th>Stage</Table.Th>
                    <Table.Th>Source</Table.Th>
                    <Table.Th>Campaign</Table.Th>
                    <Table.Th>Follow-up</Table.Th>
                    <Table.Th>Client</Table.Th>
                    <Table.Th></Table.Th>
                  </Table.Tr>
                </Table.Thead>
                <Table.Tbody>
                  {isLoading ? (
                    <Table.Tr><Table.Td colSpan={11}><Text c="dimmed" ta="center" py="md">Loading...</Text></Table.Td></Table.Tr>
                  ) : contacts.length === 0 ? (
                    <Table.Tr><Table.Td colSpan={11}><Text c="dimmed" ta="center" py="md">No contacts found</Text></Table.Td></Table.Tr>
                  ) : contacts.map((c, idx) => (
                    <Table.Tr key={c.id}>
                      <Table.Td><Text size="sm" c="dimmed">{idx + 1}</Text></Table.Td>
                      <Table.Td>
                        <ActionIcon variant="subtle" color="yellow" onClick={() => toggleImportant(c)}>
                          {c.is_important ? <IconStarFilled size={16} /> : <IconStar size={16} />}
                        </ActionIcon>
                      </Table.Td>
                      <Table.Td fw={c.is_important ? 600 : 400}>{c.name}</Table.Td>
                      <Table.Td>
                        <Anchor href={`https://wa.me/${c.phone.replace(/\D/g, '')}`} target="_blank" size="sm">
                          {c.phone}
                        </Anchor>
                      </Table.Td>
                      <Table.Td>
                        <Group gap={4} wrap="wrap">
                          {c.services?.length
                            ? c.services.map(s => <Badge key={s} size="xs" variant="outline">{s}</Badge>)
                            : <Text size="xs" c="dimmed">—</Text>}
                        </Group>
                      </Table.Td>
                      <Table.Td>
                        <Badge color={LABEL_META[c.label].color} variant="light">{LABEL_META[c.label].label}</Badge>
                      </Table.Td>
                      <Table.Td><Text size="sm">{SOURCE_META[c.source]}</Text></Table.Td>
                      <Table.Td>
                        <Text size="sm" c="dimmed">{c.campaign?.name ?? '—'}</Text>
                      </Table.Td>
                      <Table.Td>
                        <Text size="sm" c={c.next_followup_date && new Date(c.next_followup_date) < new Date() ? 'red' : undefined}>
                          {c.next_followup_date ?? '—'}
                        </Text>
                      </Table.Td>
                      <Table.Td>
                        {c.client
                          ? <Text size="sm" c="green">{c.client.name}</Text>
                          : <Text size="sm" c="dimmed">—</Text>}
                      </Table.Td>
                      <Table.Td>
                        <Group gap={4} justify="flex-end">
                          {can('whatsapp_contacts.log') && (
                            <Tooltip label="Log Call / Follow-up">
                              <ActionIcon variant="light" color="teal" onClick={() => setFollowupContact(c)}>
                                <IconPhone size={15} />
                              </ActionIcon>
                            </Tooltip>
                          )}
                          {can('whatsapp_contacts.convert') && !c.client_id && (
                            <Tooltip label="Convert to Client">
                              <ActionIcon variant="light" color="green" onClick={() => setConvertContact(c)}>
                                <IconUserCheck size={15} />
                              </ActionIcon>
                            </Tooltip>
                          )}
                          {can('whatsapp_contacts.update') && (
                            <ActionIcon variant="light" onClick={() => { setEditContact(c); setFormOpened(true); }}>
                              <IconEdit size={15} />
                            </ActionIcon>
                          )}
                          {can('whatsapp_contacts.delete') && (
                            <ActionIcon variant="light" color="red" onClick={() => deleteMutation.mutate(c.id)}>
                              <IconTrash size={15} />
                            </ActionIcon>
                          )}
                        </Group>
                      </Table.Td>
                    </Table.Tr>
                  ))}
                </Table.Tbody>
              </Table>
            </Table.ScrollContainer>
          </Stack>
        </Tabs.Panel>

        {/* Campaigns Tab */}
        <Tabs.Panel value="campaigns" pt="md">
          <Table.ScrollContainer minWidth={600}>
            <Table highlightOnHover>
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Campaign</Table.Th>
                  <Table.Th>Start Date</Table.Th>
                  <Table.Th>End Date</Table.Th>
                  <Table.Th>Budget</Table.Th>
                  <Table.Th>Leads</Table.Th>
                  <Table.Th>Converted</Table.Th>
                  <Table.Th>Cost / Lead</Table.Th>
                  <Table.Th></Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {campaigns.length === 0 ? (
                  <Table.Tr><Table.Td colSpan={8}><Text c="dimmed" ta="center" py="md">No campaigns yet</Text></Table.Td></Table.Tr>
                ) : campaigns.map((camp) => {
                  const costPerLead = camp.leads_count > 0 ? camp.budget / camp.leads_count : null;
                  return (
                    <Table.Tr key={camp.id}>
                      <Table.Td fw={500}>{camp.name}</Table.Td>
                      <Table.Td>{camp.start_date}</Table.Td>
                      <Table.Td>{camp.end_date ?? '—'}</Table.Td>
                      <Table.Td>{formatCurrency(camp.budget)}</Table.Td>
                      <Table.Td>
                        <Badge variant="light" color="blue">{camp.leads_count}</Badge>
                      </Table.Td>
                      <Table.Td>
                        <Badge variant="light" color="green">{camp.converted_count}</Badge>
                      </Table.Td>
                      <Table.Td>
                        <Text size="sm" c="dimmed">
                          {costPerLead != null ? formatCurrency(costPerLead) : '—'}
                        </Text>
                      </Table.Td>
                      <Table.Td>
                        <Group gap={4} justify="flex-end">
                          {can('whatsapp_campaigns.update') && (
                            <ActionIcon variant="light" onClick={() => { setEditCampaign(camp); setCampaignFormOpened(true); }}>
                              <IconEdit size={15} />
                            </ActionIcon>
                          )}
                          {can('whatsapp_campaigns.delete') && (
                            <ActionIcon variant="light" color="red" onClick={() => deleteCampaignMutation.mutate(camp.id)}>
                              <IconTrash size={15} />
                            </ActionIcon>
                          )}
                        </Group>
                      </Table.Td>
                    </Table.Tr>
                  );
                })}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        </Tabs.Panel>
      </Tabs>

      <WhatsappContactForm opened={formOpened} onClose={() => setFormOpened(false)} contact={editContact} />
      <ConvertToClientModal contact={convertContact} onClose={() => setConvertContact(null)} />
      <CampaignForm opened={campaignFormOpened} onClose={() => setCampaignFormOpened(false)} campaign={editCampaign} />
      <FollowupDrawer contact={followupContact} onClose={() => setFollowupContact(null)} />
    </Stack>
  );
}
