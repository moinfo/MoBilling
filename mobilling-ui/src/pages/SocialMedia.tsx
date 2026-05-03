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
  IconBrandThreads, IconBrandLinkedin, IconBrandYoutube, IconBrandWhatsapp,
  IconBrandTelegram, IconBrandSnapchat, IconBrandPinterest, IconBrandTwitter,
  IconGlobe, IconPlus, IconCheck, IconX, IconEdit, IconTrash,
  IconPencil, IconLink, IconTarget, IconCalendarWeek, IconPhoto,
  IconEye, IconShieldCheck, IconVideo, IconDeviceMobile, IconLayoutColumns,
  IconHash, IconClock, IconBriefcase, IconAlertTriangle, IconPackage,
  IconSettings, IconToggleLeft, IconToggleRight, IconExternalLink,
} from '@tabler/icons-react';
import dayjs from 'dayjs';
import isoWeek from 'dayjs/plugin/isoWeek';
import {
  getPosts, createPost, updatePost, deletePost,
  updateDesign, updateContent, togglePlatform,
  getTargets, upsertTarget, deleteTarget,
  getWeeklySummary,
  getDesignOrders, createDesignOrder, updateDesignOrder, deleteDesignOrder,
  getSocialPlatforms, createSocialPlatform, updateSocialPlatform, deleteSocialPlatform,
  POST_TYPES, POST_FORMATS, FORMAT_LABELS, FORMAT_COLORS,
  TYPE_LABELS, DAY_NAMES,
  DESIGN_TYPES, DESIGN_TYPE_LABELS, DESIGN_TYPE_COLORS,
  DESIGN_ORDER_STATUSES, DESIGN_ORDER_STATUS_LABELS, DESIGN_ORDER_STATUS_COLORS,
  KNOWN_ICONS, MANTINE_COLORS,
  type SocialPost, type SocialTarget, type PostType, type PostFormat,
  type ClientDesignOrder, type DesignType, type DesignOrderStatus,
  type SocialPlatformConfig,
} from '../api/socialMedia';
import { getClients } from '../api/clients';
import { getUsers } from '../api/users';
import { usePermissions } from '../hooks/usePermissions';
import { useAuth } from '../context/AuthContext';

dayjs.extend(isoWeek);

// Default fallback platforms (used while API loads or if no platforms configured)
const DEFAULT_PLATFORMS: SocialPlatformConfig[] = [
  { id: '1', name: 'instagram', label: 'Instagram', color: 'pink',  icon: 'brand-instagram', profile_url: null, is_active: true, sort_order: 1 },
  { id: '2', name: 'facebook',  label: 'Facebook',  color: 'blue',  icon: 'brand-facebook',  profile_url: null, is_active: true, sort_order: 2 },
  { id: '3', name: 'threads',   label: 'Threads',   color: 'dark',  icon: 'brand-threads',   profile_url: null, is_active: true, sort_order: 3 },
  { id: '4', name: 'x',         label: 'X (Twitter)', color: 'gray', icon: 'brand-x',         profile_url: null, is_active: true, sort_order: 4 },
  { id: '5', name: 'tiktok',    label: 'TikTok',    color: 'red',   icon: 'brand-tiktok',    profile_url: null, is_active: true, sort_order: 5 },
];

function getPlatformIcon(iconName: string, size = 16): React.ReactNode {
  const map: Record<string, React.ReactNode> = {
    'brand-instagram': <IconBrandInstagram size={size} />,
    'brand-facebook':  <IconBrandFacebook  size={size} />,
    'brand-threads':   <IconBrandThreads   size={size} />,
    'brand-x':         <IconBrandX         size={size} />,
    'brand-tiktok':    <IconBrandTiktok    size={size} />,
    'brand-linkedin':  <IconBrandLinkedin  size={size} />,
    'brand-youtube':   <IconBrandYoutube   size={size} />,
    'brand-whatsapp':  <IconBrandWhatsapp  size={size} />,
    'brand-telegram':  <IconBrandTelegram  size={size} />,
    'brand-snapchat':  <IconBrandSnapchat  size={size} />,
    'brand-pinterest': <IconBrandPinterest size={size} />,
    'brand-twitter':   <IconBrandTwitter   size={size} />,
    'globe':           <IconGlobe          size={size} />,
  };
  return map[iconName] ?? <IconGlobe size={size} />;
}

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

// Ordered tab config — permission controls visibility, alignRight pushes to the far end
const SOCIAL_TABS = [
  { value: 'board',          perm: 'social.board',          label: 'Board',             icon: <IconCalendarWeek size={16} /> },
  { value: 'designer',       perm: 'social.design_work',    label: 'Design Work',       icon: <IconPhoto size={16} /> },
  { value: 'creator',        perm: 'social.content',        label: 'Content & Posting', icon: <IconPencil size={16} /> },
  { value: 'qa',             perm: 'social.qa',             label: 'QA Review',         icon: <IconShieldCheck size={16} /> },
  { value: 'client_designs', perm: 'social.client_designs', label: 'Client Designs',    icon: <IconBriefcase size={16} /> },
  { value: 'targets',        perm: 'social.targets',        label: 'Targets',           icon: <IconTarget size={16} /> },
  { value: 'settings',       perm: 'social.settings',       label: 'Platform Settings', icon: <IconSettings size={16} />, alignRight: true },
] as const;

export default function SocialMedia() {
  const { can } = usePermissions();
  const [tab, setTab] = useState<string | null>(null);

  // Auto-select the first tab the user has permission for
  useEffect(() => {
    if (tab) return;
    const first = SOCIAL_TABS.find(t => can(t.perm));
    if (first) setTab(first.value);
  }, [can, tab]);

  const { data: platformsData } = useQuery({
    queryKey: ['social-platforms'],
    queryFn: getSocialPlatforms,
    staleTime: 5 * 60 * 1000,
  });
  const platforms: SocialPlatformConfig[] = platformsData?.data?.data ?? DEFAULT_PLATFORMS;
  const activePlatforms = platforms.filter(p => p.is_active);

  const visibleTabs = SOCIAL_TABS.filter(t => can(t.perm));

  if (visibleTabs.length === 0) {
    return (
      <Stack>
        <Title order={2}>Social Media</Title>
        <Center py="xl">
          <Text c="dimmed">You don't have permission to access any social media tabs.</Text>
        </Center>
      </Stack>
    );
  }

  return (
    <Stack>
      <Title order={2}>Social Media</Title>
      <Tabs value={tab} onChange={setTab} keepMounted={false}>
        <Tabs.List mb="md">
          {SOCIAL_TABS.map(t => !can(t.perm) ? null : (
            <Tabs.Tab key={t.value} value={t.value} leftSection={t.icon}
              ml={'alignRight' in t && t.alignRight ? 'auto' : undefined}>
              {t.label}
            </Tabs.Tab>
          ))}
        </Tabs.List>
        {can('social.board')          && <Tabs.Panel value="board">          <BoardTab    can={can} platforms={activePlatforms} /></Tabs.Panel>}
        {can('social.design_work')    && <Tabs.Panel value="designer">       <DesignerTab can={can} platforms={activePlatforms} /></Tabs.Panel>}
        {can('social.content')        && <Tabs.Panel value="creator">        <CreatorTab  can={can} platforms={activePlatforms} /></Tabs.Panel>}
        {can('social.qa')             && <Tabs.Panel value="qa">             <QATab       can={can} platforms={activePlatforms} /></Tabs.Panel>}
        {can('social.client_designs') && <Tabs.Panel value="client_designs"> <ClientDesignsTab can={can} /></Tabs.Panel>}
        {can('social.targets')        && <Tabs.Panel value="targets">        <TargetsTab  can={can} /></Tabs.Panel>}
        {can('social.settings')       && <Tabs.Panel value="settings">       <PlatformSettingsTab can={can} platforms={platforms} /></Tabs.Panel>}
      </Tabs>
    </Stack>
  );
}

// ── Board Tab ────────────────────────────────────────────────────────────────

function BoardTab({ can, platforms }: { can: (p: string) => boolean; platforms: SocialPlatformConfig[] }) {
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
                      key={post.id} post={post} platforms={platforms}
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
          post={selected} opened={detailModal} platforms={platforms}
          onClose={() => { closeDetail(); setSelected(null); }}
          canUpdate={can('social.update')}
          onUpdated={p => setSelected(p)}
        />
      )}
    </Stack>
  );
}

function PostCard({ post, platforms, canUpdate, canDelete, onOpen, onDelete }: {
  post: SocialPost; platforms: SocialPlatformConfig[]; canUpdate: boolean; canDelete: boolean;
  onOpen: () => void; onDelete: () => void;
}) {
  const postedCount = platforms.filter(p => post.platforms[p.name]?.posted).length;
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

        {/* Platform icons — dynamic */}
        <Group gap={2} mt={2}>
          {platforms.map(p => (
            <Tooltip key={p.name} label={p.label} position="top" withArrow>
              <ThemeIcon
                size="xs"
                variant={post.platforms[p.name]?.posted ? 'filled' : 'light'}
                color={post.platforms[p.name]?.posted ? p.color : 'gray'}
              >
                {getPlatformIcon(p.icon)}
              </ThemeIcon>
            </Tooltip>
          ))}
          <Text size="xs" c="dimmed" ml="auto">{postedCount}/{platforms.length}</Text>
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

function PostDetailModal({ post, opened, onClose, canUpdate, onUpdated, platforms = DEFAULT_PLATFORMS }: {
  post: SocialPost; opened: boolean; onClose: () => void;
  canUpdate: boolean; onUpdated: (p: SocialPost) => void;
  platforms?: SocialPlatformConfig[];
}) {
  const qc = useQueryClient();
  const [caption,     setCaption]     = useState(post.caption ?? '');
  const [hashtags,    setHashtags]    = useState(post.hashtags ?? '');
  const [designUrl,   setDesignUrl]   = useState(post.design_file_url ?? '');
  const [designNotes, setDesignNotes] = useState(post.design_notes ?? '');
  const [platformUrls, setPlatformUrls] = useState<Record<string, string>>(
    Object.fromEntries(platforms.map(p => [p.name, post.platforms[p.name]?.post_url ?? '']))
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

        {/* Platform posting — dynamic */}
        <Divider label="Platform Posting" labelPosition="left" />
        <Stack gap="xs">
          {platforms.map(platform => {
            const row = post.platforms[platform.name];
            return (
              <Group key={platform.name} justify="space-between" wrap="nowrap">
                <Group gap="xs" style={{ flex: 1 }}>
                  <ThemeIcon size="sm" color={platform.color} variant={row?.posted ? 'filled' : 'light'}>
                    {getPlatformIcon(platform.icon)}
                  </ThemeIcon>
                  <div>
                    <Text size="sm">{platform.label}</Text>
                    {platform.profile_url && !row?.posted && (
                      <Text size="xs" c="blue" component="a" href={platform.profile_url} target="_blank" rel="noopener noreferrer">
                        {platform.profile_url.replace('https://', '')}
                      </Text>
                    )}
                  </div>
                  {row?.posted && row.posted_at && (
                    <Text size="xs" c="dimmed">{dayjs(row.posted_at).format('D MMM HH:mm')}</Text>
                  )}
                </Group>
                {canUpdate && (
                  <Group gap="xs" wrap="nowrap">
                    <TextInput
                      size="xs" placeholder="Post URL" style={{ width: 180 }}
                      value={platformUrls[platform.name] ?? ''}
                      onChange={e => setPlatformUrls(prev => ({ ...prev, [platform.name]: e.currentTarget.value }))}
                      leftSection={<IconLink size={12} />}
                    />
                    <Switch
                      checked={row?.posted ?? false}
                      onChange={e => platformMutation.mutate({ platform: platform.name as any, posted: e.currentTarget.checked })}
                      color={platform.color}
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

function DesignerTab({ can, platforms }: { can: (p: string) => boolean; platforms: SocialPlatformConfig[] }) {
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
          post={selected} opened={detailModal} platforms={platforms}
          onClose={() => { closeDetail(); setSelected(null); }}
          canUpdate={can('social.update')}
          onUpdated={p => setSelected(p)}
        />
      )}
    </Stack>
  );
}

// ── Content Creator Tab ───────────────────────────────────────────────────────

function CreatorTab({ can, platforms }: { can: (p: string) => boolean; platforms: SocialPlatformConfig[] }) {
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
          {platforms.map(p => (
            <ThemeIcon key={p.name} size="xs"
              variant={post.platforms[p.name]?.posted ? 'filled' : 'light'}
              color={post.platforms[p.name]?.posted ? p.color : 'gray'}>
              {getPlatformIcon(p.icon)}
            </ThemeIcon>
          ))}
          <Text size="xs" c="dimmed" ml="auto">
            {platforms.filter(p => post.platforms[p.name]?.posted).length}/{platforms.length}
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
          post={selected} opened={detailModal} platforms={platforms}
          onClose={() => { closeDetail(); setSelected(null); }}
          canUpdate={can('social.update')}
          onUpdated={p => setSelected(p)}
        />
      )}
    </Stack>
  );
}

// ── QA Review Tab ─────────────────────────────────────────────────────────────

function QATab({ can, platforms }: { can: (p: string) => boolean; platforms: SocialPlatformConfig[] }) {
  const [weekOffset, setWeekOffset] = useState(0);
  const ws = weekStart(weekOffset);
  const we = dayjs(ws).add(6, 'day').format('YYYY-MM-DD');

  const { data, isLoading } = useQuery({
    queryKey: ['social-posts-qa', ws],
    queryFn: () => getPosts({ week_start: ws }),
  });

  const posts: SocialPost[] = (data?.data?.data ?? [])
    .sort((a: SocialPost, b: SocialPost) => a.scheduled_date.localeCompare(b.scheduled_date));

  const totalPlatformSlots = posts.length * platforms.length;
  const postedSlots = posts.reduce((sum, p) =>
    sum + platforms.filter(pl => p.platforms[pl.name]?.posted).length, 0
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
        <SimpleGrid cols={{ base: 2, sm: Math.min(platforms.length, 6) }} spacing="sm">
          {platforms.map(platform => {
            const postedCount = posts.filter(p => p.platforms[platform.name]?.posted).length;
            const pct = posts.length > 0 ? Math.round((postedCount / posts.length) * 100) : 0;
            return (
              <Stack key={platform.name} gap={4} align="center">
                <ThemeIcon
                  size="lg"
                  color={pct === 100 ? 'green' : pct >= 50 ? 'yellow' : 'red'}
                  variant={pct === 100 ? 'filled' : 'light'}
                >
                  {getPlatformIcon(platform.icon)}
                </ThemeIcon>
                <Text size="xs" fw={500}>{platform.label}</Text>
                {platform.profile_url && (
                  <Text size="xs" c="blue" component="a" href={platform.profile_url} target="_blank"
                    rel="noopener noreferrer" style={{ textDecoration: 'none' }}>
                    Open ↗
                  </Text>
                )}
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
              {notPosted.map(post => <QAPostRow key={post.id} post={post} platforms={platforms} onOpen={() => { setSelected(post); openDetail(); }} />)}
            </Stack>
          )}
          {allPosted.length > 0 && (
            <Stack gap="xs">
              <Text size="xs" fw={600} c="dimmed" tt="uppercase">Completed ({allPosted.length})</Text>
              {allPosted.map(post => <QAPostRow key={post.id} post={post} platforms={platforms} onOpen={() => { setSelected(post); openDetail(); }} />)}
            </Stack>
          )}
        </Stack>
      )}

      {selected && (
        <PostDetailModal
          post={selected} opened={detailModal} platforms={platforms}
          onClose={() => { closeDetail(); setSelected(null); }}
          canUpdate={can('social.update')}
          onUpdated={p => setSelected(p)}
        />
      )}
    </Stack>
  );
}

function QAPostRow({ post, platforms, onOpen }: { post: SocialPost; platforms: SocialPlatformConfig[]; onOpen: () => void }) {
  const postedOnAll = platforms.every(p => post.platforms[p.name]?.posted);
  const postedCount = platforms.filter(p => post.platforms[p.name]?.posted).length;
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
          {platforms.map(p => (
            <Tooltip key={p.name}
              label={`${p.label}: ${post.platforms[p.name]?.posted ? 'Posted ✓' : 'Not posted'}`}
              position="top" withArrow>
              <ThemeIcon size="xs"
                variant={post.platforms[p.name]?.posted ? 'filled' : 'light'}
                color={post.platforms[p.name]?.posted ? p.color : 'red'}>
                {post.platforms[p.name]?.posted ? <IconCheck size={10} /> : <IconX size={10} />}
              </ThemeIcon>
            </Tooltip>
          ))}
          <Text size="xs" c="dimmed" w={30} ta="right">{postedCount}/{platforms.length}</Text>
        </Group>
      </Group>
    </Paper>
  );
}

// ── Platform Settings Tab ─────────────────────────────────────────────────────

function PlatformSettingsTab({ can, platforms }: { can: (p: string) => boolean; platforms: SocialPlatformConfig[] }) {
  const qc = useQueryClient();
  const [modal, { open, close }] = useDisclosure(false);
  const [editing, setEditing] = useState<SocialPlatformConfig | null>(null);

  const deleteMutation = useMutation({
    mutationFn: deleteSocialPlatform,
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['social-platforms'] });
      notifications.show({ message: 'Platform removed.', color: 'green' });
    },
  });

  const toggleActive = useMutation({
    mutationFn: ({ id, is_active }: { id: string; is_active: boolean }) =>
      updateSocialPlatform(id, { is_active }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['social-platforms'] }),
  });

  return (
    <Stack>
      <Group justify="space-between">
        <div>
          <Text fw={600} size="lg">Social Media Platforms</Text>
          <Text size="xs" c="dimmed">Configure which platforms you post to. Active platforms are seeded on every new post.</Text>
        </div>
        {can('social.targets') && (
          <Button leftSection={<IconPlus size={16} />} onClick={() => { setEditing(null); open(); }}>
            Add Platform
          </Button>
        )}
      </Group>

      <Stack gap="xs">
        {platforms.length === 0 && (
          <Text c="dimmed" ta="center" py="xl">No platforms configured.</Text>
        )}
        {[...platforms].sort((a, b) => a.sort_order - b.sort_order).map(platform => (
          <Paper key={platform.id} withBorder p="md" radius="md"
            style={{ opacity: platform.is_active ? 1 : 0.6 }}>
            <Group justify="space-between" wrap="nowrap">
              <Group gap="md" wrap="nowrap" style={{ flex: 1, minWidth: 0 }}>
                <ThemeIcon
                  size="xl" color={platform.color}
                  variant={platform.is_active ? 'filled' : 'light'}
                  radius="xl"
                >
                  {getPlatformIcon(platform.icon, 22)}
                </ThemeIcon>
                <div style={{ minWidth: 0, flex: 1 }}>
                  <Group gap="xs" mb={4}>
                    <Text fw={700} size="sm">{platform.label}</Text>
                    <Badge size="xs" color="gray" variant="dot">{platform.name}</Badge>
                    {!platform.is_active && <Badge size="xs" color="gray">Inactive</Badge>}
                  </Group>
                  {platform.profile_url ? (
                    <Group gap={4} wrap="nowrap">
                      <IconExternalLink size={12} style={{ color: 'var(--mantine-color-blue-5)', flexShrink: 0 }} />
                      <Text
                        size="xs" c="blue" lineClamp={1} component="a"
                        href={platform.profile_url} target="_blank" rel="noopener noreferrer"
                        style={{ textDecoration: 'none' }}
                      >
                        {platform.profile_url}
                      </Text>
                    </Group>
                  ) : (
                    <Text size="xs" c="dimmed">No profile URL set</Text>
                  )}
                </div>
              </Group>
              <Group gap="xs" wrap="nowrap">
                <Tooltip label={platform.is_active ? 'Disable platform' : 'Enable platform'} position="top" withArrow>
                  <ActionIcon
                    size="md" variant="subtle"
                    color={platform.is_active ? 'green' : 'gray'}
                    loading={toggleActive.isPending}
                    onClick={() => toggleActive.mutate({ id: platform.id, is_active: !platform.is_active })}
                  >
                    {platform.is_active ? <IconToggleRight size={20} /> : <IconToggleLeft size={20} />}
                  </ActionIcon>
                </Tooltip>
                {can('social.targets') && (
                  <>
                    <ActionIcon size="sm" variant="subtle"
                      onClick={() => { setEditing(platform); open(); }}>
                      <IconEdit size={14} />
                    </ActionIcon>
                    <ActionIcon size="sm" variant="subtle" color="red"
                      onClick={() => deleteMutation.mutate(platform.id)}>
                      <IconTrash size={14} />
                    </ActionIcon>
                  </>
                )}
              </Group>
            </Group>
          </Paper>
        ))}
      </Stack>

      <PlatformFormModal opened={modal} onClose={close} existing={editing} />
    </Stack>
  );
}

function PlatformFormModal({ opened, onClose, existing }: {
  opened: boolean; onClose: () => void; existing: SocialPlatformConfig | null;
}) {
  const qc = useQueryClient();

  const form = useForm({
    initialValues: {
      name:        existing?.name        ?? '',
      label:       existing?.label       ?? '',
      color:       existing?.color       ?? 'blue',
      icon:        existing?.icon        ?? 'brand-instagram',
      profile_url: existing?.profile_url ?? '',
      is_active:   existing?.is_active   ?? true,
      sort_order:  existing?.sort_order  ?? 99,
    },
    validate: {
      name:  v => !existing && !v.trim() ? 'Name required' : null,
      label: v => !v.trim() ? 'Label required' : null,
    },
  });

  useEffect(() => {
    if (existing) {
      form.setValues({
        name:        existing.name,
        label:       existing.label,
        color:       existing.color,
        icon:        existing.icon,
        profile_url: existing.profile_url ?? '',
        is_active:   existing.is_active,
        sort_order:  existing.sort_order,
      });
    } else {
      form.reset();
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [existing?.id]);

  const mutation = useMutation({
    mutationFn: (v: ReturnType<typeof form.getValues>) => {
      const payload = {
        name:        v.name,
        label:       v.label,
        color:       v.color,
        icon:        v.icon,
        profile_url: v.profile_url || undefined,
        is_active:   v.is_active,
        sort_order:  v.sort_order,
      };
      return existing
        ? updateSocialPlatform(existing.id, payload)
        : createSocialPlatform(payload);
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['social-platforms'] });
      notifications.show({ message: existing ? 'Platform updated.' : 'Platform added.', color: 'green' });
      form.reset();
      onClose();
    },
  });

  const selectedIcon = form.values.icon;
  const selectedColor = form.values.color;

  return (
    <Modal opened={opened} onClose={onClose}
      title={existing ? `Edit ${existing.label}` : 'Add Social Media Platform'}
      centered size="sm">
      <form onSubmit={form.onSubmit(v => mutation.mutate(v))}>
        <Stack>
          {/* Icon + color preview */}
          <Group justify="center" mb="xs">
            <ThemeIcon size={60} color={selectedColor} variant="filled" radius="xl">
              {getPlatformIcon(selectedIcon, 30)}
            </ThemeIcon>
          </Group>

          <Select
            label="Icon" required
            data={KNOWN_ICONS.map(i => ({ value: i.value, label: i.label }))}
            renderOption={({ option }) => (
              <Group gap="sm">
                {getPlatformIcon(option.value, 16)}
                <Text size="sm">{option.label}</Text>
              </Group>
            )}
            {...form.getInputProps('icon')}
          />

          <TextInput
            label="Label" required placeholder="Instagram"
            {...form.getInputProps('label')}
          />

          {!existing && (
            <TextInput
              label="Name (slug)" required placeholder="instagram"
              description="Lowercase, no spaces — used internally"
              {...form.getInputProps('name')}
            />
          )}

          <div>
            <Text size="sm" fw={500} mb={6}>Color</Text>
            <Group gap="xs" wrap="wrap">
              {MANTINE_COLORS.map(c => (
                <Tooltip key={c} label={c} position="top" withArrow>
                  <div
                    onClick={() => form.setFieldValue('color', c)}
                    style={{
                      width: 24, height: 24, borderRadius: '50%', cursor: 'pointer',
                      background: `var(--mantine-color-${c}-6)`,
                      outline: form.values.color === c ? '3px solid var(--mantine-color-blue-5)' : 'none',
                      outlineOffset: 2,
                    }}
                  />
                </Tooltip>
              ))}
            </Group>
          </div>

          <TextInput
            label="Profile URL" placeholder="https://instagram.com/moinfotech"
            leftSection={<IconLink size={14} />}
            description="Used as a quick link in QA review"
            {...form.getInputProps('profile_url')}
          />

          <Group grow>
            <NumberInput label="Sort order" min={0} max={99} {...form.getInputProps('sort_order')} />
            <Switch
              label="Active" checked={form.values.is_active}
              onChange={e => form.setFieldValue('is_active', e.currentTarget.checked)}
              mt="lg"
            />
          </Group>

          <Group justify="flex-end">
            <Button variant="default" onClick={onClose}>Cancel</Button>
            <Button type="submit" loading={mutation.isPending}>
              {existing ? 'Update' : 'Add Platform'}
            </Button>
          </Group>
        </Stack>
      </form>
    </Modal>
  );
}

// ── Client Designs Tab ────────────────────────────────────────────────────────

function ClientDesignsTab({ can }: { can: (p: string) => boolean }) {
  const qc = useQueryClient();
  const [filterStatus,  setFilterStatus]  = useState<string | null>(null);
  const [filterType,    setFilterType]    = useState<string | null>(null);
  const [filterDesigner, setFilterDesigner] = useState<string | null>(null);
  const [orderModal,  { open: openOrder,  close: closeOrder }]  = useDisclosure(false);
  const [detailModal, { open: openDetail, close: closeDetail }] = useDisclosure(false);
  const [selected, setSelected]   = useState<ClientDesignOrder | null>(null);
  const [editing,  setEditing]    = useState<ClientDesignOrder | null>(null);

  const { data: usersData } = useQuery({ queryKey: ['users'], queryFn: () => getUsers({ per_page: 100 }) });
  const users = (usersData?.data?.data ?? []).map((u: any) => ({ value: u.id, label: u.name }));

  const { data, isLoading, refetch } = useQuery({
    queryKey: ['client-design-orders', filterStatus, filterType, filterDesigner],
    queryFn: () => getDesignOrders({
      status:      filterStatus  || undefined,
      design_type: filterType    || undefined,
      designer_id: filterDesigner || undefined,
    }),
  });
  const orders: ClientDesignOrder[] = data?.data?.data ?? [];

  const deleteMutation = useMutation({
    mutationFn: deleteDesignOrder,
    onSuccess: () => { qc.invalidateQueries({ queryKey: ['client-design-orders'] }); notifications.show({ message: 'Order deleted.', color: 'green' }); },
  });

  // Stats
  const stats = DESIGN_ORDER_STATUSES.map(s => ({
    status: s, count: orders.filter(o => o.status === s).length,
  }));
  const overdueCount = orders.filter(o => o.is_overdue).length;

  return (
    <Stack>
      {/* Header */}
      <Group justify="space-between">
        <Group gap="xs">
          <Text fw={600} size="lg">Client Design Orders</Text>
          {overdueCount > 0 && (
            <Badge color="red" leftSection={<IconAlertTriangle size={12} />} variant="light">
              {overdueCount} overdue
            </Badge>
          )}
        </Group>
        {can('social.create') && (
          <Button leftSection={<IconPlus size={16} />} onClick={() => { setEditing(null); openOrder(); }}>
            New Order
          </Button>
        )}
      </Group>

      {/* Status summary chips */}
      <Group gap="xs" wrap="wrap">
        {stats.map(({ status, count }) => (
          <Badge
            key={status} size="lg" variant={filterStatus === status ? 'filled' : 'light'}
            color={DESIGN_ORDER_STATUS_COLORS[status as DesignOrderStatus]}
            style={{ cursor: 'pointer' }}
            onClick={() => setFilterStatus(filterStatus === status ? null : status)}
          >
            {DESIGN_ORDER_STATUS_LABELS[status as DesignOrderStatus]}: {count}
          </Badge>
        ))}
      </Group>

      {/* Filter row */}
      <Group gap="xs" wrap="wrap">
        <Select
          size="xs" placeholder="All types" clearable
          data={DESIGN_TYPES.map(t => ({ value: t, label: DESIGN_TYPE_LABELS[t] }))}
          value={filterType} onChange={setFilterType}
          style={{ width: 180 }}
        />
        <Select
          size="xs" placeholder="All designers" clearable
          data={users}
          value={filterDesigner} onChange={setFilterDesigner}
          style={{ width: 160 }}
        />
        {(filterStatus || filterType || filterDesigner) && (
          <Button size="xs" variant="subtle" color="gray"
            onClick={() => { setFilterStatus(null); setFilterType(null); setFilterDesigner(null); }}>
            Clear filters
          </Button>
        )}
        <Text size="xs" c="dimmed" ml="auto">{orders.length} order{orders.length !== 1 ? 's' : ''}</Text>
      </Group>

      {/* Orders list */}
      {isLoading ? <Center py="xl"><Loader /></Center> : orders.length === 0 ? (
        <Center py="xl">
          <Stack align="center" gap="xs">
            <ThemeIcon size="xl" color="gray" variant="light" radius="xl"><IconPackage size={28} /></ThemeIcon>
            <Text c="dimmed">No design orders found.</Text>
            {can('social.create') && (
              <Button size="sm" variant="light" onClick={() => { setEditing(null); openOrder(); }}>
                Create first order
              </Button>
            )}
          </Stack>
        </Center>
      ) : (
        <Stack gap="xs">
          {orders.map(order => (
            <Paper key={order.id} withBorder p="md" radius="md"
              style={{
                cursor: 'pointer',
                borderLeft: `4px solid var(--mantine-color-${DESIGN_ORDER_STATUS_COLORS[order.status]}-5)`,
                opacity: order.status === 'delivered' ? 0.75 : 1,
              }}
              onClick={() => { setSelected(order); openDetail(); }}>
              <Group justify="space-between" wrap="nowrap" align="flex-start">
                <Group gap="sm" style={{ flex: 1, minWidth: 0 }} align="flex-start">
                  <ThemeIcon size="md" color={DESIGN_TYPE_COLORS[order.design_type]} variant="light" mt={2}>
                    <IconPhoto size={16} />
                  </ThemeIcon>
                  <div style={{ minWidth: 0, flex: 1 }}>
                    <Group gap="xs" mb={4} wrap="wrap">
                      <Text fw={600} size="sm" lineClamp={1}>{order.title}</Text>
                      {order.is_overdue && (
                        <Badge size="xs" color="red" leftSection={<IconAlertTriangle size={10} />}>Overdue</Badge>
                      )}
                    </Group>
                    <Group gap="xs" wrap="wrap">
                      <Badge size="xs" color={DESIGN_TYPE_COLORS[order.design_type]} variant="light">
                        {DESIGN_TYPE_LABELS[order.design_type]}
                      </Badge>
                      <Badge size="xs" color={DESIGN_ORDER_STATUS_COLORS[order.status]}>
                        {DESIGN_ORDER_STATUS_LABELS[order.status]}
                      </Badge>
                      {order.revision_count > 0 && (
                        <Badge size="xs" color="orange" variant="dot">
                          {order.revision_count} revision{order.revision_count > 1 ? 's' : ''}
                        </Badge>
                      )}
                    </Group>
                    <Group gap="xs" mt={6} wrap="wrap">
                      {order.client && (
                        <Text size="xs" c="dimmed">Client: <strong>{order.client.name}</strong></Text>
                      )}
                      {order.designer && (
                        <Text size="xs" c="dimmed">Designer: <strong>{order.designer.name}</strong></Text>
                      )}
                      {order.due_date && (
                        <Group gap={4} wrap="nowrap">
                          <IconClock size={12} style={{ color: order.is_overdue ? 'var(--mantine-color-red-5)' : 'var(--mantine-color-dimmed)' }} />
                          <Text size="xs" c={order.is_overdue ? 'red' : 'dimmed'}>
                            Due {dayjs(order.due_date).format('D MMM YYYY')}
                          </Text>
                        </Group>
                      )}
                      {order.price && (
                        <Text size="xs" c="dimmed">
                          TZS {Number(order.price).toLocaleString()}
                        </Text>
                      )}
                    </Group>
                    {order.revision_notes && order.status === 'needs_revision' && (
                      <Text size="xs" c="orange" mt={4} lineClamp={2}>
                        📋 Revision: {order.revision_notes}
                      </Text>
                    )}
                  </div>
                </Group>
                <Group gap="xs" wrap="nowrap">
                  {order.file_url && (
                    <Tooltip label="File uploaded" position="top" withArrow>
                      <ThemeIcon size="sm" color="green" variant="light">
                        <IconCheck size={12} />
                      </ThemeIcon>
                    </Tooltip>
                  )}
                  {can('social.update') && (
                    <ActionIcon size="sm" variant="subtle"
                      onClick={e => { e.stopPropagation(); setEditing(order); openOrder(); }}>
                      <IconEdit size={14} />
                    </ActionIcon>
                  )}
                  {can('social.delete') && (
                    <ActionIcon size="sm" variant="subtle" color="red"
                      onClick={e => { e.stopPropagation(); deleteMutation.mutate(order.id); }}>
                      <IconTrash size={14} />
                    </ActionIcon>
                  )}
                </Group>
              </Group>
            </Paper>
          ))}
        </Stack>
      )}

      <DesignOrderFormModal
        opened={orderModal} onClose={closeOrder}
        existing={editing} users={users}
      />
      {selected && (
        <DesignOrderDetailModal
          order={selected} opened={detailModal}
          onClose={() => { closeDetail(); setSelected(null); refetch(); }}
          canUpdate={can('social.update')}
          users={users}
        />
      )}
    </Stack>
  );
}

function DesignOrderFormModal({ opened, onClose, existing, users }: {
  opened: boolean; onClose: () => void;
  existing: ClientDesignOrder | null;
  users: { value: string; label: string }[];
}) {
  const qc = useQueryClient();
  const { data: clientsData } = useQuery({
    queryKey: ['clients-list'],
    queryFn: () => getClients({ per_page: 200 }),
  });
  const clients = (clientsData?.data?.data ?? []).map((c: any) => ({ value: c.id, label: c.name }));

  const form = useForm({
    initialValues: {
      title:                existing?.title ?? '',
      design_type:          (existing?.design_type ?? 'flyer') as DesignType,
      client_id:            existing?.client?.id ?? '',
      description:          existing?.description ?? '',
      reference_url:        existing?.reference_url ?? '',
      assigned_designer_id: existing?.designer?.id ?? '',
      due_date:             existing?.due_date ? new Date(existing.due_date) : null as Date | null,
      price:                existing?.price ? Number(existing.price) : null as number | null,
    },
    validate: {
      title: v => !v.trim() ? 'Title required' : null,
    },
  });

  useEffect(() => {
    if (existing) {
      form.setValues({
        title:                existing.title,
        design_type:          existing.design_type,
        client_id:            existing.client?.id ?? '',
        description:          existing.description ?? '',
        reference_url:        existing.reference_url ?? '',
        assigned_designer_id: existing.designer?.id ?? '',
        due_date:             existing.due_date ? new Date(existing.due_date) : null,
        price:                existing.price ? Number(existing.price) : null,
      });
    } else {
      form.reset();
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [existing?.id]);

  const mutation = useMutation({
    mutationFn: (v: ReturnType<typeof form.getValues>) => {
      const payload = {
        title:                v.title,
        design_type:          v.design_type,
        client_id:            v.client_id   || undefined,
        description:          v.description  || undefined,
        reference_url:        v.reference_url || undefined,
        assigned_designer_id: v.assigned_designer_id || undefined,
        due_date:             v.due_date ? dayjs(v.due_date).format('YYYY-MM-DD') : undefined,
        price:                v.price ?? undefined,
      };
      return existing ? updateDesignOrder(existing.id, payload) : createDesignOrder(payload);
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['client-design-orders'] });
      notifications.show({ message: existing ? 'Order updated.' : 'Order created.', color: 'green' });
      form.reset();
      onClose();
    },
  });

  return (
    <Modal opened={opened} onClose={onClose}
      title={existing ? 'Edit Design Order' : 'New Client Design Order'}
      centered size="md">
      <form onSubmit={form.onSubmit(v => mutation.mutate(v))}>
        <Stack>
          <TextInput label="Order title" required placeholder="Logo for ABC Company" {...form.getInputProps('title')} />

          <Select
            label="Design type" required
            data={DESIGN_TYPES.map(t => ({ value: t, label: DESIGN_TYPE_LABELS[t] }))}
            {...form.getInputProps('design_type')}
          />

          <Select
            label="Client" placeholder="Select client (optional)"
            data={clients} clearable searchable
            {...form.getInputProps('client_id')}
          />

          <Textarea
            label="Brief / Requirements" minRows={3}
            placeholder="Describe what the client needs, brand colors, style preferences…"
            {...form.getInputProps('description')}
          />

          <TextInput
            label="Reference URL" placeholder="https://drive.google.com/… (brand guidelines, examples)"
            leftSection={<IconLink size={14} />}
            {...form.getInputProps('reference_url')}
          />

          <Select
            label="Assigned Designer" data={users} clearable searchable
            {...form.getInputProps('assigned_designer_id')}
          />

          <Group grow>
            <DatePickerInput label="Due date" clearable {...form.getInputProps('due_date')} />
            <NumberInput
              label="Price (TZS)" placeholder="0" min={0}
              {...form.getInputProps('price')}
            />
          </Group>

          <Group justify="flex-end">
            <Button variant="default" onClick={onClose}>Cancel</Button>
            <Button type="submit" loading={mutation.isPending}>
              {existing ? 'Update' : 'Create Order'}
            </Button>
          </Group>
        </Stack>
      </form>
    </Modal>
  );
}

function DesignOrderDetailModal({ order, opened, onClose, canUpdate, users }: {
  order: ClientDesignOrder; opened: boolean; onClose: () => void;
  canUpdate: boolean;
  users: { value: string; label: string }[];
}) {
  const qc = useQueryClient();
  const [fileUrl,       setFileUrl]       = useState(order.file_url ?? '');
  const [revisionNotes, setRevisionNotes] = useState('');

  const mutation = useMutation({
    mutationFn: (updates: Parameters<typeof updateDesignOrder>[1]) =>
      updateDesignOrder(order.id, updates),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['client-design-orders'] });
      notifications.show({ message: 'Order updated.', color: 'green' });
      onClose();
    },
  });

  const setStatus = (status: DesignOrderStatus) => {
    const updates: Parameters<typeof updateDesignOrder>[1] = { status };
    if (fileUrl) updates.file_url = fileUrl;
    if (status === 'needs_revision' && revisionNotes) updates.revision_notes = revisionNotes;
    mutation.mutate(updates);
  };

  const timeStr = order.due_date ? dayjs(order.due_date).format('D MMM YYYY') : null;

  return (
    <Modal opened={opened} onClose={onClose} title={order.title} size="md" centered>
      <Stack gap="md">
        {/* Status + badges */}
        <Group gap="xs" wrap="wrap">
          <Badge color={DESIGN_ORDER_STATUS_COLORS[order.status]} size="lg">
            {DESIGN_ORDER_STATUS_LABELS[order.status]}
          </Badge>
          <Badge color={DESIGN_TYPE_COLORS[order.design_type]} variant="light">
            {DESIGN_TYPE_LABELS[order.design_type]}
          </Badge>
          {order.is_overdue && <Badge color="red" leftSection={<IconAlertTriangle size={10} />}>Overdue</Badge>}
          {order.revision_count > 0 && (
            <Badge color="orange" variant="dot">{order.revision_count} revision{order.revision_count > 1 ? 's' : ''}</Badge>
          )}
        </Group>

        {/* Meta */}
        <SimpleGrid cols={2} spacing="xs">
          {order.client   && <Text size="sm"><Text span c="dimmed">Client: </Text>{order.client.name}</Text>}
          {order.designer && <Text size="sm"><Text span c="dimmed">Designer: </Text>{order.designer.name}</Text>}
          {timeStr        && <Text size="sm" c={order.is_overdue ? 'red' : undefined}><Text span c="dimmed">Due: </Text>{timeStr}</Text>}
          {order.price    && <Text size="sm"><Text span c="dimmed">Price: </Text>TZS {Number(order.price).toLocaleString()}</Text>}
        </SimpleGrid>

        {/* Description */}
        {order.description && (
          <>
            <Divider label="Brief" labelPosition="left" />
            <Text size="sm" style={{ whiteSpace: 'pre-wrap' }}>{order.description}</Text>
          </>
        )}

        {/* Revision notes */}
        {order.revision_notes && (
          <>
            <Divider label="Revision Request" labelPosition="left" />
            <Paper withBorder p="sm" bg="orange.0" radius="sm">
              <Text size="sm" c="orange.8">{order.revision_notes}</Text>
            </Paper>
          </>
        )}

        {/* Reference */}
        {order.reference_url && (
          <Button
            size="xs" variant="subtle" component="a"
            href={order.reference_url} target="_blank" rel="noopener noreferrer"
            leftSection={<IconLink size={12} />}
          >
            View Reference / Brief
          </Button>
        )}

        {/* File + status actions */}
        {canUpdate && (
          <>
            <Divider label="Update Status" labelPosition="left" />
            <TextInput
              label="Design file URL (Google Drive, Canva…)"
              placeholder="https://drive.google.com/…"
              leftSection={<IconLink size={14} />}
              value={fileUrl} onChange={e => setFileUrl(e.currentTarget.value)}
            />
            {order.status === 'in_progress' || order.status === 'needs_revision' ? (
              <Textarea
                label="Revision notes (if requesting changes)"
                placeholder="Describe what needs to be changed…"
                minRows={2}
                value={revisionNotes} onChange={e => setRevisionNotes(e.currentTarget.value)}
              />
            ) : null}

            <Group gap="xs" wrap="wrap">
              {order.status === 'pending' && (
                <Button size="xs" color="yellow" loading={mutation.isPending}
                  onClick={() => setStatus('in_progress')}>
                  Start Working
                </Button>
              )}
              {(order.status === 'in_progress' || order.status === 'needs_revision') && (
                <>
                  <Button size="xs" color="green" loading={mutation.isPending}
                    onClick={() => setStatus('done')}>
                    Mark Done
                  </Button>
                  <Button size="xs" color="orange" variant="light" loading={mutation.isPending}
                    onClick={() => setStatus('needs_revision')}>
                    Request Revision
                  </Button>
                </>
              )}
              {order.status === 'done' && (
                <Button size="xs" color="teal" loading={mutation.isPending}
                  onClick={() => setStatus('delivered')}>
                  Mark Delivered
                </Button>
              )}
              {order.status === 'delivered' && (
                <Button size="xs" variant="light" color="yellow" loading={mutation.isPending}
                  onClick={() => setStatus('in_progress')}>
                  Re-open
                </Button>
              )}
              {order.file_url && (
                <Button
                  size="xs" variant="subtle" component="a"
                  href={order.file_url} target="_blank" rel="noopener noreferrer"
                  leftSection={<IconLink size={12} />}
                >
                  View Current File
                </Button>
              )}
            </Group>
          </>
        )}

        {!canUpdate && order.file_url && (
          <Button
            size="xs" variant="light" component="a"
            href={order.file_url} target="_blank" rel="noopener noreferrer"
            leftSection={<IconLink size={12} />}
          >
            Download Design File
          </Button>
        )}
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
