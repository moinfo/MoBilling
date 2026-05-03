import { useState, useEffect } from 'react';
import {
  Title, Tabs, Stack, Group, Button, Badge, Text, Paper, SimpleGrid,
  ActionIcon, Tooltip, Modal, TextInput, Select, Textarea, Progress,
  ThemeIcon, Divider, Checkbox, NumberInput, Switch, Loader, Center,
  SegmentedControl, SegmentedControlItem,
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
  IconEye, IconShieldCheck, IconVideo, IconDeviceMobile, IconLayoutColumns,
  IconHash, IconClock,
} from '@tabler/icons-react';
import dayjs from 'dayjs';
import isoWeek from 'dayjs/plugin/isoWeek';
import {
  getPosts, createPost, updatePost, deletePost,
  updateDesign, updateContent, togglePlatform,
  getTargets, upsertTarget, deleteTarget,
  getWeeklySummary,
  PLATFORMS, POST_TYPES, POST_FORMATS, FORMAT_LABELS, FORMAT_COLORS,
  TYPE_LABELS, PLATFORM_LABELS, DAY_NAMES,
  type SocialPost, type SocialTarget, type Platform, type PostType, type PostFormat,
} from '../api/socialMedia';
import { getUsers } from '../api/users';
import { usePermissions } from '../hooks/usePermissions';
import { useAuth } from '../context/AuthContext';

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

const FORMAT_ICONS: Record<PostFormat, React.ReactNode> = {
  feed_post: <IconPhoto size={11} />,
  reel:      <IconVideo size={11} />,
  story:     <IconDeviceMobile size={11} />,
  carousel:  <IconLayoutColumns size={11} />,
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

function formatTime(t: string | null) {
  if (!t) return null;
  const [h, m] = t.split(':').map(Number);
  const ampm = h >= 12 ? 'PM' : 'AM';
  const h12 = h % 12 || 12;
  return `${h12}:${String(m).padStart(2, '0')} ${ampm}`;
}

export default function SocialMedia() {
  const { can } = usePermissions();
  const [tab, setTab] = useState<string | null>('board');

  return (
    <Stack>
      <Title order={2}>Social Media</Title>
      <Tabs value={tab} onChange={setTab} keepMounted={false}>
        <Tabs.List mb="md">
          <Tabs.Tab value="board"    leftSection={<IconCalendarWeek size={16} />}>Board</Tabs.Tab>
          <Tabs.Tab value="designer" leftSection={<IconPhoto size={16} />}>Design Work</Tabs.Tab>
          <Tabs.Tab value="creator"  leftSection={<IconPencil size={16} />}>Content & Posting</Tabs.Tab>
          <Tabs.Tab value="qa"       leftSection={<IconShieldCheck size={16} />}>QA Review</Tabs.Tab>
          <Tabs.Tab value="targets"  leftSection={<IconTarget size={16} />}>Targets</Tabs.Tab>
        </Tabs.List>
        <Tabs.Panel value="board">   <BoardTab can={can} /></Tabs.Panel>
        <Tabs.Panel value="designer"><DesignerTab can={can} /></Tabs.Panel>
        <Tabs.Panel value="creator"> <CreatorTab can={can} /></Tabs.Panel>
        <Tabs.Panel value="qa">      <QATab can={can} /></Tabs.Panel>
        <Tabs.Panel value="targets"> <TargetsTab can={can} /></Tabs.Panel>
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

  // Filters (applied client-side on the week's data)
  const [filterFormat, setFilterFormat] = useState<string | null>(null);
  const [filterType,   setFilterType]   = useState<string | null>(null);
  const [filterStatus, setFilterStatus] = useState<string | null>(null);

  const ws = weekStart(weekOffset);
  const we = dayjs(ws).add(6, 'day').format('YYYY-MM-DD');

  const { data, isLoading } = useQuery({
    queryKey: ['social-posts', ws],
    queryFn: () => getPosts({ week_start: ws }),
  });
  const allPosts: SocialPost[] = data?.data?.data ?? [];
  const posts = allPosts.filter(p =>
    (!filterFormat || p.post_format === filterFormat) &&
    (!filterType   || p.type === filterType) &&
    (!filterStatus || p.status === filterStatus)
  );

  const days = Array.from({ length: 7 }, (_, i) => dayjs(ws).add(i, 'day'));

  const deleteMutation = useMutation({
    mutationFn: deletePost,
    onSuccess: () => { qc.invalidateQueries({ queryKey: ['social-posts'] }); notifications.show({ message: 'Post deleted.', color: 'green' }); },
  });

  const hasFilters = filterFormat || filterType || filterStatus;

  return (
    <Stack>
      {/* Navigation row */}
      <Group justify="space-between" wrap="nowrap">
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

      {/* Filter row */}
      <Group gap="xs" wrap="wrap">
        <Select
          size="xs" placeholder="All formats" clearable
          data={POST_FORMATS.map(f => ({ value: f, label: FORMAT_LABELS[f] }))}
          value={filterFormat} onChange={setFilterFormat}
          style={{ width: 130 }}
        />
        <Select
          size="xs" placeholder="All types" clearable
          data={POST_TYPES.map(t => ({ value: t, label: TYPE_LABELS[t] }))}
          value={filterType} onChange={setFilterType}
          style={{ width: 160 }}
        />
        <Select
          size="xs" placeholder="All statuses" clearable
          data={Object.entries(STATUS_LABEL).map(([v, l]) => ({ value: v, label: l }))}
          value={filterStatus} onChange={setFilterStatus}
          style={{ width: 140 }}
        />
        {hasFilters && (
          <Button size="xs" variant="subtle" color="gray"
            onClick={() => { setFilterFormat(null); setFilterType(null); setFilterStatus(null); }}>
            Clear filters
          </Button>
        )}
        <Text size="xs" c="dimmed" ml="auto">
          {posts.length} post{posts.length !== 1 ? 's' : ''} this week
        </Text>
      </Group>

      {isLoading ? <Center py="xl"><Loader /></Center> : (
        <SimpleGrid cols={{ base: 1, sm: 2, md: 3, lg: 7 }} spacing="xs">
          {days.map(day => {
            const dayPosts = posts.filter(p => p.scheduled_date === day.format('YYYY-MM-DD'));
            const isToday = day.format('YYYY-MM-DD') === dayjs().format('YYYY-MM-DD');
            return (
              <Stack key={day.format('YYYY-MM-DD')} gap="xs">
                <Paper
                  p="xs" withBorder
                  style={{
                    borderColor: isToday ? 'var(--mantine-color-blue-5)' : undefined,
                    background: isToday ? 'var(--mantine-color-blue-0)' : undefined,
                  }}
                >
                  <Text size="xs" fw={700} c={isToday ? 'blue' : 'dimmed'} ta="center">{day.format('ddd')}</Text>
                  <Text size="xs" ta="center" c="dimmed">{day.format('D')}</Text>
                </Paper>
                {dayPosts
                  .sort((a, b) => (a.scheduled_time ?? '00:00').localeCompare(b.scheduled_time ?? '00:00'))
                  .map(post => (
                    <PostCard
                      key={post.id} post={post}
                      canUpdate={can('social.update')} canDelete={can('social.delete')}
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
          post={selected} opened={detailModal}
          onClose={() => { closeDetail(); setSelected(null); }}
          canUpdate={can('social.update')}
          onUpdated={p => setSelected(p)}
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
  const timeStr = formatTime(post.scheduled_time);

  return (
    <Paper withBorder p="xs" style={{ cursor: 'pointer' }} onClick={onOpen}>
      <Stack gap={5}>
        {/* Format + delete row */}
        <Group justify="space-between" wrap="nowrap" gap={4}>
          <Group gap={4} wrap="nowrap">
            <Badge
              size="xs"
              color={FORMAT_COLORS[post.post_format]}
              variant="filled"
              leftSection={FORMAT_ICONS[post.post_format]}
            >
              {FORMAT_LABELS[post.post_format]}
            </Badge>
            {post.media_type === 'video' && (
              <Tooltip label="Video" position="top" withArrow>
                <ThemeIcon size={16} color="grape" variant="light" radius="xl">
                  <IconVideo size={9} />
                </ThemeIcon>
              </Tooltip>
            )}
          </Group>
          {canDelete && (
            <ActionIcon size="xs" color="red" variant="subtle"
              onClick={e => { e.stopPropagation(); onDelete(); }}>
              <IconTrash size={12} />
            </ActionIcon>
          )}
        </Group>

        {/* Status */}
        <Badge size="xs" color={STATUS_COLOR[post.status]} variant="light" style={{ alignSelf: 'flex-start' }}>
          {STATUS_LABEL[post.status]}
        </Badge>

        {/* Title */}
        <Text size="xs" fw={600} lineClamp={2}>{post.title}</Text>

        {/* Meta: type + time */}
        <Group gap={4} wrap="nowrap">
          <Text size="xs" c="dimmed" style={{ flex: 1 }} lineClamp={1}>{TYPE_LABELS[post.type]}</Text>
          {timeStr && (
            <Group gap={2} wrap="nowrap">
              <IconClock size={10} style={{ color: 'var(--mantine-color-dimmed)' }} />
              <Text size="xs" c="dimmed">{timeStr}</Text>
            </Group>
          )}
        </Group>

        {/* Designer / Creator avatars */}
        {(post.assigned_designer || post.assigned_creator) && (
          <Group gap={4} wrap="nowrap">
            {post.assigned_designer && (
              <Tooltip label={`Designer: ${post.assigned_designer.name}`} position="top" withArrow>
                <ThemeIcon size={18} color="violet" variant="light" radius="xl">
                  <IconPhoto size={10} />
                </ThemeIcon>
              </Tooltip>
            )}
            {post.assigned_creator && (
              <Tooltip label={`Creator: ${post.assigned_creator.name}`} position="top" withArrow>
                <ThemeIcon size={18} color="teal" variant="light" radius="xl">
                  <IconPencil size={10} />
                </ThemeIcon>
              </Tooltip>
            )}
          </Group>
        )}

        {/* Platform icons */}
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

function PostFormModal({ opened, onClose, existing }: {
  opened: boolean; onClose: () => void; existing?: SocialPost;
}) {
  const qc = useQueryClient();
  const { data: usersData } = useQuery({ queryKey: ['users'], queryFn: () => getUsers({ per_page: 100 }) });
  const users = (usersData?.data?.data ?? []).map((u: any) => ({ value: u.id, label: u.name }));

  const [scheduledTime, setScheduledTime] = useState(existing?.scheduled_time ?? '');

  const form = useForm({
    initialValues: {
      title:               existing?.title ?? '',
      type:                (existing?.type ?? 'general') as PostType,
      post_format:         (existing?.post_format ?? 'feed_post') as PostFormat,
      media_type:          existing?.media_type ?? 'image',
      scheduled_date:      existing?.scheduled_date ? new Date(existing.scheduled_date) : new Date() as Date | null,
      brief:               existing?.brief ?? '',
      hashtags:            existing?.hashtags ?? '',
      assigned_designer_id: existing?.assigned_designer?.id ?? '',
      assigned_creator_id:  existing?.assigned_creator?.id  ?? '',
    },
    validate: {
      title:          v => !v.trim() ? 'Title required' : null,
      scheduled_date: v => !v ? 'Date required' : null,
    },
  });

  const isEdit = !!existing;

  const mutation = useMutation({
    mutationFn: (vals: ReturnType<typeof form.getValues>) => {
      const payload = {
        title:               vals.title,
        type:                vals.type,
        post_format:         vals.post_format,
        media_type:          vals.media_type as 'image' | 'video',
        scheduled_date:      dayjs(vals.scheduled_date!).format('YYYY-MM-DD'),
        scheduled_time:      scheduledTime || undefined,
        brief:               vals.brief || undefined,
        hashtags:            vals.hashtags || undefined,
        assigned_designer_id: vals.assigned_designer_id || undefined,
        assigned_creator_id:  vals.assigned_creator_id  || undefined,
      };
      return isEdit ? updatePost(existing!.id, payload) : createPost(payload);
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['social-posts'] });
      qc.invalidateQueries({ queryKey: ['social-weekly-summary'] });
      notifications.show({ message: isEdit ? 'Post updated.' : 'Post scheduled.', color: 'green' });
      form.reset();
      setScheduledTime('');
      onClose();
    },
  });

  const formatData: SegmentedControlItem[] = POST_FORMATS.map(f => ({
    value: f,
    label: FORMAT_LABELS[f],
  }));

  return (
    <Modal opened={opened} onClose={onClose} title={isEdit ? 'Edit Post' : 'Schedule New Post'} centered size="md">
      <form onSubmit={form.onSubmit(v => mutation.mutate(v))}>
        <Stack>
          <TextInput label="Title" required {...form.getInputProps('title')} />

          <Select
            label="Post type" required
            data={POST_TYPES.map(t => ({ value: t, label: TYPE_LABELS[t] }))}
            {...form.getInputProps('type')}
          />

          <div>
            <Text size="sm" fw={500} mb={4}>Format</Text>
            <SegmentedControl fullWidth data={formatData} {...form.getInputProps('post_format')} />
          </div>

          <div>
            <Text size="sm" fw={500} mb={4}>Media type</Text>
            <SegmentedControl
              fullWidth
              data={[
                { value: 'image', label: '📷 Image / Graphic' },
                { value: 'video', label: '🎬 Video / Animation' },
              ]}
              {...form.getInputProps('media_type')}
            />
          </div>

          <Group grow>
            <DatePickerInput label="Scheduled date" required {...form.getInputProps('scheduled_date')} />
            <TextInput
              label="Time (optional)"
              placeholder="09:00"
              type="time"
              value={scheduledTime}
              onChange={e => setScheduledTime(e.currentTarget.value)}
              leftSection={<IconClock size={14} />}
            />
          </Group>

          <Textarea label="Brief / Instructions for designer" minRows={2} {...form.getInputProps('brief')} />

          <TextInput
            label="Hashtags"
            placeholder="#moinfotech #tech #innovation"
            leftSection={<IconHash size={14} />}
            {...form.getInputProps('hashtags')}
          />

          <Select label="Assigned Designer" data={users} clearable searchable {...form.getInputProps('assigned_designer_id')} />
          <Select label="Assigned Content Creator" data={users} clearable searchable {...form.getInputProps('assigned_creator_id')} />

          <Group justify="flex-end">
            <Button variant="default" onClick={onClose}>Cancel</Button>
            <Button type="submit" loading={mutation.isPending}>{isEdit ? 'Update' : 'Schedule'}</Button>
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
  const [caption,     setCaption]     = useState(post.caption ?? '');
  const [hashtags,    setHashtags]    = useState(post.hashtags ?? '');
  const [designUrl,   setDesignUrl]   = useState(post.design_file_url ?? '');
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
      updateContent(post.id, { content_status: status, caption, hashtags }),
    onSuccess: r => { invalidate(); onUpdated(r.data.data); notifications.show({ message: 'Content updated.', color: 'green' }); },
  });

  const platformMutation = useMutation({
    mutationFn: ({ platform, posted }: { platform: Platform; posted: boolean }) =>
      togglePlatform(post.id, platform, { posted, post_url: platformUrls[platform] || undefined }),
    onSuccess: r => { invalidate(); onUpdated(r.data.data); },
  });

  const timeStr = formatTime(post.scheduled_time);

  return (
    <Modal opened={opened} onClose={onClose} title={post.title} size="lg" centered>
      <Stack gap="md">
        {/* Header badges */}
        <Group gap="xs" wrap="wrap">
          <Badge color={FORMAT_COLORS[post.post_format]} leftSection={FORMAT_ICONS[post.post_format]}>
            {FORMAT_LABELS[post.post_format]}
          </Badge>
          <Badge color={post.media_type === 'video' ? 'grape' : 'blue'} variant="light">
            {post.media_type === 'video' ? '🎬 Video' : '📷 Image'}
          </Badge>
          <Badge color={STATUS_COLOR[post.status]}>{STATUS_LABEL[post.status]}</Badge>
          <Badge variant="dot" color="gray">{TYPE_LABELS[post.type]}</Badge>
          <Text size="xs" c="dimmed">
            {dayjs(post.scheduled_date).format('D MMM YYYY')}
            {timeStr ? ` at ${timeStr}` : ''}
          </Text>
        </Group>

        {post.brief && <Text size="sm" c="dimmed" style={{ fontStyle: 'italic' }}>{post.brief}</Text>}

        {/* Design section */}
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
                size="xs" label="Design file URL (Google Drive, Canva, Figma…)"
                placeholder="https://drive.google.com/…"
                value={designUrl} onChange={e => setDesignUrl(e.currentTarget.value)}
                leftSection={<IconLink size={14} />}
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
          {post.design_file_url && (
            <Button
              size="xs" variant="subtle" component="a"
              href={post.design_file_url} target="_blank" rel="noopener noreferrer"
              leftSection={<IconLink size={12} />}
            >
              View Design File
            </Button>
          )}
        </Stack>

        {/* Content section */}
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
                size="xs" label="Caption" minRows={3} placeholder="Write caption…"
                value={caption} onChange={e => setCaption(e.currentTarget.value)}
              />
              <TextInput
                size="xs" label="Hashtags" placeholder="#moinfotech #tech"
                leftSection={<IconHash size={12} />}
                value={hashtags} onChange={e => setHashtags(e.currentTarget.value)}
              />
              <Group gap="xs">
                <Button size="xs" variant="light" color="green" loading={contentMutation.isPending}
                  onClick={() => contentMutation.mutate('ready')}>Mark Ready</Button>
              </Group>
            </>
          )}
          {!canUpdate && post.caption && (
            <Text size="sm" style={{ whiteSpace: 'pre-wrap' }}>{post.caption}</Text>
          )}
          {!canUpdate && post.hashtags && (
            <Text size="sm" c="blue">{post.hashtags}</Text>
          )}
        </Stack>

        {/* Platform posting */}
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
                {!canUpdate && row?.post_url && (
                  <Button
                    size="xs" variant="subtle" component="a"
                    href={row.post_url} target="_blank" rel="noopener noreferrer"
                    leftSection={<IconLink size={12} />}
                  >
                    View
                  </Button>
                )}
              </Group>
            );
          })}
        </Stack>
      </Stack>
    </Modal>
  );
}

// ── Designer Tab ─────────────────────────────────────────────────────────────

function DesignerTab({ can }: { can: (p: string) => boolean }) {
  const { user } = useAuth();
  const [weekOffset, setWeekOffset] = useState(0);
  const ws = weekStart(weekOffset);
  const we = dayjs(ws).add(6, 'day').format('YYYY-MM-DD');

  const { data, isLoading } = useQuery({
    queryKey: ['social-posts-designer', ws],
    queryFn: () => getPosts({ week_start: ws }),
  });

  const allPosts: SocialPost[] = data?.data?.data ?? [];
  const posts = allPosts.filter(p =>
    !p.assigned_designer || p.assigned_designer.id === user?.id
  );

  const pending    = posts.filter(p => p.design_status === 'pending');
  const inProgress = posts.filter(p => p.design_status === 'in_progress');
  const done       = posts.filter(p => p.design_status === 'done');

  const [selected, setSelected] = useState<SocialPost | null>(null);
  const [detailModal, { open: openDetail, close: closeDetail }] = useDisclosure(false);

  return (
    <Stack>
      <Group justify="space-between">
        <Group gap="xs">
          <ActionIcon variant="default" onClick={() => setWeekOffset(o => o - 1)}>‹</ActionIcon>
          <Text fw={500} size="sm">{dayjs(ws).format('D MMM')} – {dayjs(we).format('D MMM YYYY')}</Text>
          <ActionIcon variant="default" onClick={() => setWeekOffset(o => o + 1)}>›</ActionIcon>
          {weekOffset !== 0 && <Button size="xs" variant="light" onClick={() => setWeekOffset(0)}>This week</Button>}
        </Group>
        <Group gap="sm">
          <Badge color="gray"   variant="light">{pending.length} Pending</Badge>
          <Badge color="yellow" variant="light">{inProgress.length} In Progress</Badge>
          <Badge color="green"  variant="light">{done.length} Done</Badge>
        </Group>
      </Group>

      {isLoading ? <Center py="xl"><Loader /></Center> : (
        <SimpleGrid cols={{ base: 1, md: 3 }} spacing="md">
          {[
            { label: 'Pending Design', color: 'gray',   items: pending },
            { label: 'In Progress',    color: 'yellow', items: inProgress },
            { label: 'Design Done',    color: 'green',  items: done },
          ].map(({ label, color, items }) => (
            <Stack key={label} gap="xs">
              <Group gap="xs">
                <Badge color={color} variant="filled" size="sm">{label}</Badge>
                <Text size="xs" c="dimmed">({items.length})</Text>
              </Group>
              {items.length === 0
                ? <Text size="xs" c="dimmed" ta="center" py="md">Nothing here</Text>
                : items.map(post => (
                  <Paper key={post.id} withBorder p="sm" style={{ cursor: 'pointer' }}
                    onClick={() => { setSelected(post); openDetail(); }}>
                    <Stack gap={5}>
                      <Group gap={4} wrap="nowrap">
                        <Badge size="xs" color={FORMAT_COLORS[post.post_format]} variant="filled"
                          leftSection={FORMAT_ICONS[post.post_format]}>
                          {FORMAT_LABELS[post.post_format]}
                        </Badge>
                        {post.media_type === 'video' && (
                          <Badge size="xs" color="grape" variant="light" leftSection={<IconVideo size={9} />}>
                            Video
                          </Badge>
                        )}
                      </Group>
                      <Text size="sm" fw={600} lineClamp={2}>{post.title}</Text>
                      <Text size="xs" c="dimmed">
                        {dayjs(post.scheduled_date).format('D MMM')}
                        {post.scheduled_time ? ` at ${formatTime(post.scheduled_time)}` : ''}
                        {' · '}{TYPE_LABELS[post.type]}
                      </Text>
                      {post.brief && (
                        <Text size="xs" c="blue" lineClamp={2}>📋 {post.brief}</Text>
                      )}
                      {post.design_notes && <Text size="xs" c="orange" lineClamp={1}>📝 {post.design_notes}</Text>}
                      {post.design_file_url && (
                        <Text size="xs" c="green" fw={500}>✓ File uploaded</Text>
                      )}
                    </Stack>
                  </Paper>
                ))
              }
            </Stack>
          ))}
        </SimpleGrid>
      )}

      {selected && (
        <PostDetailModal
          post={selected} opened={detailModal}
          onClose={() => { closeDetail(); setSelected(null); }}
          canUpdate={can('social.update')}
          onUpdated={p => setSelected(p)}
        />
      )}
    </Stack>
  );
}

// ── Content Creator Tab ───────────────────────────────────────────────────────

function CreatorTab({ can }: { can: (p: string) => boolean }) {
  const { user } = useAuth();
  const [weekOffset, setWeekOffset] = useState(0);
  const ws = weekStart(weekOffset);
  const we = dayjs(ws).add(6, 'day').format('YYYY-MM-DD');

  const { data, isLoading } = useQuery({
    queryKey: ['social-posts-creator', ws],
    queryFn: () => getPosts({ week_start: ws }),
  });

  const allPosts: SocialPost[] = data?.data?.data ?? [];
  const posts = allPosts.filter(p =>
    !p.assigned_creator || p.assigned_creator.id === user?.id
  );

  const needsCaption = posts.filter(p => p.design_status === 'done' && p.content_status === 'pending');
  const readyToPost  = posts.filter(p => p.content_status === 'ready' && p.status !== 'posted');
  const fullyPosted  = posts.filter(p => p.status === 'posted');

  const [selected, setSelected] = useState<SocialPost | null>(null);
  const [detailModal, { open: openDetail, close: closeDetail }] = useDisclosure(false);

  const renderPostItem = (post: SocialPost) => (
    <Paper key={post.id} withBorder p="sm" style={{ cursor: 'pointer' }}
      onClick={() => { setSelected(post); openDetail(); }}>
      <Stack gap={5}>
        <Group gap={4} wrap="nowrap">
          <Badge size="xs" color={FORMAT_COLORS[post.post_format]} variant="filled"
            leftSection={FORMAT_ICONS[post.post_format]}>
            {FORMAT_LABELS[post.post_format]}
          </Badge>
          {post.media_type === 'video' && (
            <Badge size="xs" color="grape" variant="light" leftSection={<IconVideo size={9} />}>Video</Badge>
          )}
        </Group>
        <Text size="sm" fw={600} lineClamp={2}>{post.title}</Text>
        <Text size="xs" c="dimmed">
          {dayjs(post.scheduled_date).format('D MMM')}
          {post.scheduled_time ? ` at ${formatTime(post.scheduled_time)}` : ''}
        </Text>
        {post.caption && (
          <Text size="xs" c="dimmed" lineClamp={2} style={{ fontStyle: 'italic' }}>"{post.caption}"</Text>
        )}
        {post.hashtags && (
          <Text size="xs" c="blue" lineClamp={1}>{post.hashtags}</Text>
        )}
        <Group gap={2} mt={2}>
          {PLATFORMS.map(p => (
            <ThemeIcon key={p} size="xs"
              variant={post.platforms[p]?.posted ? 'filled' : 'light'}
              color={post.platforms[p]?.posted ? PLATFORM_COLORS[p] : 'gray'}>
              {PLATFORM_ICONS[p]}
            </ThemeIcon>
          ))}
          <Text size="xs" c="dimmed" ml="auto">
            {PLATFORMS.filter(p => post.platforms[p]?.posted).length}/5
          </Text>
        </Group>
      </Stack>
    </Paper>
  );

  return (
    <Stack>
      <Group justify="space-between">
        <Group gap="xs">
          <ActionIcon variant="default" onClick={() => setWeekOffset(o => o - 1)}>‹</ActionIcon>
          <Text fw={500} size="sm">{dayjs(ws).format('D MMM')} – {dayjs(we).format('D MMM YYYY')}</Text>
          <ActionIcon variant="default" onClick={() => setWeekOffset(o => o + 1)}>›</ActionIcon>
          {weekOffset !== 0 && <Button size="xs" variant="light" onClick={() => setWeekOffset(0)}>This week</Button>}
        </Group>
        <Group gap="sm">
          <Badge color="blue"   variant="light">{needsCaption.length} Need Caption</Badge>
          <Badge color="orange" variant="light">{readyToPost.length} Ready to Post</Badge>
          <Badge color="green"  variant="light">{fullyPosted.length} Fully Posted</Badge>
        </Group>
      </Group>

      {isLoading ? <Center py="xl"><Loader /></Center> : (
        <SimpleGrid cols={{ base: 1, md: 3 }} spacing="md">
          {[
            { label: 'Write Caption',        color: 'blue',   items: needsCaption },
            { label: 'Ready to Post',         color: 'orange', items: readyToPost },
            { label: 'All Platforms Posted',  color: 'green',  items: fullyPosted },
          ].map(({ label, color, items }) => (
            <Stack key={label} gap="xs">
              <Group gap="xs">
                <Badge color={color} variant="filled" size="sm">{label}</Badge>
                <Text size="xs" c="dimmed">({items.length})</Text>
              </Group>
              {items.length === 0
                ? <Text size="xs" c="dimmed" ta="center" py="md">Nothing here</Text>
                : items.map(renderPostItem)
              }
            </Stack>
          ))}
        </SimpleGrid>
      )}

      {selected && (
        <PostDetailModal
          post={selected} opened={detailModal}
          onClose={() => { closeDetail(); setSelected(null); }}
          canUpdate={can('social.update')}
          onUpdated={p => setSelected(p)}
        />
      )}
    </Stack>
  );
}

// ── QA Review Tab ─────────────────────────────────────────────────────────────

function QATab({ can }: { can: (p: string) => boolean }) {
  const [weekOffset, setWeekOffset] = useState(0);
  const ws = weekStart(weekOffset);
  const we = dayjs(ws).add(6, 'day').format('YYYY-MM-DD');

  const { data, isLoading } = useQuery({
    queryKey: ['social-posts-qa', ws],
    queryFn: () => getPosts({ week_start: ws }),
  });

  const posts: SocialPost[] = (data?.data?.data ?? [])
    .sort((a: SocialPost, b: SocialPost) => a.scheduled_date.localeCompare(b.scheduled_date));

  const totalPlatformSlots = posts.length * PLATFORMS.length;
  const postedSlots = posts.reduce((sum, p) =>
    sum + PLATFORMS.filter(pl => p.platforms[pl]?.posted).length, 0
  );
  const coveragePercent = totalPlatformSlots > 0
    ? Math.round((postedSlots / totalPlatformSlots) * 100)
    : 0;

  const notPosted  = posts.filter(p => p.status !== 'posted');
  const allPosted  = posts.filter(p => p.status === 'posted');

  const [selected, setSelected] = useState<SocialPost | null>(null);
  const [detailModal, { open: openDetail, close: closeDetail }] = useDisclosure(false);

  return (
    <Stack>
      <Group justify="space-between">
        <Group gap="xs">
          <ActionIcon variant="default" onClick={() => setWeekOffset(o => o - 1)}>‹</ActionIcon>
          <Text fw={500} size="sm">{dayjs(ws).format('D MMM')} – {dayjs(we).format('D MMM YYYY')}</Text>
          <ActionIcon variant="default" onClick={() => setWeekOffset(o => o + 1)}>›</ActionIcon>
          {weekOffset !== 0 && <Button size="xs" variant="light" onClick={() => setWeekOffset(0)}>This week</Button>}
        </Group>
        <Group gap="sm">
          <Badge color="blue" variant="light">{posts.length} Posts</Badge>
          <Badge
            color={coveragePercent === 100 ? 'green' : coveragePercent >= 60 ? 'yellow' : 'red'}
            variant="light"
          >
            {postedSlots}/{totalPlatformSlots} platform posts ({coveragePercent}%)
          </Badge>
        </Group>
      </Group>

      {/* Per-platform coverage summary */}
      <Paper withBorder p="md" radius="md">
        <Text fw={600} size="sm" mb="sm">Platform Coverage This Week</Text>
        <SimpleGrid cols={{ base: 2, sm: 5 }} spacing="sm">
          {PLATFORMS.map(platform => {
            const postedCount = posts.filter(p => p.platforms[platform]?.posted).length;
            const pct = posts.length > 0 ? Math.round((postedCount / posts.length) * 100) : 0;
            return (
              <Stack key={platform} gap={4} align="center">
                <ThemeIcon
                  size="lg"
                  color={pct === 100 ? 'green' : pct >= 50 ? 'yellow' : 'red'}
                  variant={pct === 100 ? 'filled' : 'light'}
                >
                  {PLATFORM_ICONS[platform]}
                </ThemeIcon>
                <Text size="xs" fw={500}>{PLATFORM_LABELS[platform]}</Text>
                <Text size="xs" c="dimmed">{postedCount}/{posts.length}</Text>
                <Progress value={pct} size="xs" w="100%"
                  color={pct === 100 ? 'green' : pct >= 50 ? 'yellow' : 'red'} />
              </Stack>
            );
          })}
        </SimpleGrid>
      </Paper>

      {/* Per-post checklist grouped by posted / pending */}
      {isLoading ? <Center py="xl"><Loader /></Center> : posts.length === 0 ? (
        <Text c="dimmed" ta="center" py="xl">No posts scheduled this week.</Text>
      ) : (
        <Stack gap="sm">
          {notPosted.length > 0 && (
            <Stack gap="xs">
              <Text size="xs" fw={600} c="dimmed" tt="uppercase">Needs attention ({notPosted.length})</Text>
              {notPosted.map(post => <QAPostRow key={post.id} post={post} onOpen={() => { setSelected(post); openDetail(); }} />)}
            </Stack>
          )}
          {allPosted.length > 0 && (
            <Stack gap="xs">
              <Text size="xs" fw={600} c="dimmed" tt="uppercase">Completed ({allPosted.length})</Text>
              {allPosted.map(post => <QAPostRow key={post.id} post={post} onOpen={() => { setSelected(post); openDetail(); }} />)}
            </Stack>
          )}
        </Stack>
      )}

      {selected && (
        <PostDetailModal
          post={selected} opened={detailModal}
          onClose={() => { closeDetail(); setSelected(null); }}
          canUpdate={can('social.update')}
          onUpdated={p => setSelected(p)}
        />
      )}
    </Stack>
  );
}

function QAPostRow({ post, onOpen }: { post: SocialPost; onOpen: () => void }) {
  const postedOnAll = PLATFORMS.every(p => post.platforms[p]?.posted);
  const postedCount = PLATFORMS.filter(p => post.platforms[p]?.posted).length;
  const timeStr = formatTime(post.scheduled_time);

  return (
    <Paper withBorder p="sm" style={{ cursor: 'pointer' }} onClick={onOpen}>
      <Group justify="space-between" wrap="nowrap">
        <Group gap="sm" style={{ flex: 1, minWidth: 0 }}>
          <ThemeIcon size="sm" color={postedOnAll ? 'green' : 'orange'} variant="light">
            {postedOnAll ? <IconCheck size={12} /> : <IconEye size={12} />}
          </ThemeIcon>
          <div style={{ minWidth: 0 }}>
            <Group gap={4} mb={2} wrap="nowrap">
              <Text size="sm" fw={500} lineClamp={1}>{post.title}</Text>
              <Badge size="xs" color={FORMAT_COLORS[post.post_format]} variant="light">
                {FORMAT_LABELS[post.post_format]}
              </Badge>
            </Group>
            <Text size="xs" c="dimmed">
              {dayjs(post.scheduled_date).format('ddd D MMM')}
              {timeStr ? ` · ${timeStr}` : ''}
              {' · '}{TYPE_LABELS[post.type]}
            </Text>
          </div>
        </Group>
        <Group gap={4} wrap="nowrap">
          {PLATFORMS.map(p => (
            <Tooltip key={p}
              label={`${PLATFORM_LABELS[p]}: ${post.platforms[p]?.posted ? 'Posted ✓' : 'Not posted'}`}
              position="top" withArrow>
              <ThemeIcon size="xs"
                variant={post.platforms[p]?.posted ? 'filled' : 'light'}
                color={post.platforms[p]?.posted ? PLATFORM_COLORS[p] : 'red'}>
                {post.platforms[p]?.posted ? <IconCheck size={10} /> : <IconX size={10} />}
              </ThemeIcon>
            </Tooltip>
          ))}
          <Text size="xs" c="dimmed" w={30} ta="right">{postedCount}/5</Text>
        </Group>
      </Group>
    </Paper>
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
  const summary = summaryData?.data?.data ?? [];

  const deleteMutation = useMutation({
    mutationFn: deleteTarget,
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['social-targets'] });
      qc.invalidateQueries({ queryKey: ['social-weekly-summary'] });
    },
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
          <Button size="sm" leftSection={<IconPlus size={16} />}
            onClick={() => { setEditTarget(null); openTarget(); }}>
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
                        {entry.target.daily_target}/day on{' '}
                        {entry.target.active_days.map((d: number) => DAY_NAMES[d]).join(', ')}
                      </Text>
                    </div>
                  </Group>
                  <Group gap="xs">
                    <Badge
                      size="lg"
                      color={entry.percent >= 100 ? 'green' : entry.percent >= 50 ? 'yellow' : 'red'}
                      variant="light"
                    >
                      {entry.weekly_achieved}/{entry.weekly_target}
                    </Badge>
                    {can('social.targets') && (
                      <>
                        <ActionIcon size="sm" variant="subtle"
                          onClick={() => { setEditTarget(entry.target); openTarget(); }}>
                          <IconEdit size={14} />
                        </ActionIcon>
                        <ActionIcon size="sm" variant="subtle" color="red"
                          onClick={() => deleteMutation.mutate(entry.target.id)}>
                          <IconTrash size={14} />
                        </ActionIcon>
                      </>
                    )}
                  </Group>
                </Group>

                <Progress
                  value={entry.percent}
                  color={entry.percent >= 100 ? 'green' : entry.percent >= 50 ? 'yellow' : 'red'}
                  size="sm"
                />
                <Text size="xs" c="dimmed" ta="right">
                  {entry.percent}% of weekly target ({entry.weekly_target})
                </Text>

                <SimpleGrid cols={7} spacing="xs">
                  {entry.daily.map((day: any) => (
                    <Stack key={day.date} gap={2} align="center">
                      <Text size="xs" c="dimmed" fw={500}>{day.day_name}</Text>
                      <ThemeIcon
                        size="sm"
                        variant={!day.is_active ? 'subtle' : day.met ? 'filled' : 'light'}
                        color={!day.is_active ? 'gray' : day.met ? 'green' : day.achieved > 0 ? 'yellow' : 'red'}
                      >
                        {!day.is_active
                          ? <IconX size={10} />
                          : day.met
                            ? <IconCheck size={10} />
                            : <Text size={9}>{day.achieved}</Text>
                        }
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

      <TargetFormModal opened={targetModal} onClose={closeTarget} existing={editTarget} />
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
      user_id:     v => !v ? 'Select a team member' : null,
      active_days: v => v.length === 0 ? 'Select at least one day' : null,
    },
  });

  useEffect(() => {
    if (existing) {
      form.setValues({
        user_id:        existing.user?.id ?? '',
        metric:         existing.metric,
        daily_target:   existing.daily_target,
        weekly_target:  existing.weekly_target,
        active_days:    existing.active_days,
        effective_from: new Date(existing.effective_from),
      });
    } else {
      form.reset();
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [existing?.id]);

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
