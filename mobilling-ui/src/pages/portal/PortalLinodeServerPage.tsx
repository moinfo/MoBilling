import { useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { Paper, Title, Table, Modal, Stack, Text, Alert, TextInput, Group, Button, Badge, Divider, Textarea, Loader, Drawer, Select, NumberInput, Checkbox, Code, CopyButton, ActionIcon, Center } from '@mantine/core';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { notifications } from '@mantine/notifications';
import { IconRefresh, IconLifebuoy, IconArrowLeft, IconSettings, IconPlus, IconEdit, IconCopy, IconCheck, IconLock, IconWorldWww } from '@tabler/icons-react';
import { useAuth } from '../../context/AuthContext';
import {
  getPortalLinodeServer, portalLinodeReboot, portalLinodeRequestDomain, portalLinodeSupportTicket, getPortalDnsRecords, addPortalDnsRecord, updatePortalDnsRecord,
  portalDnsPointToServer, PortalDnsRecord, PortalDnsRecordInput, PortalAddDomainResult,
} from '../../api/portal';
import { DOMAIN_TTLS, RECORD_TTLS, RECORD_TYPES, LINODE_NAMESERVERS } from '../../api/linode';

const errMsg = (e: any): string =>
  e?.response?.data?.message || (e?.response?.data?.errors ? Object.values(e.response.data.errors).flat().join(' ') : null) || e?.message || 'Something went wrong';

const ttlLabel = (s: number) => (s === 0 ? 'Default' : s >= 86400 ? `siku ${s / 86400}` : s >= 3600 ? `saa ${s / 3600}` : `sek ${s}`);
const ttlOptions = (list: number[]) => list.map((t) => ({ value: String(t), label: ttlLabel(t) }));

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

function RecordModal({ sid, did, record, onClose, onSaved }: { sid: string; did: string; record: PortalDnsRecord | null; onClose: () => void; onSaved: () => void }) {
  const [type, setType] = useState<string>(record?.type ?? 'A');
  const [name, setName] = useState(record?.name ?? '');
  const [target, setTarget] = useState(record?.target ?? '');
  const [ttl, setTtl] = useState<string>(String(record?.ttl_sec ?? 0));
  const [priority, setPriority] = useState<number | string>(record?.priority ?? 10);
  const [weight, setWeight] = useState<number | string>(record?.weight ?? 0);
  const [port, setPort] = useState<number | string>(record?.port ?? 0);
  const [tag, setTag] = useState<string>(record?.tag ?? 'issue');
  const [error, setError] = useState<string | null>(null);
  const m = useMutation({
    mutationFn: () => {
      const p: PortalDnsRecordInput = { type, name: name.trim(), target: target.trim(), ttl_sec: Number(ttl),
        ...(type === 'MX' || type === 'SRV' ? { priority: Number(priority) } : {}),
        ...(type === 'SRV' ? { weight: Number(weight), port: Number(port) } : {}),
        ...(type === 'CAA' ? { tag } : {}) };
      return record ? updatePortalDnsRecord(sid, did, record.id, p) : addPortalDnsRecord(sid, did, p);
    },
    onSuccess: (r) => { notifications.show({ color: 'green', message: r.data.message }); onSaved(); onClose(); },
    onError: (e) => setError(errMsg(e)),
  });
  return (
    <Modal opened onClose={onClose} title={record ? 'Hariri record' : 'Ongeza record'} zIndex={500}>
      <Stack>
        {error && <Alert color="red">{error}</Alert>}
        <Select label="Aina" data={RECORD_TYPES} value={type} onChange={(v) => setType(v ?? 'A')} allowDeselect={false} disabled={!!record} />
        <TextInput label="Jina" description="Acha wazi kwa domain kuu. CNAME haiwezi kuwa kwenye domain kuu." placeholder="www" value={name} onChange={(e) => setName(e.currentTarget.value)} />
        <TextInput label="Target" placeholder={type === 'A' ? '1.2.3.4' : type === 'CNAME' || type === 'MX' ? 'host.example.com' : ''} value={target} onChange={(e) => setTarget(e.currentTarget.value)} required />
        {(type === 'MX' || type === 'SRV') && <NumberInput label="Priority (0-255)" min={0} max={255} value={priority} onChange={setPriority} />}
        {type === 'SRV' && (<Group grow><NumberInput label="Weight" min={0} max={65535} value={weight} onChange={setWeight} /><NumberInput label="Port" min={0} max={65535} value={port} onChange={setPort} /></Group>)}
        {type === 'CAA' && <Select label="Tag" data={['issue', 'issuewild', 'iodef']} value={tag} onChange={(v) => setTag(v ?? 'issue')} allowDeselect={false} />}
        <Select label="TTL" data={ttlOptions(RECORD_TTLS)} value={ttl} onChange={(v) => setTtl(v ?? '0')} allowDeselect={false} />
        <Button loading={m.isPending} disabled={!target.trim()} onClick={() => { setError(null); m.mutate(); }}>Hifadhi</Button>
      </Stack>
    </Modal>
  );
}

function DnsDrawer({ sid, domain, isAdmin, serverIp, onClose }: { sid: string; domain: { id: string; name: string; registered_domain_id: string | null }; isAdmin: boolean; serverIp: string | null; onClose: () => void }) {
  const qc = useQueryClient();
  const navigate = useNavigate();
  const key = ['portal-dns', sid, domain.id];
  const { data, isLoading, isError, error } = useQuery({ queryKey: key, queryFn: () => getPortalDnsRecords(sid, domain.id), retry: false });
  const rows = data?.data?.data ?? [];
  const [editing, setEditing] = useState<PortalDnsRecord | 'new' | null>(null);
  const point = useMutation({
    mutationFn: () => portalDnsPointToServer(sid, domain.id),
    onSuccess: (r) => { notifications.show({ color: 'green', message: r.data.message }); qc.invalidateQueries({ queryKey: key }); qc.invalidateQueries({ queryKey: ['portal-linode', sid] }); },
    onError: (e) => notifications.show({ color: 'red', message: errMsg(e) }),
  });
  return (
    <Drawer opened onClose={onClose} title={`DNS - ${domain.name}`} position="right" size="xl" zIndex={400}>
      <Stack>
        <NameserverCard nameservers={data?.data?.meta?.nameservers ?? LINODE_NAMESERVERS} />
        {domain.registered_domain_id && (
          <Alert color="blue">Domain hii imesajiliwa kupitia sisi. <Button size="compact-xs" variant="subtle" onClick={() => navigate(`/portal/domains/${domain.registered_domain_id}`)}>Simamia usajili na nameservers</Button></Alert>
        )}
        <Text size="xs" c="dimmed">Records za NS na SOA zinasimamiwa na Linode na haziwezi kubadilishwa. Unaweza kuongeza au kuhariri records, lakini si kuzifuta.</Text>
        {isAdmin && (
          <Group>
            <Button size="xs" leftSection={<IconPlus size={14} />} onClick={() => setEditing('new')}>Ongeza record</Button>
            <Button size="xs" variant="light" leftSection={<IconWorldWww size={14} />} loading={point.isPending} disabled={!serverIp}
              onClick={() => { if (window.confirm(`Weka records za A na www zielekee ${serverIp}?`)) point.mutate(); }}>Elekeza kwenye server hii</Button>
          </Group>
        )}
        {isLoading ? <Center><Loader /></Center> : isError ? <Alert color="red">{errMsg(error)}</Alert> : !rows.length ? <Text c="dimmed">Hakuna records.</Text> : (
          <Table.ScrollContainer minWidth={480}>
            <Table verticalSpacing="xs">
              <Table.Thead><Table.Tr><Table.Th>Aina</Table.Th><Table.Th>Jina</Table.Th><Table.Th>Target</Table.Th><Table.Th>TTL</Table.Th><Table.Th /></Table.Tr></Table.Thead>
              <Table.Tbody>
                {rows.map((r) => (
                  <Table.Tr key={r.id}>
                    <Table.Td><Badge variant="light">{r.type}</Badge></Table.Td>
                    <Table.Td>{r.name || '@'}</Table.Td>
                    <Table.Td style={{ wordBreak: 'break-all' }}>{r.target}{r.priority != null && r.type === 'MX' ? ` (prio ${r.priority})` : ''}</Table.Td>
                    <Table.Td>{ttlLabel(r.ttl_sec)}</Table.Td>
                    <Table.Td>
                      {r.locked ? <IconLock size={14} /> : isAdmin && <ActionIcon variant="light" aria-label="Hariri" onClick={() => setEditing(r)}><IconEdit size={14} /></ActionIcon>}
                    </Table.Td>
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        )}
      </Stack>
      {editing && <RecordModal sid={sid} did={domain.id} record={editing === 'new' ? null : editing} onClose={() => setEditing(null)} onSaved={() => qc.invalidateQueries({ queryKey: key })} />}
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
