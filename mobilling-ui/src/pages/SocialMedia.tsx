import { useState, useEffect } from 'react';
import {
  Title, Tabs, Stack, Group, Button, Badge, Text, Paper, SimpleGrid,
  ActionIcon, Tooltip, Modal, TextInput, Select, Textarea, Progress,
  ThemeIcon, Divider, Checkbox, NumberInput, Switch, Loader, Center,
  SegmentedControl, Chip,
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
  getTarget, upsertTarget,
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

const SOCIAL_TABS = [
  { value: 'posts',          perm: 'social.board',          label: 'Posts',          icon: <IconCalendarWeek size={16} /> },
  { value: 'workflow',       perm: 'social.design_work',    label: 'Workflow',       icon: <IconLayoutColumns size={16} /> },
  { value: 'client_designs', perm: 'social.client_designs', label: 'Client Designs', icon: <IconBriefcase size={16} /> },
  { value: 'settings',       perm: 'social.settings',       label: 'Settings',       icon: <IconSettings size={16} />, alignRight: true },
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
        {can('social.board')          && <Tabs.Panel value="posts">          <PostsTab    can={can} platforms={activePlatforms} /></Tabs.Panel>}
        {can('social.design_work')    && <Tabs.Panel value="workflow">       <WorkflowTab can={can} platforms={activePlatforms} /></Tabs.Panel>}
        {can('social.client_designs') && <Tabs.Panel value="client_designs"> <ClientDesignsTab can={can} /></Tabs.Panel>}
        {can('social.settings')       && <Tabs.Panel value="settings">       <SettingsTab can={can} platforms={platforms} /></Tabs.Panel>}
      </Tabs>
    </Stack>
  );
}

// ── Board Tab ────────────────────────────────────────────────────────────────

function WeeklyProgressBar() {
  const ws = weekStart(0);
  const we = dayjs(ws).add(6, 'day').format('YYYY-MM-DD');

  const { data: targetData } = useQuery({ queryKey: ['social-target'], queryFn: getTarget });
  const { data: summaryData } = useQuery({
    queryKey: ['social-weekly-summary', ws],
    queryFn: () => getWeeklySummary(ws),
  });

  const target  = targetData?.data?.data ?? null;
  const summary = summaryData?.data ?? null;
  if (!target) return null;

  const imageTarget  = target.image_target;
  const videoTarget  = target.video_target;
  const imageDone    = summary?.image_achieved ?? 0;
  const videoDone    = summary?.video_achieved ?? 0;
  const imagePercent = imageTarget > 0 ? Math.min(100, Math.round((imageDone / imageTarget) * 100)) : 0;
  const videoPercent = videoTarget > 0 ? Math.min(100, Math.round((videoDone / videoTarget) * 100)) : 0;

  const barColor = (pct: number) => pct >= 100 ? 'green' : pct >= 50 ? 'yellow' : 'red';

  return (
    <Paper withBorder px="md" py="xs" radius="md">
      <Group gap="xl" wrap="nowrap">
        <Text size="xs" c="dimmed" fw={500} style={{ whiteSpace: 'nowrap' }}>
          {dayjs(ws).format('D MMM')} – {dayjs(we).format('D MMM')}
        </Text>
        <Group gap="xs" style={{ flex: 1 }} wrap="nowrap">
          <ThemeIcon size="xs" variant="light" color="blue"><IconPhoto size={10} /></ThemeIcon>
          <Text size="xs" fw={500} style={{ whiteSpace: 'nowrap' }}>{imageDone}/{imageTarget}</Text>
          <Progress value={imagePercent} color={barColor(imagePercent)} size="sm" style={{ flex: 1 }} />
        </Group>
        <Group gap="xs" style={{ flex: 1 }} wrap="nowrap">
          <ThemeIcon size="xs" variant="light" color="grape"><IconVideo size={10} /></ThemeIcon>
          <Text size="xs" fw={500} style={{ whiteSpace: 'nowrap' }}>{videoDone}/{videoTarget}</Text>
          <Progress value={videoPercent} color={barColor(videoPercent)} size="sm" style={{ flex: 1 }} />
        </Group>
      </Group>
    </Paper>
  );
}

function PostsTab({ can, platforms }: { can: (p: string) => boolean; platforms: SocialPlatformConfig[] }) {
  const qc = useQueryClient();
  const [filterType,   setFilterType]   = useState<string | null>(null);
  const [filterStatus, setFilterStatus] = useState<string | null>(null);
  const [selected, setSelected] = useState<SocialPost | null>(null);
  const [postModal,   { open: openPost,   close: closePost   }] = useDisclosure(false);
  const [detailModal, { open: openDetail, close: closeDetail }] = useDisclosure(false);

  const { data, isLoading } = useQuery({
    queryKey: ['social-posts'],
    queryFn: () => getPosts(),
  });
  const allPosts: SocialPost[] = data?.data?.data ?? [];
  const posts = allPosts.filter(p =>
    (!filterType   || p.type === filterType) &&
    (!filterStatus || p.status === filterStatus)
  );

  const deleteMutation = useMutation({
    mutationFn: deletePost,
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['social-posts'] });
      notifications.show({ message: 'Post deleted.', color: 'green' });
    },
  });

  return (
    <Stack>
      <WeeklyProgressBar />
      <Group justify="space-between" wrap="nowrap">
        <Group gap="xs">
          <Select size="xs" placeholder="All types" clearable
            data={POST_TYPES.map(t => ({ value: t, label: TYPE_LABELS[t] }))}
            value={filterType} onChange={setFilterType} style={{ width: 160 }} />
          <Select size="xs" placeholder="All statuses" clearable
            data={Object.entries(STATUS_LABEL).map(([v, l]) => ({ value: v, label: l }))}
            value={filterStatus} onChange={setFilterStatus} style={{ width: 140 }} />
          <Text size="xs" c="dimmed">{posts.length} post{posts.length !== 1 ? 's' : ''}</Text>
        </Group>
        {can('social.create') && (
          <Button leftSection={<IconPlus size={16} />} onClick={openPost}>New Post</Button>
        )}
      </Group>

      {isLoading ? <Center py="xl"><Loader /></Center> : (
        <Stack gap="xs">
          {posts.length === 0 && <Center py="xl"><Text c="dimmed">No posts yet.</Text></Center>}
          {posts.map(post => (
            <PostRow
              key={post.id} post={post} platforms={platforms}
              canDelete={can('social.delete')}
              onOpen={() => { setSelected(post); openDetail(); }}
              onDelete={() => deleteMutation.mutate(post.id)}
            />
          ))}
        </Stack>
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

function PostRow({ post, platforms, canDelete, onOpen, onDelete }: {
  post: SocialPost; platforms: SocialPlatformConfig[];
  canDelete: boolean; onOpen: () => void; onDelete: () => void;
}) {
  const timeStr = formatTime(post.scheduled_time);
  const isToday = post.scheduled_date === dayjs().format('YYYY-MM-DD');

  return (
    <Paper withBorder p="sm" style={{ cursor: 'pointer' }} onClick={onOpen}>
      <Group wrap="nowrap" gap="md">
        {/* Date */}
        <Stack gap={0} align="center" style={{ minWidth: 52 }}>
          <Text size="xs" fw={700} c={isToday ? 'blue' : 'dimmed'}>{dayjs(post.scheduled_date).format('ddd').toUpperCase()}</Text>
          <Text size="lg" fw={800} lh={1}>{dayjs(post.scheduled_date).format('D')}</Text>
          <Text size="xs" c="dimmed">{dayjs(post.scheduled_date).format('MMM')}</Text>
          {timeStr && <Text size={10} c="dimmed">{timeStr}</Text>}
        </Stack>

        <Divider orientation="vertical" />

        {/* Title + type */}
        <Stack gap={4} style={{ flex: 1, minWidth: 0 }}>
          <Text size="sm" fw={600} lineClamp={1}>{post.title}</Text>
          <Group gap={4} wrap="wrap">
            <Badge size="xs" variant="dot" color="gray">{TYPE_LABELS[post.type]}</Badge>
            {post.post_format.map(fmt => (
              <Badge key={fmt} size="xs" color={FORMAT_COLORS[fmt]} variant="light">{FORMAT_LABELS[fmt]}</Badge>
            ))}
            {post.media_type === 'video' && <Badge size="xs" color="grape" variant="light">Video</Badge>}
          </Group>
        </Stack>

        {/* Platforms */}
        <Group gap={3} wrap="nowrap">
          {platforms.map(pl => {
            const row = post.platforms[pl.name];
            return (
              <Tooltip key={pl.name} label={pl.label} withArrow position="top">
                <ThemeIcon size={22} color={row?.posted ? pl.color : 'gray'} variant={row?.posted ? 'filled' : 'light'} radius="xl">
                  {getPlatformIcon(pl.icon, 12)}
                </ThemeIcon>
              </Tooltip>
            );
          })}
        </Group>

        {/* Status */}
        <Badge size="sm" color={STATUS_COLOR[post.status]} style={{ flexShrink: 0 }}>{STATUS_LABEL[post.status]}</Badge>

        {canDelete && (
          <ActionIcon size="sm" color="red" variant="subtle"
            onClick={e => { e.stopPropagation(); onDelete(); }}>
            <IconTrash size={14} />
          </ActionIcon>
        )}
      </Group>
    </Paper>
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
            {post.post_format.map(fmt => (
              <Badge key={fmt} size="xs" color={FORMAT_COLORS[fmt]} variant="filled" leftSection={FORMAT_ICONS[fmt]}>
                {FORMAT_LABELS[fmt]}
              </Badge>
            ))}
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

  const form = useForm({
    initialValues: {
      title:          existing?.title ?? '',
      post_format:    (existing?.post_format ?? ['feed_post']) as PostFormat[],
      media_type:     existing?.media_type ?? 'image',
      scheduled_date: existing?.scheduled_date ? new Date(existing.scheduled_date) : new Date() as Date | null,
      type:           (existing?.type ?? 'general') as PostType,
    },
    validate: {
      title:          v => !v.trim() ? 'Title is required' : null,
      scheduled_date: v => !v ? 'Date is required' : null,
    },
  });

  const isEdit = !!existing;

  const mutation = useMutation({
    mutationFn: (vals: ReturnType<typeof form.getValues>) =>
      isEdit
        ? updatePost(existing!.id, {
            title:          vals.title,
            type:           vals.type,
            post_format:    Array.isArray(vals.post_format) ? vals.post_format : [vals.post_format],
            media_type:     vals.media_type as 'image' | 'video',
            scheduled_date: dayjs(vals.scheduled_date!).format('YYYY-MM-DD'),
          })
        : createPost({
            title:          vals.title,
            type:           vals.type,
            post_format:    Array.isArray(vals.post_format) ? vals.post_format : [vals.post_format],
            media_type:     vals.media_type as 'image' | 'video',
            scheduled_date: dayjs(vals.scheduled_date!).format('YYYY-MM-DD'),
          }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['social-posts'] });
      qc.invalidateQueries({ queryKey: ['social-weekly-summary'] });
      notifications.show({ message: isEdit ? 'Post updated.' : 'Post added to plan.', color: 'green' });
      form.reset();
      onClose();
    },
  });

  return (
    <Modal opened={opened} onClose={onClose} title={isEdit ? 'Edit Post' : 'Plan a Post'} centered size="sm">
      <form onSubmit={form.onSubmit(v => mutation.mutate(v))}>
        <Stack gap="sm">
          <TextInput
            label="What's this post about?"
            placeholder="e.g. Ramadan promo, Product launch, Staff spotlight…"
            required
            {...form.getInputProps('title')}
          />

          <DatePickerInput label="Date" required {...form.getInputProps('scheduled_date')} />

          <div>
            <Text size="sm" fw={500} mb={6}>Format</Text>
            <Chip.Group multiple {...form.getInputProps('post_format')}>
              <Group gap="xs">
                {POST_FORMATS.map(f => (
                  <Chip key={f} value={f} color={FORMAT_COLORS[f]} variant="outline" size="sm">
                    {FORMAT_LABELS[f]}
                  </Chip>
                ))}
              </Group>
            </Chip.Group>
          </div>

          <SegmentedControl
            fullWidth
            data={[
              { value: 'image', label: '📷 Graphic / Image' },
              { value: 'video', label: '🎬 Video / Reel' },
            ]}
            {...form.getInputProps('media_type')}
          />

          <Select
            label="Category"
            data={POST_TYPES.map(t => ({ value: t, label: TYPE_LABELS[t] }))}
            {...form.getInputProps('type')}
          />

          <Group justify="flex-end" mt="xs">
            <Button variant="default" onClick={onClose}>Cancel</Button>
            <Button type="submit" loading={mutation.isPending}>
              {isEdit ? 'Save changes' : 'Add to plan'}
            </Button>
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
  const [editModal, { open: openEdit, close: closeEdit }] = useDisclosure(false);
  const [brief, setBrief] = useState(post.brief ?? '');
  const [time,  setTime]  = useState(post.scheduled_time?.slice(0, 5) ?? '');

  const briefMutation = useMutation({
    mutationFn: () => updatePost(post.id, {
      brief: brief || undefined,
      scheduled_time: time || undefined,
    }),
    onSuccess: r => { invalidate(); onUpdated(r.data.data); notifications.show({ message: 'Saved.', color: 'green' }); },
  });

  return (
    <>
    <Modal opened={opened} onClose={onClose} title={post.title} size="lg" centered>
      <Stack gap="sm">
        {/* Persistent header: badges + edit */}
        <Group justify="space-between" wrap="wrap">
          <Group gap="xs" wrap="wrap">
            {post.post_format.map(fmt => (
              <Badge key={fmt} size="sm" color={FORMAT_COLORS[fmt]} leftSection={FORMAT_ICONS[fmt]}>
                {FORMAT_LABELS[fmt]}
              </Badge>
            ))}
            <Badge size="sm" color={post.media_type === 'video' ? 'grape' : 'blue'} variant="light">
              {post.media_type === 'video' ? '🎬 Video' : '📷 Image'}
            </Badge>
            <Badge size="sm" color={STATUS_COLOR[post.status]}>{STATUS_LABEL[post.status]}</Badge>
            <Badge size="sm" variant="dot" color="gray">{TYPE_LABELS[post.type]}</Badge>
          </Group>
          <Group gap="xs">
            <Text size="xs" c="dimmed">
              {dayjs(post.scheduled_date).format('D MMM YYYY')}
              {timeStr ? ` at ${timeStr}` : ''}
            </Text>
            {canUpdate && (
              <Button size="xs" variant="subtle" leftSection={<IconEdit size={13} />} onClick={openEdit}>
                Edit
              </Button>
            )}
          </Group>
        </Group>

        {/* Tabbed sections */}
        <Tabs defaultValue="brief" variant="outline">
          <Tabs.List>
            <Tabs.Tab value="brief" leftSection={<IconPencil size={13} />}>Brief</Tabs.Tab>
            <Tabs.Tab value="design" leftSection={<IconPhoto size={13} />}>
              Design
              {post.design_status !== 'pending' && (
                <Badge size="xs" color={post.design_status === 'done' ? 'green' : 'yellow'} variant="filled" ml={6}>
                  {post.design_status === 'done' ? '✓' : '…'}
                </Badge>
              )}
            </Tabs.Tab>
            <Tabs.Tab value="content" leftSection={<IconHash size={13} />}>
              Content
              {post.content_status === 'ready' && (
                <Badge size="xs" color="green" variant="filled" ml={6}>✓</Badge>
              )}
            </Tabs.Tab>
            <Tabs.Tab value="posting" leftSection={<IconDeviceMobile size={13} />}>
              Posting
              {post.status === 'posted' && (
                <Badge size="xs" color="teal" variant="filled" ml={6}>✓</Badge>
              )}
            </Tabs.Tab>
          </Tabs.List>

          {/* Brief */}
          <Tabs.Panel value="brief" pt="sm">
            <Stack gap="xs">
              {canUpdate ? (
                <>
                  <Textarea
                    size="xs" minRows={3}
                    placeholder="Instructions for the designer — colors, text, references…"
                    value={brief} onChange={e => setBrief(e.currentTarget.value)}
                  />
                  <Group gap="xs">
                    <TextInput
                      size="xs" type="time" style={{ width: 130 }}
                      leftSection={<IconClock size={13} />}
                      value={time} onChange={e => setTime(e.currentTarget.value)}
                    />
                    <Button size="xs" variant="light" loading={briefMutation.isPending}
                      onClick={() => briefMutation.mutate()}>
                      Save
                    </Button>
                  </Group>
                </>
              ) : (
                <Text size="sm" c={brief ? undefined : 'dimmed'} style={{ fontStyle: brief ? 'normal' : 'italic' }}>
                  {brief || 'No brief added yet.'}
                </Text>
              )}
            </Stack>
          </Tabs.Panel>

          {/* Design */}
          <Tabs.Panel value="design" pt="sm">
            <Stack gap="xs">
              <Group justify="space-between">
                <Group gap="xs">
                  <Text size="sm" fw={500}>Status</Text>
                  <Badge size="sm" color={post.design_status === 'done' ? 'green' : post.design_status === 'in_progress' ? 'yellow' : 'gray'}>
                    {post.design_status === 'done' ? 'Done' : post.design_status === 'in_progress' ? 'In Progress' : 'Pending'}
                  </Badge>
                </Group>
                {post.design_file_url && (
                  <Button size="xs" variant="subtle" component="a"
                    href={post.design_file_url} target="_blank" rel="noopener noreferrer"
                    leftSection={<IconExternalLink size={12} />}>
                    View File
                  </Button>
                )}
              </Group>
              {canUpdate && (
                <>
                  <TextInput
                    size="xs" placeholder="Google Drive / Canva / Figma URL"
                    value={designUrl} onChange={e => setDesignUrl(e.currentTarget.value)}
                    leftSection={<IconLink size={13} />}
                  />
                  <Textarea
                    size="xs" placeholder="Design notes…" minRows={2}
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
          </Tabs.Panel>

          {/* Content */}
          <Tabs.Panel value="content" pt="sm">
            <Stack gap="xs">
              <Group justify="space-between">
                <Group gap="xs">
                  <Text size="sm" fw={500}>Status</Text>
                  <Badge size="sm" color={post.content_status === 'ready' ? 'green' : 'gray'}>
                    {post.content_status === 'ready' ? 'Ready' : 'Pending'}
                  </Badge>
                </Group>
              </Group>
              {canUpdate ? (
                <>
                  <Textarea
                    size="xs" placeholder="Write caption…" minRows={3}
                    value={caption} onChange={e => setCaption(e.currentTarget.value)}
                  />
                  <TextInput
                    size="xs" placeholder="#moinfotech #tech"
                    leftSection={<IconHash size={12} />}
                    value={hashtags} onChange={e => setHashtags(e.currentTarget.value)}
                  />
                  <Button size="xs" variant="light" color="green" loading={contentMutation.isPending}
                    onClick={() => contentMutation.mutate('ready')} style={{ alignSelf: 'flex-start' }}>
                    Mark Ready
                  </Button>
                </>
              ) : (
                <Stack gap={4}>
                  {post.caption && <Text size="sm" style={{ whiteSpace: 'pre-wrap' }}>{post.caption}</Text>}
                  {post.hashtags && <Text size="sm" c="blue">{post.hashtags}</Text>}
                  {!post.caption && !post.hashtags && <Text size="sm" c="dimmed" fs="italic">No content yet.</Text>}
                </Stack>
              )}
            </Stack>
          </Tabs.Panel>

          {/* Platform Posting */}
          <Tabs.Panel value="posting" pt="sm">
            <Stack gap="xs">
              {platforms.map(platform => {
                const row = post.platforms[platform.name];
                return (
                  <Group key={platform.name} justify="space-between" wrap="nowrap">
                    <Group gap="xs" style={{ minWidth: 0, flex: 1 }}>
                      <ThemeIcon size="sm" color={platform.color} variant={row?.posted ? 'filled' : 'light'}>
                        {getPlatformIcon(platform.icon)}
                      </ThemeIcon>
                      <div style={{ minWidth: 0 }}>
                        <Text size="sm">{platform.label}</Text>
                        {row?.posted && row.posted_at && (
                          <Text size="xs" c="dimmed">{dayjs(row.posted_at).format('D MMM HH:mm')}</Text>
                        )}
                      </div>
                    </Group>
                    {canUpdate ? (
                      <Group gap="xs" wrap="nowrap">
                        <TextInput
                          size="xs" placeholder="Post URL" style={{ width: 160 }}
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
                    ) : row?.post_url ? (
                      <Button size="xs" variant="subtle" component="a"
                        href={row.post_url} target="_blank" rel="noopener noreferrer"
                        leftSection={<IconLink size={12} />}>
                        View
                      </Button>
                    ) : null}
                  </Group>
                );
              })}
            </Stack>
          </Tabs.Panel>
        </Tabs>
      </Stack>
    </Modal>

    <PostFormModal opened={editModal} onClose={closeEdit} existing={post} />
    </>
  );
}

// ── Workflow Tab (Design · Content · Posting) ─────────────────────────────────

function WorkflowTab({ can, platforms }: { can: (p: string) => boolean; platforms: SocialPlatformConfig[] }) {
  const [weekOffset, setWeekOffset] = useState(0);
  const ws = weekStart(weekOffset);
  const we = dayjs(ws).add(6, 'day').format('YYYY-MM-DD');

  const { data, isLoading } = useQuery({
    queryKey: ['social-posts-workflow', ws],
    queryFn: () => getPosts({ week_start: ws }),
  });

  const posts: SocialPost[] = data?.data?.data ?? [];

  // Design column: needs design work
  const designing = posts.filter(p => p.design_status !== 'done');
  // Content column: design done, needs caption/posting
  const content   = posts.filter(p => p.design_status === 'done' && p.status !== 'posted');
  // Posting column: all posts for QA review
  const posting   = posts.sort((a, b) => a.scheduled_date.localeCompare(b.scheduled_date));

  const [selected, setSelected] = useState<SocialPost | null>(null);
  const [detailModal, { open: openDetail, close: closeDetail }] = useDisclosure(false);

  const renderCard = (post: SocialPost) => (
    <Paper key={post.id} withBorder p="sm" style={{ cursor: 'pointer' }}
      onClick={() => { setSelected(post); openDetail(); }}>
      <Stack gap={4}>
        <Text size="sm" fw={600} lineClamp={1}>{post.title}</Text>
        <Group gap={4} wrap="wrap">
          {post.post_format.map(fmt => (
            <Badge key={fmt} size="xs" color={FORMAT_COLORS[fmt]} variant="light">{FORMAT_LABELS[fmt]}</Badge>
          ))}
          {post.media_type === 'video' && <Badge size="xs" color="grape" variant="light">Video</Badge>}
        </Group>
        <Text size="xs" c="dimmed">
          {dayjs(post.scheduled_date).format('ddd D MMM')}
          {post.scheduled_time ? ` · ${formatTime(post.scheduled_time)}` : ''}
        </Text>
        <Group gap={2} mt={2}>
          {platforms.map(p => (
            <Tooltip key={p.name} label={p.label} withArrow>
              <ThemeIcon size={16} color={post.platforms[p.name]?.posted ? p.color : 'gray'}
                variant={post.platforms[p.name]?.posted ? 'filled' : 'light'} radius="xl">
                {getPlatformIcon(p.icon, 9)}
              </ThemeIcon>
            </Tooltip>
          ))}
          <Badge size="xs" color={STATUS_COLOR[post.status]} variant="dot" ml="auto">
            {STATUS_LABEL[post.status]}
          </Badge>
        </Group>
      </Stack>
    </Paper>
  );

  const colCount = [can('social.design_work'), can('social.content'), can('social.qa')].filter(Boolean).length || 1;

  return (
    <Stack>
      <Group gap="xs">
        <ActionIcon variant="default" onClick={() => setWeekOffset(o => o - 1)}>‹</ActionIcon>
        <Text fw={500} size="sm">{dayjs(ws).format('D MMM')} – {dayjs(we).format('D MMM YYYY')}</Text>
        <ActionIcon variant="default" onClick={() => setWeekOffset(o => o + 1)}>›</ActionIcon>
        {weekOffset !== 0 && <Button size="xs" variant="light" onClick={() => setWeekOffset(0)}>This week</Button>}
      </Group>

      {isLoading ? <Center py="xl"><Loader /></Center> : (
        <SimpleGrid cols={colCount} spacing="md">
          {can('social.design_work') && (
            <Stack gap="xs">
              <Group gap="xs">
                <Badge color="violet" variant="filled" size="sm">Design</Badge>
                <Text size="xs" c="dimmed">({designing.length})</Text>
              </Group>
              <Divider />
              {designing.length === 0
                ? <Text size="xs" c="dimmed" ta="center" py="md">All designed ✓</Text>
                : designing.map(renderCard)}
            </Stack>
          )}

          {can('social.content') && (
            <Stack gap="xs">
              <Group gap="xs">
                <Badge color="teal" variant="filled" size="sm">Content</Badge>
                <Text size="xs" c="dimmed">({content.length})</Text>
              </Group>
              <Divider />
              {content.length === 0
                ? <Text size="xs" c="dimmed" ta="center" py="md">All captioned ✓</Text>
                : content.map(renderCard)}
            </Stack>
          )}

          {can('social.qa') && (
            <Stack gap="xs">
              <Group gap="xs">
                <Badge color="orange" variant="filled" size="sm">Posting</Badge>
                <Text size="xs" c="dimmed">({posting.length})</Text>
              </Group>
              <Divider />
              {posting.length === 0
                ? <Text size="xs" c="dimmed" ta="center" py="md">No posts this week</Text>
                : posting.map(renderCard)}
            </Stack>
          )}
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

// ── Settings Tab (Platforms + Targets) ───────────────────────────────────────

function SettingsTab({ can, platforms }: { can: (p: string) => boolean; platforms: SocialPlatformConfig[] }) {
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

      {/* ── Targets section ── */}
      <Divider label="Targets" labelPosition="left" mt="xl" />
      <TargetsSection can={can} />
    </Stack>
  );
}

function TargetsSection({ can }: { can: (p: string) => boolean }) {
  const [weekOffset, setWeekOffset] = useState(0);
  const ws = weekStart(weekOffset);
  const we = dayjs(ws).add(6, 'day').format('YYYY-MM-DD');
  const [targetModal, { open: openTarget, close: closeTarget }] = useDisclosure(false);

  const { data: targetData } = useQuery({ queryKey: ['social-target'], queryFn: getTarget });
  const { data: summaryData, isLoading } = useQuery({
    queryKey: ['social-weekly-summary', ws],
    queryFn: () => getWeeklySummary(ws),
  });

  const target = targetData?.data?.data ?? null;
  const summary = summaryData?.data ?? null;

  const imageTarget  = target?.image_target  ?? 0;
  const videoTarget  = target?.video_target  ?? 0;
  const imageDone    = summary?.image_achieved ?? 0;
  const videoDone    = summary?.video_achieved ?? 0;
  const imagePercent = imageTarget > 0 ? Math.min(100, Math.round((imageDone / imageTarget) * 100)) : 0;
  const videoPercent = videoTarget > 0 ? Math.min(100, Math.round((videoDone / videoTarget) * 100)) : 0;

  const daily = summary?.daily ?? [];

  return (
    <Stack>
      <Group justify="space-between">
        <Group gap="xs">
          <ActionIcon variant="default" onClick={() => setWeekOffset(o => o - 1)}>‹</ActionIcon>
          <Text fw={500} size="sm">{dayjs(ws).format('D MMM')} – {dayjs(we).format('D MMM YYYY')}</Text>
          <ActionIcon variant="default" onClick={() => setWeekOffset(o => o + 1)}>›</ActionIcon>
          {weekOffset !== 0 && <Button size="xs" variant="light" onClick={() => setWeekOffset(0)}>This week</Button>}
        </Group>
        {can('social.settings') && (
          <Button size="sm" leftSection={<IconTarget size={16} />} onClick={openTarget}>
            {target ? 'Edit Target' : 'Set Target'}
          </Button>
        )}
      </Group>

      {isLoading ? <Center py="xl"><Loader /></Center> : !target ? (
        <Text c="dimmed" ta="center" py="md">No target set yet.</Text>
      ) : (
        <Stack gap="md">
          <Paper withBorder p="md" radius="md">
            <Stack gap="sm">
              <Group justify="space-between">
                <Group gap="xs">
                  <ThemeIcon size="sm" variant="light" color="blue"><IconPhoto size={14} /></ThemeIcon>
                  <Text fw={500} size="sm">Image Posts</Text>
                </Group>
                <Badge size="lg" color={imagePercent >= 100 ? 'green' : imagePercent >= 50 ? 'yellow' : 'red'} variant="light">
                  {imageDone} / {imageTarget}
                </Badge>
              </Group>
              <Progress value={imagePercent} color={imagePercent >= 100 ? 'green' : imagePercent >= 50 ? 'yellow' : 'red'} size="sm" />

              <Group justify="space-between" mt="xs">
                <Group gap="xs">
                  <ThemeIcon size="sm" variant="light" color="grape"><IconVideo size={14} /></ThemeIcon>
                  <Text fw={500} size="sm">Video Posts</Text>
                </Group>
                <Badge size="lg" color={videoPercent >= 100 ? 'green' : videoPercent >= 50 ? 'yellow' : 'red'} variant="light">
                  {videoDone} / {videoTarget}
                </Badge>
              </Group>
              <Progress value={videoPercent} color={videoPercent >= 100 ? 'green' : videoPercent >= 50 ? 'yellow' : 'red'} size="sm" />
            </Stack>
          </Paper>

          {daily.length > 0 && (
            <SimpleGrid cols={7} spacing="xs">
              {daily.map(day => (
                <Stack key={day.date} gap={2} align="center">
                  <Text size="xs" c="dimmed" fw={500}>{day.day_name}</Text>
                  <ThemeIcon size="sm"
                    variant={!day.is_active ? 'subtle' : day.total > 0 ? 'filled' : 'light'}
                    color={!day.is_active ? 'gray' : day.total > 0 ? 'green' : 'red'}>
                    {!day.is_active ? <IconX size={10} /> : day.total > 0 ? <IconCheck size={10} /> : <Text size={9}>0</Text>}
                  </ThemeIcon>
                  {day.is_active && (
                    <Text size={9} c="dimmed">{day.images}🖼 {day.videos}🎬</Text>
                  )}
                </Stack>
              ))}
            </SimpleGrid>
          )}
        </Stack>
      )}

      <TargetFormModal opened={targetModal} onClose={closeTarget} existing={target} />
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


function TargetFormModal({ opened, onClose, existing }: {
  opened: boolean; onClose: () => void; existing: SocialTarget | null;
}) {
  const qc = useQueryClient();

  const form = useForm({
    initialValues: {
      image_target:   existing?.image_target  ?? 3,
      video_target:   existing?.video_target  ?? 2,
      active_days:    existing?.active_days   ?? [1, 2, 3, 4, 5],
      effective_from: existing?.effective_from ? new Date(existing.effective_from) : new Date() as Date | null,
    },
    validate: {
      active_days: v => v.length === 0 ? 'Select at least one day' : null,
    },
  });

  useEffect(() => {
    if (existing) {
      form.setValues({
        image_target:   existing.image_target,
        video_target:   existing.video_target,
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
      qc.invalidateQueries({ queryKey: ['social-target'] });
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
        image_target:   v.image_target,
        video_target:   v.video_target,
        active_days:    v.active_days,
        effective_from: dayjs(v.effective_from!).format('YYYY-MM-DD'),
      }))}>
        <Stack gap="md">
          <Group grow>
            <NumberInput
              label="Image posts per week"
              leftSection={<IconPhoto size={14} />}
              min={0} max={100}
              {...form.getInputProps('image_target')}
            />
            <NumberInput
              label="Video posts per week"
              leftSection={<IconVideo size={14} />}
              min={0} max={100}
              {...form.getInputProps('video_target')}
            />
          </Group>

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
