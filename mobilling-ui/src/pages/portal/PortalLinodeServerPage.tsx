import { useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { Paper, Title, Table, Modal, Stack, Text, Alert, TextInput, Group, Button, Badge, Divider, Textarea, Loader, Drawer, Select, Checkbox, Code, CopyButton, ActionIcon, Center } from '@mantine/core';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { notifications } from '@mantine/notifications';
import { IconRefresh, IconLifebuoy, IconArrowLeft, IconSettings, IconCopy, IconCheck, IconWorldWww } from '@tabler/icons-react';
import { useAuth } from '../../context/AuthContext';
import {
  getPortalLinodeServer, portalLinodeReboot, portalLinodeRequestDomain, portalLinodeSupportTicket, getPortalDnsRecords, addPortalDnsRecord, updatePortalDnsRecord,
  portalDnsPointToServer, PortalAddDomainResult, PortalSoa, getPortalDnsDomain, updatePortalDnsSoa,
} from '../../api/portal';
import { DOMAIN_TTLS, SOA_TTLS, LINODE_NAMESERVERS } from '../../api/linode';
import { DnsSections, DnsRecordModal, DnsRec, DnsPayload, dnsErrMsg, ttlSelectData } from '../../components/DnsSections';

const errMsg = dnsErrMsg;

const ttlOptions = ttlSelectData;

function NameserverCard({ nameservers }: { nameservers: string[] }) {
  return (
    <Paper withBorder p="sm">
      <Text size="sm" fw={600}>Weka nameservers hizi kwa msajili wa domain</Text>
      <Stack gap={4} my="xs">
        {nameservers.map((n) => (
          <Group key={n} gap="xs">
            <Code>{n}</Code>
            <CopyButton value={n}>{({ copied, copy }) => (
              <ActionIcon size="sm" variant="subtle" onClick={copy} aria-label={`Nakili ${n}`}>{copied ? <IconCheck size={14} /> : <IconCopy size={14} />}</ActionIcon>
            )}</CopyButton>
          </Group>
        ))}
      </Stack>
      <CopyButton value={nameservers.join('\n')}>{({ copied, copy }) => (
        <Button size="xs" variant="light" leftSection={copied ? <IconCheck size={14} /> : <IconCopy size={14} />} onClick={copy}>{copied ? 'Imenakiliwa' : 'Nakili zote'}</Button>
      )}</CopyButton>
      <Text size="xs" c="dimmed" mt="xs">Mabadiliko yanaweza kuchukua hadi saa kadhaa kusambaa.</Text>
    </Paper>
  );
}

function SoaModal({ sid, did, soa, onClose, onSaved }: { sid: string; did: string; soa: PortalSoa; onClose: () => void; onSaved: () => void }) {
  const [email, setEmail] = useState(soa.soa_email ?? '');
  const [f, setF] = useState({ ttl_sec: String(soa.ttl_sec), refresh_sec: String(soa.refresh_sec), retry_sec: String(soa.retry_sec), expire_sec: String(soa.expire_sec) });
  const [error, setError] = useState<string | null>(null);
  const m = useMutation({
    mutationFn: () => updatePortalDnsSoa(sid, did, { soa_email: email.trim(), ttl_sec: Number(f.ttl_sec), refresh_sec: Number(f.refresh_sec), retry_sec: Number(f.retry_sec), expire_sec: Number(f.expire_sec) }),
    onSuccess: (r) => { notifications.show({ color: 'green', message: r.data.message }); onSaved(); onClose(); },
    onError: (e) => setError(errMsg(e)),
  });
  const sel = (label: string, k: keyof typeof f) => <Select label={label} data={ttlSelectData(SOA_TTLS)} value={f[k]} onChange={(v) => setF({ ...f, [k]: v ?? '0' })} allowDeselect={false} />;
  return (
    <Modal opened onClose={onClose} title="Hariri SOA Record" zIndex={500}>
      <Stack>
        {error && <Alert color="red">{error}</Alert>}
        <TextInput label="Email" value={email} onChange={(e) => setEmail(e.currentTarget.value)} required />
        {sel('Default TTL', 'ttl_sec')}{sel('Refresh Rate', 'refresh_sec')}{sel('Retry Rate', 'retry_sec')}{sel('Expire Time', 'expire_sec')}
        <Button loading={m.isPending} disabled={!email.trim()} onClick={() => { setError(null); m.mutate(); }}>Hifadhi</Button>
      </Stack>
    </Modal>
  );
}

function DnsDrawer({ sid, domain, isAdmin, serverIp, onClose }: { sid: string; domain: { id: string; name: string; registered_domain_id: string | null }; isAdmin: boolean; serverIp: string | null; onClose: () => void }) {
  const qc = useQueryClient();
  const navigate = useNavigate();
  const key = ['portal-dns', sid, domain.id];
  const soaKey = ['portal-dns-soa', sid, domain.id];
  const { data, isLoading, isError, error } = useQuery({ queryKey: key, queryFn: () => getPortalDnsRecords(sid, domain.id), retry: false });
  const soaQ = useQuery({ queryKey: soaKey, queryFn: () => getPortalDnsDomain(sid, domain.id), retry: false });
  const rows = (data?.data?.data ?? []) as DnsRec[];
  const [editing, setEditing] = useState<{ type: string; record: DnsRec | null } | null>(null);
  const [soaOpen, setSoaOpen] = useState(false);
  const point = useMutation({
    mutationFn: () => portalDnsPointToServer(sid, domain.id),
    onSuccess: (r) => { notifications.show({ color: 'green', message: r.data.message }); qc.invalidateQueries({ queryKey: key }); qc.invalidateQueries({ queryKey: ['portal-linode', sid] }); },
    onError: (e) => notifications.show({ color: 'red', message: errMsg(e) }),
  });
  const submit = async (p: DnsPayload, record: DnsRec | null) => {
    const r = record ? await updatePortalDnsRecord(sid, domain.id, record.id, p) : await addPortalDnsRecord(sid, domain.id, p);
    notifications.show({ color: 'green', message: r.data.message });
  };
  return (
    <Drawer opened onClose={onClose} title={domain.name} position="right" size="xl" zIndex={400}>
      <Stack>
        <NameserverCard nameservers={data?.data?.meta?.nameservers ?? LINODE_NAMESERVERS} />
        {domain.registered_domain_id && (
          <Alert color="blue">Domain hii imesajiliwa kupitia sisi. <Button size="compact-xs" variant="subtle" onClick={() => navigate(`/portal/domains/${domain.registered_domain_id}`)}>Simamia usajili na nameservers</Button></Alert>
        )}
        <Text size="xs" c="dimmed">Records za NS zinasimamiwa na Linode na haziwezi kubadilishwa. Unaweza kuongeza au kuhariri records, lakini si kuzifuta.</Text>
        {isAdmin && (
          <Group>
            <Button size="xs" variant="light" leftSection={<IconWorldWww size={14} />} loading={point.isPending} disabled={!serverIp}
              onClick={() => { if (window.confirm(`Weka records za A na www zielekee ${serverIp}?`)) point.mutate(); }}>Elekeza kwenye server hii</Button>
          </Group>
        )}
        {isLoading ? <Center><Loader /></Center> : isError ? <Alert color="red">{errMsg(error)}</Alert> : (
          <DnsSections domain={domain.name} rows={rows} sw canManage={isAdmin}
            soa={soaQ.isLoading || soaQ.isError ? undefined : (soaQ.data?.data?.data ?? null)}
            onAdd={(t) => setEditing({ type: t, record: null })} onEdit={(r) => setEditing({ type: r.type, record: r })} onEditSoa={() => setSoaOpen(true)} />
        )}
      </Stack>
      {editing && <DnsRecordModal type={editing.type} record={editing.record} domain={domain.name} sw submit={submit} onClose={() => setEditing(null)} onSaved={() => qc.invalidateQueries({ queryKey: key })} />}
      {soaOpen && soaQ.data?.data?.data && <SoaModal sid={sid} did={domain.id} soa={soaQ.data.data.data} onClose={() => setSoaOpen(false)} onSaved={() => qc.invalidateQueries({ queryKey: soaKey })} />}
    </Drawer>
  );
}

const reqColor: Record<string, string> = { pending: 'yellow', approved: 'green', rejected: 'red' };
const reqLabel: Record<string, string> = { pending: 'Inasubiri', approved: 'Imekubaliwa', rejected: 'Imekataliwa' };

/** Full page for one Linode server: status, reboot only (never shutdown/boot/delete), domains, add-domain request, support ticket. */
export default function PortalLinodeServerPage() {
  const { user } = useAuth();
  const isAdmin = (user as any)?.role === 'admin';
  const { id = '' } = useParams();
  const navigate = useNavigate();
  const qc = useQueryClient();
  const [rebootOpen, setRebootOpen] = useState(false);
  const [confirm, setConfirm] = useState('');
  const [domain, setDomain] = useState('');
  const [soa, setSoa] = useState((user as any)?.email ?? '');
  const [ttl, setTtl] = useState<string>('0');
  const [pointToServer, setPointToServer] = useState(true);
  const [added, setAdded] = useState<PortalAddDomainResult | null>(null);
  const [dnsFor, setDnsFor] = useState<{ id: string; name: string; registered_domain_id: string | null } | null>(null);
  const [ticketOpen, setTicketOpen] = useState(false);
  const [ticketMsg, setTicketMsg] = useState('');
  const key = ['portal-linode', id];
  const { data, isLoading, error } = useQuery({ queryKey: key, queryFn: () => getPortalLinodeServer(id), retry: false });
  const info = data?.data?.data;
  const server = { id, name: info?.server.name ?? '', status: info?.server.status };

  const reboot = useMutation({
    mutationFn: () => portalLinodeReboot(id, confirm),
    onSuccess: (r) => {
      notifications.show({ color: 'green', message: r.data.message });
      setRebootOpen(false); setConfirm('');
      qc.invalidateQueries({ queryKey: ['portal-subscriptions'] }); qc.invalidateQueries({ queryKey: key });
    },
    onError: (e) => notifications.show({ color: 'red', message: errMsg(e) }),
  });
  const request = useMutation({
    mutationFn: () => portalLinodeRequestDomain(id, { domain: domain.trim().toLowerCase(), soa_email: soa.trim() || undefined, ttl: Number(ttl), point_to_server: pointToServer }),
    onSuccess: (r) => { notifications.show({ color: 'green', message: r.data.message }); setAdded(r.data.data); setDomain(''); qc.invalidateQueries({ queryKey: key }); },
    onError: (e) => notifications.show({ color: 'red', message: errMsg(e) }),
  });
  const ticket = useMutation({
    mutationFn: () => portalLinodeSupportTicket(id, ticketMsg.trim() || undefined),
    onSuccess: (r) => { notifications.show({ color: 'green', message: r.data.message }); setTicketOpen(false); setTicketMsg(''); },
    onError: (e) => notifications.show({ color: 'red', message: errMsg(e) }),
  });

  const busy = ['booting', 'rebooting', 'shutting_down', 'provisioning', 'migrating', 'rebuilding'].includes(String(info?.server.status ?? server.status));

  return (
    <Stack>
      <Group>
        <Button variant="subtle" size="compact-sm" leftSection={<IconArrowLeft size={14} />} onClick={() => navigate('/portal/subscriptions')}>Subscriptions</Button>
      </Group>
      {error ? <Alert color="red">Server haipatikani au huna ruhusa ya kuiona.</Alert> : isLoading || !info ? <Loader size="sm" /> : (
        <Paper withBorder p="md">
          <Stack>
            <Title order={3}>Server {info.server.name}</Title>
            <Text size="sm" c="dimmed">
              {info.server.ip ?? '-'} · {info.server.region ?? '-'} · <Badge size="sm" variant="light">{info.server.status ?? '-'}</Badge>
            </Text>
            <Group>
              {isAdmin && (
                <Button color="orange" variant="light" leftSection={<IconRefresh size={16} />} disabled={busy || info.server.status !== 'running'}
                  onClick={() => { setConfirm(''); setRebootOpen(true); }}>Washa upya server</Button>
              )}
              <Button variant="light" leftSection={<IconLifebuoy size={16} />} onClick={() => setTicketOpen(true)}>Omba msaada wa server</Button>
            </Group>

            <Divider label="Domains kwenye server hii" labelPosition="left" />
            {info.domains.length === 0
              ? <Text size="sm" c="dimmed">Hakuna domain iliyounganishwa bado.</Text>
              : (
                <Table.ScrollContainer minWidth={640}>
                  <Table striped highlightOnHover>
                    <Table.Thead><Table.Tr><Table.Th>#</Table.Th><Table.Th>Domain</Table.Th><Table.Th>Inaelekea (IP)</Table.Th><Table.Th>Usajili</Table.Th><Table.Th>Inaisha</Table.Th><Table.Th /></Table.Tr></Table.Thead>
                    <Table.Tbody>
                      {info.domains.map((d, i) => (
                        <Table.Tr key={d.name}>
                          <Table.Td>{i + 1}</Table.Td>
                          <Table.Td><Text fw={600} size="sm">{d.name}</Text></Table.Td>
                          <Table.Td><Text size="sm">{d.apex_ips.join(', ') || '-'}</Text></Table.Td>
                          <Table.Td>{d.registered ? <Badge size="sm" variant="light" color={d.registration_status === 'active' ? 'green' : 'gray'}>{d.registration_status}</Badge> : <Text size="xs" c="dimmed">Nje ya mfumo</Text>}</Table.Td>
                          <Table.Td><Text size="sm">{d.expires_at ?? '-'}</Text></Table.Td>
                          <Table.Td><Button size="compact-xs" variant="light" leftSection={<IconSettings size={14} />} onClick={() => setDnsFor({ id: d.id, name: d.name, registered_domain_id: d.registered_domain_id })}>Simamia</Button></Table.Td>
                        </Table.Tr>
                      ))}
                    </Table.Tbody>
                  </Table>
                </Table.ScrollContainer>
              )}

            {isAdmin && (
              <>
                <Divider label="Ongeza domain" labelPosition="left" />
                {added ? (
                  <Stack>
                    <Alert color="green" title={`${added.domain} imeongezwa`}>
                      {added.pointed ? `Records ${added.records_created} zimeundwa.` : 'Zone imeundwa bila records. Itaonekana kwenye jedwali ikishaelekezwa kwenye server hii.'}
                    </Alert>
                    <NameserverCard nameservers={added.nameservers ?? LINODE_NAMESERVERS} />
                    <Group><Button variant="default" onClick={() => setAdded(null)}>Ongeza nyingine</Button></Group>
                  </Stack>
                ) : (
                  <Stack>
                    <TextInput label="Jina la domain" placeholder="mfano: biashara.co.tz" value={domain} onChange={(e) => setDomain(e.currentTarget.value)} />
                    <TextInput label="Barua pepe ya mawasiliano (SOA)" value={soa} onChange={(e) => setSoa(e.currentTarget.value)} />
                    <Select label="TTL" data={ttlOptions(DOMAIN_TTLS)} value={ttl} onChange={(v) => setTtl(v ?? '0')} allowDeselect={false} />
                    <Checkbox label="Elekeza kwenye server hii (A + www)" checked={pointToServer} onChange={(e) => setPointToServer(e.currentTarget.checked)} />
                    <Paper withBorder p="sm">
                      <Text size="sm" fw={600}>Vitakavyoundwa</Text>
                      <Text size="sm">Zone ya domain <Code>{domain.trim().toLowerCase() || 'biashara.co.tz'}</Code>{pointToServer ? '' : ' - bila records'}</Text>
                      {pointToServer && (<>
                        <Text size="sm">A <Code>{domain.trim().toLowerCase() || 'biashara.co.tz'}</Code> &rarr; <Code>{info.server.ip ?? '-'}</Code></Text>
                        <Text size="sm">A <Code>www.{domain.trim().toLowerCase() || 'biashara.co.tz'}</Code> &rarr; <Code>{info.server.ip ?? '-'}</Code></Text>
                      </>)}
                    </Paper>
                    <Group><Button loading={request.isPending} disabled={!domain.trim()} onClick={() => request.mutate()}>Ongeza domain</Button></Group>
                    <Text size="xs" c="dimmed">Domain itaongezwa mara moja. Baada ya hapo weka nameservers za Linode kwa msajili wa domain.</Text>
                  </Stack>
                )}
              </>
            )}
            {info.requests.length > 0 && (
              <Stack gap={4}>
                {info.requests.map((r) => (
                  <Group key={r.id} justify="space-between" wrap="nowrap">
                    <Text size="sm">{r.domain}{r.note ? <Text span size="xs" c="dimmed"> · {r.note}</Text> : null}</Text>
                    <Badge color={reqColor[r.status]} variant="light" size="sm">{reqLabel[r.status]}</Badge>
                  </Group>
                ))}
              </Stack>
            )}
          </Stack>
        </Paper>
      )}

      {dnsFor && info && <DnsDrawer sid={id} domain={dnsFor} isAdmin={isAdmin} serverIp={info.server.ip} onClose={() => setDnsFor(null)} />}

      <Modal opened={rebootOpen} onClose={() => setRebootOpen(false)} title="Washa upya server" zIndex={400}>
        <Stack>
          <Alert color="orange">Server itazimwa na kuwashwa upya; tovuti zitakuwa hazipatikani kwa dakika 1-2.</Alert>
          <TextInput label={`Andika jina la server (${server.name}) kuthibitisha`} value={confirm} onChange={(e) => setConfirm(e.currentTarget.value)} />
          <Group justify="flex-end">
            <Button variant="default" onClick={() => setRebootOpen(false)}>Ghairi</Button>
            <Button color="orange" loading={reboot.isPending} disabled={confirm !== server.name} onClick={() => reboot.mutate()}>Washa upya</Button>
          </Group>
        </Stack>
      </Modal>

      <Modal opened={ticketOpen} onClose={() => setTicketOpen(false)} title="Omba msaada wa server" zIndex={400}>
        <Stack>
          <Text size="sm" c="dimmed">Tutafungua tiketi yenye taarifa za server ({server.name}). Unaweza kuongeza maelezo.</Text>
          <Textarea minRows={3} maxLength={5000} placeholder="Elezea tatizo (si lazima)" value={ticketMsg} onChange={(e) => setTicketMsg(e.currentTarget.value)} />
          <Group justify="flex-end">
            <Button variant="default" onClick={() => setTicketOpen(false)}>Ghairi</Button>
            <Button loading={ticket.isPending} onClick={() => ticket.mutate()}>Tuma</Button>
          </Group>
        </Stack>
      </Modal>
    </Stack>
  );
}
