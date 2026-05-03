import { useState } from 'react';
import {
  Title, Tabs, Stack, Group, Button, Badge, Text, Paper, SimpleGrid,
  ActionIcon, Tooltip, Modal, TextInput, Select, Textarea, Progress,
  ThemeIcon, Divider, Checkbox, NumberInput, Switch, Loader, Center,
  SegmentedControl,
} from '@mantine/core';
import { DatePickerInput } from '@mantine/dates';
import { useDisclosure } from '@mantine/hooks';
import { useForm } from '@mantine/form';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { notifications } from '@mantine/notifications';
import {
  IconBrandInstagram, IconBrandFacebook, IconBrandTiktok, IconBrandX,
  IconBrandThreads, IconPlus, IconCheck, IconX, IconEdit, IconTrash,
  IconPencil, IconLink, IconTarget, IconCalendarWeek, IconPhoto,
} from '@tabler/icons-react';
import dayjs from 'dayjs';
import isoWeek from 'dayjs/plugin/isoWeek';
import {
  getPosts, createPost, updatePost, deletePost,
  updateDesign, updateContent, togglePlatform,
  getTargets, upsertTarget, deleteTarget,
  getWeeklySummary,
  PLATFORMS, POST_TYPES, TYPE_LABELS, PLATFORM_LABELS, DAY_NAMES,
  type SocialPost, type SocialTarget, type Platform, type PostType,
} from '../api/socialMedia';
import { getUsers } from '../api/users';
import { usePermissions } from '../hooks/usePermissions';

dayjs.extend(isoWeek);

const PLATFORM_ICONS: Record<Platform, React.ReactNode> = {
  instagram: <IconBrandInstagram size={16} />,
  facebook:  <IconBrandFacebook size={16} />,
  threads:   <IconBrandThreads size={16} />,
  x:         <IconBrandX size={16} />,
  tiktok:    <IconBrandTiktok size={16} />,
};

const PLATFORM_COLORS: Record<Platform, string> = {
  instagram: 'pink', facebook: 'blue', threads: 'dark', x: 'dark', tiktok: 'red',
};

const STATUS_COLOR: Record<string, string> = {
  planned: 'gray', designing: 'yellow', content_ready: 'blue',
  partial_posted: 'orange', posted: 'green',
};

const STATUS_LABEL: Record<string, string> = {
  planned: 'Planned', designing: 'Designing', content_ready: 'Content Ready',
  partial_posted: 'Partial', posted: 'Posted',
};

function weekStart(offset = 0) {
  return dayjs().isoWeekday(1).add(offset * 7, 'day').format('YYYY-MM-DD');
}

export default function SocialMedia() {
  const { can } = usePermissions();
  const [tab, setTab] = useState<string | null>('board');

  return (
    <Stack>
      <Title order={2}>Social Media</Title>
      <Tabs value={tab} onChange={setTab}>
        <Tabs.List mb="md">
          <Tabs.Tab value="board" leftSection={<IconCalendarWeek size={16} />}>Board</Tabs.Tab>
          <Tabs.Tab value="targets" leftSection={<IconTarget size={16} />}>Targets</Tabs.Tab>
        </Tabs.List>
        <Tabs.Panel value="board"><BoardTab can={can} /></Tabs.Panel>
        <Tabs.Panel value="targets"><TargetsTab can={can} /></Tabs.Panel>
      </Tabs>
    </Stack>
  );
}

// ── Board Tab ────────────────────────────────────────────────────────────────

function BoardTab({ can }: { can: (p: string) => boolean }) {
  const qc = useQueryClient();
  const [weekOffset, setWeekOffset] = useState(0);
  const [selected, setSelected] = useState<SocialPost | null>(null);
  const [postModal, { open: openPost, close: closePost }] = useDisclosure(false);
  const [detailModal, { open: openDetail, close: closeDetail }] = useDisclosure(false);

  const ws = weekStart(weekOffset);
  const we = dayjs(ws).add(6, 'day').format('YYYY-MM-DD');

  const { data, isLoading } = useQuery({
    queryKey: ['social-posts', ws],
    queryFn: () => getPosts({ week_start: ws }),
  });
  const posts: SocialPost[] = data?.data?.data ?? [];

  const days = Array.from({ length: 7 }, (_, i) => dayjs(ws).add(i, 'day'));

  const deleteMutation = useMutation({
    mutationFn: deletePost,
    onSuccess: () => { qc.invalidateQueries({ queryKey: ['social-posts'] }); notifications.show({ message: 'Post deleted.', color: 'green' }); },
  });

  return (
    <Stack>
      <Group justify="space-between">
        <Group gap="xs">
          <ActionIcon variant="default" onClick={() => setWeekOffset(o => o - 1)}>‹</ActionIcon>
          <Text fw={500} size="sm">{dayjs(ws).format('D MMM')} – {dayjs(we).format('D MMM YYYY')}</Text>
          <ActionIcon variant="default" onClick={() => setWeekOffset(o => o + 1)}>›</ActionIcon>
          {weekOffset !== 0 && <Button size="xs" variant="light" onClick={() => setWeekOffset(0)}>This week</Button>}
        </Group>
        {can('social.create') && (
          <Button leftSection={<IconPlus size={16} />} onClick={openPost}>New Post</Button>
        )}
      </Group>

      {isLoading ? <Center py="xl"><Loader /></Center> : (
        <SimpleGrid cols={{ base: 1, sm: 2, md: 3, lg: 7 }} spacing="xs">
          {days.map(day => {
            const dayPosts = posts.filter(p => p.scheduled_date === day.format('YYYY-MM-DD'));
            const isToday = day.format('YYYY-MM-DD') === dayjs().format('YYYY-MM-DD');
            return (
              <Stack key={day.format('YYYY-MM-DD')} gap="xs">
                <Paper
                  p="xs"
                  withBorder
                  style={{
                    borderColor: isToday ? 'var(--mantine-color-blue-5)' : undefined,
                    background: isToday ? 'var(--mantine-color-blue-0)' : undefined,
                  }}
                >
                  <Text size="xs" fw={700} c={isToday ? 'blue' : 'dimmed'} ta="center">{day.format('ddd')}</Text>
                  <Text size="xs" ta="center" c="dimmed">{day.format('D')}</Text>
                </Paper>
                {dayPosts.map(post => (
                  <PostCard
                    key={post.id}
                    post={post}
                    canUpdate={can('social.update')}
                    canDelete={can('social.delete')}
                    onOpen={() => { setSelected(post); openDetail(); }}
                    onDelete={() => deleteMutation.mutate(post.id)}
                  />
                ))}
                {dayPosts.length === 0 && (
                  <Text size="xs" c="dimmed" ta="center" py="xs">—</Text>
                )}
              </Stack>
            );
          })}
        </SimpleGrid>
      )}

      <PostFormModal opened={postModal} onClose={closePost} />
      {selected && (
        <PostDetailModal
          post={selected}
          opened={detailModal}
          onClose={() => { closeDetail(); setSelected(null); }}
          canUpdate={can('social.update')}
          onUpdated={(p) => setSelected(p)}
        />
      )}
    </Stack>
  );
}

function PostCard({ post, canUpdate, canDelete, onOpen, onDelete }: {
  post: SocialPost; canUpdate: boolean; canDelete: boolean;
  onOpen: () => void; onDelete: () => void;
}) {
  const postedCount = PLATFORMS.filter(p => post.platforms[p]?.posted).length;
  return (
    <Paper withBorder p="xs" style={{ cursor: 'pointer' }} onClick={onOpen}>
      <Stack gap={4}>
        <Group justify="space-between" wrap="nowrap">
          <Badge size="xs" color={STATUS_COLOR[post.status]} variant="light">
            {STATUS_LABEL[post.status]}
          </Badge>
          {canDelete && (
            <ActionIcon size="xs" color="red" variant="subtle"
              onClick={(e) => { e.stopPropagation(); onDelete(); }}>
              <IconTrash size={12} />
            </ActionIcon>
          )}
        </Group>
        <Text size="xs" fw={600} lineClamp={2}>{post.title}</Text>
        <Badge size="xs" variant="dot" color="gray">{TYPE_LABELS[post.type]}</Badge>
        <Group gap={2} mt={2}>
          {PLATFORMS.map(p => (
            <Tooltip key={p} label={PLATFORM_LABELS[p]} position="top" withArrow>
              <ThemeIcon
                size="xs"
                variant={post.platforms[p]?.posted ? 'filled' : 'light'}
                color={post.platforms[p]?.posted ? PLATFORM_COLORS[p] : 'gray'}
              >
                {PLATFORM_ICONS[p]}
              </ThemeIcon>
            </Tooltip>
          ))}
          <Text size="xs" c="dimmed" ml="auto">{postedCount}/5</Text>
        </Group>
      </Stack>
    </Paper>
  );
}

function PostFormModal({ opened, onClose }: { opened: boolean; onClose: () => void }) {
  const qc = useQueryClient();
  const { data: usersData } = useQuery({ queryKey: ['users'], queryFn: () => getUsers({ per_page: 100 }) });
  const users = (usersData?.data?.data ?? []).map((u: any) => ({ value: u.id, label: u.name }));

  const form = useForm({
    initialValues: {
      title: '', type: 'general' as PostType,
      scheduled_date: new Date() as Date | null,
      brief: '', assigned_designer_id: '', assigned_creator_id: '',
    },
    validate: {
      title: v => !v.trim() ? 'Title required' : null,
      scheduled_date: v => !v ? 'Date required' : null,
    },
  });

  const mutation = useMutation({
    mutationFn: createPost,
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['social-posts'] });
      qc.invalidateQueries({ queryKey: ['social-weekly-summary'] });
      notifications.show({ message: 'Post scheduled.', color: 'green' });
      form.reset();
      onClose();
    },
  });

  return (
    <Modal opened={opened} onClose={onClose} title="Schedule New Post" centered size="md">
      <form onSubmit={form.onSubmit(v => mutation.mutate({
        title: v.title, type: v.type,
        scheduled_date: dayjs(v.scheduled_date!).format('YYYY-MM-DD'),
        brief: v.brief || undefined,
        assigned_designer_id: v.assigned_designer_id || undefined,
        assigned_creator_id:  v.assigned_creator_id  || undefined,
      }))}>
        <Stack>
          <TextInput label="Title" required {...form.getInputProps('title')} />
          <Select label="Type" required data={POST_TYPES.map(t => ({ value: t, label: TYPE_LABELS[t] }))} {...form.getInputProps('type')} />
          <DatePickerInput label="Scheduled Date" required {...form.getInputProps('scheduled_date')} />
          <Textarea label="Brief / Instructions" minRows={2} {...form.getInputProps('brief')} />
          <Select label="Assigned Designer" data={users} clearable searchable {...form.getInputProps('assigned_designer_id')} />
          <Select label="Assigned Content Creator" data={users} clearable searchable {...form.getInputProps('assigned_creator_id')} />
          <Group justify="flex-end">
            <Button variant="default" onClick={onClose}>Cancel</Button>
            <Button type="submit" loading={mutation.isPending}>Schedule</Button>
          </Group>
        </Stack>
      </form>
    </Modal>
  );
}

function PostDetailModal({ post, opened, onClose, canUpdate, onUpdated }: {
  post: SocialPost; opened: boolean; onClose: () => void;
  canUpdate: boolean; onUpdated: (p: SocialPost) => void;
}) {
  const qc = useQueryClient();
  const [caption, setCaption] = useState(post.caption ?? '');
  const [designUrl, setDesignUrl] = useState(post.design_file_url ?? '');
  const [designNotes, setDesignNotes] = useState(post.design_notes ?? '');
  const [platformUrls, setPlatformUrls] = useState<Record<string, string>>(
    Object.fromEntries(PLATFORMS.map(p => [p, post.platforms[p]?.post_url ?? '']))
  );

  const invalidate = () => qc.invalidateQueries({ queryKey: ['social-posts'] });

  const designMutation = useMutation({
    mutationFn: (status: 'pending' | 'in_progress' | 'done') =>
      updateDesign(post.id, { design_status: status, design_notes: designNotes, design_file_url: designUrl }),
    onSuccess: r => { invalidate(); onUpdated(r.data.data); notifications.show({ message: 'Design updated.', color: 'green' }); },
  });

  const contentMutation = useMutation({
    mutationFn: (status: 'pending' | 'ready') =>
      updateContent(post.id, { content_status: status, caption }),
    onSuccess: r => { invalidate(); onUpdated(r.data.data); notifications.show({ message: 'Content updated.', color: 'green' }); },
  });

  const platformMutation = useMutation({
    mutationFn: ({ platform, posted }: { platform: Platform; posted: boolean }) =>
      togglePlatform(post.id, platform, { posted, post_url: platformUrls[platform] || undefined }),
    onSuccess: r => { invalidate(); onUpdated(r.data.data); },
  });

  return (
    <Modal opened={opened} onClose={onClose} title={post.title} size="lg" centered>
      <Stack gap="md">
        <Group>
          <Badge color={STATUS_COLOR[post.status]}>{STATUS_LABEL[post.status]}</Badge>
          <Badge variant="dot" color="gray">{TYPE_LABELS[post.type]}</Badge>
          <Text size="xs" c="dimmed">{dayjs(post.scheduled_date).format('D MMM YYYY')}</Text>
        </Group>

        {post.brief && <Text size="sm" c="dimmed" style={{ fontStyle: 'italic' }}>{post.brief}</Text>}

        <Divider label="Design" labelPosition="left" />
        <Stack gap="xs">
          <Group>
            <Text size="sm" fw={500}>Designer: {post.assigned_designer?.name ?? '—'}</Text>
            <Badge size="sm" color={post.design_status === 'done' ? 'green' : post.design_status === 'in_progress' ? 'yellow' : 'gray'}>
              {post.design_status === 'done' ? 'Done' : post.design_status === 'in_progress' ? 'In Progress' : 'Pending'}
            </Badge>
          </Group>
          {canUpdate && (
            <>
              <TextInput
                size="xs" label="Design file URL" placeholder="https://drive.google.com/..."
                value={designUrl} onChange={e => setDesignUrl(e.currentTarget.value)}
                leftSection={<IconPhoto size={14} />}
              />
              <Textarea
                size="xs" label="Design notes" minRows={1}
                value={designNotes} onChange={e => setDesignNotes(e.currentTarget.value)}
              />
              <Group gap="xs">
                <Button size="xs" variant="light" color="yellow" loading={designMutation.isPending}
                  onClick={() => designMutation.mutate('in_progress')}>In Progress</Button>
                <Button size="xs" variant="light" color="green" loading={designMutation.isPending}
                  onClick={() => designMutation.mutate('done')}>Mark Done</Button>
              </Group>
            </>
          )}
        </Stack>

        <Divider label="Content" labelPosition="left" />
        <Stack gap="xs">
          <Group>
            <Text size="sm" fw={500}>Creator: {post.assigned_creator?.name ?? '—'}</Text>
            <Badge size="sm" color={post.content_status === 'ready' ? 'green' : 'gray'}>
              {post.content_status === 'ready' ? 'Ready' : 'Pending'}
            </Badge>
          </Group>
          {canUpdate && (
            <>
              <Textarea
                size="xs" label="Caption" minRows={3} placeholder="Write caption..."
                value={caption} onChange={e => setCaption(e.currentTarget.value)}
              />
              <Group gap="xs">
                <Button size="xs" variant="light" color="green" loading={contentMutation.isPending}
                  onClick={() => contentMutation.mutate('ready')}>Mark Ready</Button>
              </Group>
            </>
          )}
        </Stack>

        <Divider label="Platform Posting" labelPosition="left" />
        <Stack gap="xs">
          {PLATFORMS.map(platform => {
            const row = post.platforms[platform];
            return (
              <Group key={platform} justify="space-between" wrap="nowrap">
                <Group gap="xs" style={{ flex: 1 }}>
                  <ThemeIcon size="sm" color={PLATFORM_COLORS[platform]} variant={row?.posted ? 'filled' : 'light'}>
                    {PLATFORM_ICONS[platform]}
                  </ThemeIcon>
                  <Text size="sm">{PLATFORM_LABELS[platform]}</Text>
                  {row?.posted && row.posted_at && (
                    <Text size="xs" c="dimmed">{dayjs(row.posted_at).format('D MMM HH:mm')}</Text>
                  )}
                </Group>
                {canUpdate && (
                  <Group gap="xs" wrap="nowrap">
                    <TextInput
                      size="xs" placeholder="Post URL" style={{ width: 180 }}
                      value={platformUrls[platform]}
                      onChange={e => setPlatformUrls(prev => ({ ...prev, [platform]: e.currentTarget.value }))}
                      leftSection={<IconLink size={12} />}
                    />
                    <Switch
                      checked={row?.posted ?? false}
                      onChange={e => platformMutation.mutate({ platform, posted: e.currentTarget.checked })}
                      color={PLATFORM_COLORS[platform]}
                    />
                  </Group>
                )}
              </Group>
            );
          })}
        </Stack>
      </Stack>
    </Modal>
  );
}

// ── Targets Tab ──────────────────────────────────────────────────────────────

function TargetsTab({ can }: { can: (p: string) => boolean }) {
  const qc = useQueryClient();
  const [weekOffset, setWeekOffset] = useState(0);
  const ws = weekStart(weekOffset);
  const [targetModal, { open: openTarget, close: closeTarget }] = useDisclosure(false);
  const [editTarget, setEditTarget] = useState<SocialTarget | null>(null);

  const { data: targetsData } = useQuery({ queryKey: ['social-targets'], queryFn: getTargets });
  const { data: summaryData, isLoading } = useQuery({
    queryKey: ['social-weekly-summary', ws],
    queryFn: () => getWeeklySummary(ws),
  });

  const targets: SocialTarget[] = targetsData?.data?.data ?? [];
  const summary = summaryData?.data ?? [];

  const deleteMutation = useMutation({
    mutationFn: deleteTarget,
    onSuccess: () => { qc.invalidateQueries({ queryKey: ['social-targets'] }); qc.invalidateQueries({ queryKey: ['social-weekly-summary'] }); },
  });

  const we = dayjs(ws).add(6, 'day').format('YYYY-MM-DD');

  return (
    <Stack>
      <Group justify="space-between">
        <Group gap="xs">
          <ActionIcon variant="default" onClick={() => setWeekOffset(o => o - 1)}>‹</ActionIcon>
          <Text fw={500} size="sm">{dayjs(ws).format('D MMM')} – {dayjs(we).format('D MMM YYYY')}</Text>
          <ActionIcon variant="default" onClick={() => setWeekOffset(o => o + 1)}>›</ActionIcon>
          {weekOffset !== 0 && <Button size="xs" variant="light" onClick={() => setWeekOffset(0)}>This week</Button>}
        </Group>
        {can('social.targets') && (
          <Button size="sm" leftSection={<IconPlus size={16} />} onClick={() => { setEditTarget(null); openTarget(); }}>
            Set Target
          </Button>
        )}
      </Group>

      {isLoading ? <Center py="xl"><Loader /></Center> : summary.length === 0 ? (
        <Text c="dimmed" ta="center" py="xl">No targets set yet. Add targets to start tracking.</Text>
      ) : (
        <Stack gap="md">
          {summary.map((entry, i) => (
            <Paper key={i} withBorder p="md" radius="md">
              <Stack gap="sm">
                <Group justify="space-between">
                  <Group gap="sm">
                    <ThemeIcon size="md" variant="light" color={entry.target.metric === 'designs' ? 'violet' : 'teal'}>
                      {entry.target.metric === 'designs' ? <IconPhoto size={16} /> : <IconBrandInstagram size={16} />}
                    </ThemeIcon>
                    <div>
                      <Text fw={600} size="sm">{entry.target.user?.name ?? '—'}</Text>
                      <Text size="xs" c="dimmed">
                        {entry.target.metric === 'designs' ? 'Designs' : 'Platform Posts'} ·{' '}
                        {entry.target.daily_target}/day on {entry.target.active_days.map(d => DAY_NAMES[d]).join(', ')}
                      </Text>
                    </div>
                  </Group>
                  <Group gap="xs">
                    <Badge size="lg" color={entry.percent >= 100 ? 'green' : entry.percent >= 50 ? 'yellow' : 'red'} variant="light">
                      {entry.weekly_achieved}/{entry.weekly_target}
                    </Badge>
                    {can('social.targets') && (
                      <>
                        <ActionIcon size="sm" variant="subtle" onClick={() => { setEditTarget(entry.target); openTarget(); }}>
                          <IconEdit size={14} />
                        </ActionIcon>
                        <ActionIcon size="sm" variant="subtle" color="red" onClick={() => deleteMutation.mutate(entry.target.id)}>
                          <IconTrash size={14} />
                        </ActionIcon>
                      </>
                    )}
                  </Group>
                </Group>

                <Progress value={entry.percent} color={entry.percent >= 100 ? 'green' : entry.percent >= 50 ? 'yellow' : 'red'} size="sm" />
                <Text size="xs" c="dimmed" ta="right">{entry.percent}% of weekly target ({entry.weekly_target})</Text>

                {/* Per-day breakdown */}
                <SimpleGrid cols={7} spacing="xs">
                  {entry.daily.map(day => (
                    <Stack key={day.date} gap={2} align="center">
                      <Text size="xs" c="dimmed" fw={500}>{day.day_name}</Text>
                      <ThemeIcon
                        size="sm"
                        variant={!day.is_active ? 'subtle' : day.met ? 'filled' : 'light'}
                        color={!day.is_active ? 'gray' : day.met ? 'green' : day.achieved > 0 ? 'yellow' : 'red'}
                      >
                        {!day.is_active ? <IconX size={10} /> : day.met ? <IconCheck size={10} /> : <Text size={9}>{day.achieved}</Text>}
                      </ThemeIcon>
                      {day.is_active && (
                        <Text size={9} c="dimmed">{day.achieved}/{day.target}</Text>
                      )}
                    </Stack>
                  ))}
                </SimpleGrid>
              </Stack>
            </Paper>
          ))}
        </Stack>
      )}

      <TargetFormModal
        opened={targetModal}
        onClose={closeTarget}
        existing={editTarget}
      />
    </Stack>
  );
}

function TargetFormModal({ opened, onClose, existing }: {
  opened: boolean; onClose: () => void; existing: SocialTarget | null;
}) {
  const qc = useQueryClient();
  const { data: usersData } = useQuery({ queryKey: ['users'], queryFn: () => getUsers({ per_page: 100 }) });
  const users = (usersData?.data?.data ?? []).map((u: any) => ({ value: u.id, label: u.name }));

  const form = useForm({
    initialValues: {
      user_id:        existing?.user?.id ?? '',
      metric:         (existing?.metric ?? 'designs') as 'designs' | 'posts',
      daily_target:   existing?.daily_target ?? 1,
      weekly_target:  existing?.weekly_target ?? 5,
      active_days:    existing?.active_days ?? [1, 2, 3, 4, 5],
      effective_from: existing?.effective_from ? new Date(existing.effective_from) : new Date() as Date | null,
    },
    validate: {
      user_id:    v => !v ? 'Select a team member' : null,
      active_days: v => v.length === 0 ? 'Select at least one day' : null,
    },
  });

  // Sync when existing changes
  if (existing && form.values.user_id !== existing.user?.id) {
    form.setValues({
      user_id:        existing.user?.id ?? '',
      metric:         existing.metric,
      daily_target:   existing.daily_target,
      weekly_target:  existing.weekly_target,
      active_days:    existing.active_days,
      effective_from: new Date(existing.effective_from),
    });
  }

  const mutation = useMutation({
    mutationFn: upsertTarget,
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['social-targets'] });
      qc.invalidateQueries({ queryKey: ['social-weekly-summary'] });
      notifications.show({ message: 'Target saved.', color: 'green' });
      form.reset();
      onClose();
    },
  });

  const toggleDay = (day: number) => {
    const current = form.values.active_days;
    form.setFieldValue('active_days',
      current.includes(day) ? current.filter(d => d !== day) : [...current, day].sort()
    );
  };

  return (
    <Modal opened={opened} onClose={onClose} title={existing ? 'Edit Target' : 'Set Target'} centered size="sm">
      <form onSubmit={form.onSubmit(v => mutation.mutate({
        user_id:        v.user_id,
        metric:         v.metric,
        daily_target:   v.daily_target,
        weekly_target:  v.weekly_target,
        active_days:    v.active_days,
        effective_from: dayjs(v.effective_from!).format('YYYY-MM-DD'),
      }))}>
        <Stack gap="md">
          <Select label="Team Member" required data={users} searchable {...form.getInputProps('user_id')} />

          <div>
            <Text size="sm" fw={500} mb={4}>Tracking metric</Text>
            <SegmentedControl
              fullWidth
              data={[
                { value: 'designs', label: 'Designs completed' },
                { value: 'posts',   label: 'Platform posts' },
              ]}
              {...form.getInputProps('metric')}
            />
          </div>

          <div>
            <Text size="sm" fw={500} mb={6}>Active days</Text>
            <Group gap="xs">
              {[1, 2, 3, 4, 5, 6, 7].map(day => (
                <Checkbox
                  key={day}
                  label={DAY_NAMES[day]}
                  checked={form.values.active_days.includes(day)}
                  onChange={() => toggleDay(day)}
                />
              ))}
            </Group>
            {form.errors.active_days && <Text size="xs" c="red" mt={4}>{form.errors.active_days}</Text>}
          </div>

          <NumberInput
            label="Daily target"
            description="Expected completions per active day"
            min={1} max={100}
            {...form.getInputProps('daily_target')}
          />

          <NumberInput
            label="Weekly target"
            description="Total expected per week"
            min={1} max={500}
            {...form.getInputProps('weekly_target')}
          />

          <DatePickerInput label="Effective from" required {...form.getInputProps('effective_from')} />

          <Group justify="flex-end">
            <Button variant="default" onClick={onClose}>Cancel</Button>
            <Button type="submit" loading={mutation.isPending}>Save Target</Button>
          </Group>
        </Stack>
      </form>
    </Modal>
  );
}
