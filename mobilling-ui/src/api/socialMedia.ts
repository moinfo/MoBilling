import api from './axios';

export const PLATFORMS = ['instagram', 'facebook', 'threads', 'x', 'tiktok'] as const;
export type Platform = typeof PLATFORMS[number];

export const POST_TYPES = ['product_education', 'holiday', 'employee_birthday', 'promotion', 'announcement', 'general'] as const;
export type PostType = typeof POST_TYPES[number];

export const TYPE_LABELS: Record<PostType, string> = {
  product_education: 'Product Education',
  holiday:           'Holiday Wishes',
  employee_birthday: 'Employee Birthday',
  promotion:         'Promotion',
  announcement:      'Announcement',
  general:           'General',
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
  scheduled_date:     string;
  brief:              string | null;
  caption:            string | null;
  design_file_url:    string | null;
  design_notes:       string | null;
  assigned_designer:  { id: string; name: string } | null;
  assigned_creator:   { id: string; name: string } | null;
  design_status:      DesignStatus;
  content_status:     ContentStatus;
  status:             PostStatus;
  platforms:          Record<Platform, PlatformRow>;
  created_at:         string;
}

export interface SocialTarget {
  id:             string;
  user:           { id: string; name: string } | null;
  metric:         'designs' | 'posts';
  weekly_target:  number;
  daily_target:   number;
  active_days:    number[];  // ISO 1=Mon … 7=Sun
  effective_from: string;
}

export interface DailyBreakdown {
  date:      string;
  day_name:  string;
  is_active: boolean;
  target:    number;
  achieved:  number;
  met:       boolean;
}

export interface WeeklySummaryEntry {
  target:          SocialTarget;
  weekly_achieved: number;
  weekly_target:   number;
  percent:         number;
  daily:           DailyBreakdown[];
}

// Posts
export const getPosts = (params?: { week_start?: string; status?: string; type?: string }) =>
  api.get<{ data: SocialPost[] }>('/social/posts', { params });

export const createPost = (data: {
  title: string; type: PostType; scheduled_date: string;
  brief?: string; assigned_designer_id?: string; assigned_creator_id?: string;
}) => api.post<{ data: SocialPost }>('/social/posts', data);

export const updatePost = (id: string, data: Partial<{
  title: string; type: PostType; scheduled_date: string;
  brief: string; assigned_designer_id: string; assigned_creator_id: string;
}>) => api.put<{ data: SocialPost }>(`/social/posts/${id}`, data);

export const deletePost = (id: string) =>
  api.delete(`/social/posts/${id}`);

export const updateDesign = (id: string, data: { design_status: DesignStatus; design_notes?: string; design_file_url?: string }) =>
  api.patch<{ data: SocialPost }>(`/social/posts/${id}/design`, data);

export const updateContent = (id: string, data: { content_status: ContentStatus; caption?: string }) =>
  api.patch<{ data: SocialPost }>(`/social/posts/${id}/content`, data);

export const togglePlatform = (id: string, platform: Platform, data: { posted: boolean; post_url?: string }) =>
  api.patch<{ data: SocialPost }>(`/social/posts/${id}/platform/${platform}`, data);

// Targets
export const getTargets = () =>
  api.get<{ data: SocialTarget[] }>('/social/targets');

export const upsertTarget = (data: {
  user_id: string; metric: 'designs' | 'posts';
  weekly_target: number; daily_target: number;
  active_days: number[]; effective_from: string;
}) => api.post<{ data: SocialTarget }>('/social/targets', data);

export const deleteTarget = (id: string) =>
  api.delete(`/social/targets/${id}`);

// Weekly summary
export const getWeeklySummary = (weekStart: string) =>
  api.get<{ week_start: string; week_end: string; data: WeeklySummaryEntry[] }>('/social/weekly-summary', { params: { week_start: weekStart } });
