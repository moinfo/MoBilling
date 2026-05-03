import api from './axios';

export const PLATFORMS = ['instagram', 'facebook', 'threads', 'x', 'tiktok'] as const;
export type Platform = typeof PLATFORMS[number];

export const POST_TYPES = ['product_education', 'holiday', 'employee_birthday', 'promotion', 'announcement', 'general'] as const;
export type PostType = typeof POST_TYPES[number];

export const POST_FORMATS = ['feed_post', 'reel', 'story', 'carousel'] as const;
export type PostFormat = typeof POST_FORMATS[number];

export const MEDIA_TYPES = ['image', 'video'] as const;
export type MediaType = typeof MEDIA_TYPES[number];

export const TYPE_LABELS: Record<PostType, string> = {
  product_education: 'Product Education',
  holiday:           'Holiday Wishes',
  employee_birthday: 'Employee Birthday',
  promotion:         'Promotion',
  announcement:      'Announcement',
  general:           'General',
};

export const FORMAT_LABELS: Record<PostFormat, string> = {
  feed_post: 'Feed Post',
  reel:      'Reel',
  story:     'Story',
  carousel:  'Carousel',
};

export const FORMAT_COLORS: Record<PostFormat, string> = {
  feed_post: 'blue',
  reel:      'violet',
  story:     'orange',
  carousel:  'cyan',
};

export const PLATFORM_LABELS: Record<Platform, string> = {
  instagram: 'Instagram',
  facebook:  'Facebook',
  threads:   'Threads',
  x:         'X (Twitter)',
  tiktok:    'TikTok',
};

export const DAY_NAMES = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']; // index = ISO weekday

export type DesignStatus  = 'pending' | 'in_progress' | 'done';
export type ContentStatus = 'pending' | 'ready';
export type PostStatus    = 'planned' | 'designing' | 'content_ready' | 'partial_posted' | 'posted';

export interface PlatformRow {
  platform:  Platform;
  posted:    boolean;
  posted_at: string | null;
  post_url:  string | null;
}

export interface SocialPost {
  id:                 string;
  title:              string;
  type:               PostType;
  post_format:        PostFormat[];  // multiple formats allowed
  media_type:         MediaType;
  scheduled_date:     string;
  scheduled_time:     string | null;  // HH:MM
  brief:              string | null;
  caption:            string | null;
  hashtags:           string | null;
  design_file_url:    string | null;
  design_notes:       string | null;
  design_status:      DesignStatus;
  content_status:     ContentStatus;
  status:             PostStatus;
  platforms:          Record<Platform, PlatformRow>;
  created_at:         string;
}

export interface SocialTarget {
  id:             string;
  image_target:   number;  // posters per week
  video_target:   number;  // videos per week
  active_days:    number[];  // ISO 1=Mon … 7=Sun
  effective_from: string;
}

export interface DailyBreakdown {
  date:      string;
  day_name:  string;
  is_active: boolean;
  images:    number;
  videos:    number;
  total:     number;
}

export interface WeeklySummary {
  week_start:     string;
  week_end:       string;
  target:         SocialTarget | null;
  image_achieved: number;
  video_achieved: number;
  daily:          DailyBreakdown[];
}

// Posts
export const getPosts = (params?: { week_start?: string; status?: string; type?: string }) =>
  api.get<{ data: SocialPost[] }>('/social/posts', { params });

export const createPost = (data: {
  title: string; type: PostType; post_format?: PostFormat[]; media_type?: MediaType;
  scheduled_date: string; scheduled_time?: string;
  brief?: string; hashtags?: string;
}) => api.post<{ data: SocialPost }>('/social/posts', data);

export const updatePost = (id: string, data: Partial<{
  title: string; type: PostType; post_format: PostFormat[]; media_type: MediaType;
  scheduled_date: string; scheduled_time: string;
  brief: string; hashtags: string;
}>) => api.put<{ data: SocialPost }>(`/social/posts/${id}`, data);

export const deletePost = (id: string) =>
  api.delete(`/social/posts/${id}`);

export const updateDesign = (id: string, data: { design_status: DesignStatus; design_notes?: string; design_file_url?: string }) =>
  api.patch<{ data: SocialPost }>(`/social/posts/${id}/design`, data);

export const updateContent = (id: string, data: { content_status: ContentStatus; caption?: string; hashtags?: string }) =>
  api.patch<{ data: SocialPost }>(`/social/posts/${id}/content`, data);

export const togglePlatform = (id: string, platform: Platform, data: { posted: boolean; post_url?: string }) =>
  api.patch<{ data: SocialPost }>(`/social/posts/${id}/platform/${platform}`, data);

// Targets
export const getTarget = () =>
  api.get<{ data: SocialTarget | null }>('/social/targets');

export const upsertTarget = (data: {
  image_target: number; video_target: number;
  active_days: number[]; effective_from: string;
}) => api.post<{ data: SocialTarget }>('/social/targets', data);

export const deleteTarget = (id: string) =>
  api.delete(`/social/targets/${id}`);

// Weekly summary
export const getWeeklySummary = (weekStart: string) =>
  api.get<WeeklySummary>('/social/weekly-summary', { params: { week_start: weekStart } });

// ── Platform Settings ───────────────────────────────────────────────────────

export interface SocialPlatformConfig {
  id:          string;
  name:        string;  // slug: 'instagram'
  label:       string;  // display: 'Instagram'
  color:       string;  // Mantine color name
  icon:        string;  // Tabler icon key: 'brand-instagram'
  profile_url: string | null;
  is_active:   boolean;
  sort_order:  number;
}

export const KNOWN_ICONS = [
  { value: 'brand-instagram', label: 'Instagram' },
  { value: 'brand-facebook',  label: 'Facebook' },
  { value: 'brand-threads',   label: 'Threads' },
  { value: 'brand-x',         label: 'X (Twitter)' },
  { value: 'brand-tiktok',    label: 'TikTok' },
  { value: 'brand-linkedin',  label: 'LinkedIn' },
  { value: 'brand-youtube',   label: 'YouTube' },
  { value: 'brand-whatsapp',  label: 'WhatsApp' },
  { value: 'brand-telegram',  label: 'Telegram' },
  { value: 'brand-snapchat',  label: 'Snapchat' },
  { value: 'brand-pinterest', label: 'Pinterest' },
  { value: 'brand-twitter',   label: 'Twitter' },
  { value: 'globe',           label: 'Globe / Other' },
] as const;

export const MANTINE_COLORS = [
  'blue', 'cyan', 'teal', 'green', 'lime', 'yellow', 'orange', 'red',
  'pink', 'grape', 'violet', 'indigo', 'dark', 'gray',
];

export const getSocialPlatforms = () =>
  api.get<{ data: SocialPlatformConfig[] }>('/social/platforms');

export const createSocialPlatform = (data: Partial<SocialPlatformConfig>) =>
  api.post<{ data: SocialPlatformConfig }>('/social/platforms', data);

export const updateSocialPlatform = (id: string, data: Partial<SocialPlatformConfig>) =>
  api.put<{ data: SocialPlatformConfig }>(`/social/platforms/${id}`, data);

export const deleteSocialPlatform = (id: string) =>
  api.delete(`/social/platforms/${id}`);

// ── Client Design Orders ────────────────────────────────────────────────────

export const DESIGN_TYPES = [
  'logo', 'flyer', 'brochure', 'business_card', 'banner',
  'book_cover', 'label_poster', 'social_media_graphic', 'merchandise', 'other',
] as const;
export type DesignType = typeof DESIGN_TYPES[number];

export const DESIGN_TYPE_LABELS: Record<DesignType, string> = {
  logo:                 'Logo Designing',
  flyer:                'Flyer Designing',
  brochure:             'Brochure Designing',
  business_card:        'Business Cards',
  banner:               'Banner Designing',
  book_cover:           'Book Cover',
  label_poster:         'Label Poster',
  social_media_graphic: 'Social Media Graphic',
  merchandise:          'Merchandise Design',
  other:                'Other',
};

export const DESIGN_TYPE_COLORS: Record<DesignType, string> = {
  logo:                 'violet',
  flyer:                'blue',
  brochure:             'cyan',
  business_card:        'teal',
  banner:               'green',
  book_cover:           'orange',
  label_poster:         'red',
  social_media_graphic: 'pink',
  merchandise:          'grape',
  other:                'gray',
};

export const DESIGN_ORDER_STATUSES = ['pending', 'in_progress', 'needs_revision', 'done', 'delivered'] as const;
export type DesignOrderStatus = typeof DESIGN_ORDER_STATUSES[number];

export const DESIGN_ORDER_STATUS_LABELS: Record<DesignOrderStatus, string> = {
  pending:        'Pending',
  in_progress:    'In Progress',
  needs_revision: 'Needs Revision',
  done:           'Done',
  delivered:      'Delivered',
};

export const DESIGN_ORDER_STATUS_COLORS: Record<DesignOrderStatus, string> = {
  pending:        'gray',
  in_progress:    'yellow',
  needs_revision: 'orange',
  done:           'green',
  delivered:      'teal',
};

export interface ClientDesignOrder {
  id:             string;
  title:          string;
  design_type:    DesignType;
  description:    string | null;
  reference_url:  string | null;
  client:         { id: string; name: string } | null;
  designer:       { id: string; name: string } | null;
  status:         DesignOrderStatus;
  due_date:       string | null;
  is_overdue:     boolean;
  file_url:       string | null;
  revision_count: number;
  revision_notes: string | null;
  price:          string | null;
  created_at:     string;
}

export const getDesignOrders = (params?: { status?: string; design_type?: string; designer_id?: string }) =>
  api.get<{ data: ClientDesignOrder[] }>('/social/design-orders', { params });

export const createDesignOrder = (data: {
  title: string; design_type: DesignType; client_id?: string;
  description?: string; reference_url?: string;
  assigned_designer_id?: string; due_date?: string; price?: number;
}) => api.post<{ data: ClientDesignOrder }>('/social/design-orders', data);

export const updateDesignOrder = (id: string, data: Partial<{
  title: string; design_type: DesignType; client_id: string;
  description: string; reference_url: string;
  assigned_designer_id: string; status: DesignOrderStatus;
  due_date: string; file_url: string; revision_notes: string; price: number;
}>) => api.put<{ data: ClientDesignOrder }>(`/social/design-orders/${id}`, data);

export const deleteDesignOrder = (id: string) =>
  api.delete(`/social/design-orders/${id}`);
