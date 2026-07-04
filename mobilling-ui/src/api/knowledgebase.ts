import api from './axios';

// ── Admin types ────────────────────────────────────────────────────────────
export interface KbCategoryRow {
  id: string;
  name: string;
  slug: string;
  description: string | null;
  sort_order: number;
  is_active: boolean;
  articles_count: number;
  created_at: string;
}

export interface KbArticleRow {
  id: string;
  kb_category_id: string | null;
  category_name: string | null;
  title: string;
  slug: string;
  body: string;
  is_published: boolean;
  views: number;
  sort_order: number;
  created_at: string;
}

// ── Admin: categories ──────────────────────────────────────────────────────
export const getKbCategories = () => api.get<{ data: KbCategoryRow[] }>('/kb/categories');
export const createKbCategory = (data: Partial<{ name: string; description: string | null; sort_order: number; is_active: boolean }>) =>
  api.post('/kb/categories', data);
export const updateKbCategory = (id: string, data: Partial<{ name: string; description: string | null; sort_order: number; is_active: boolean }>) =>
  api.put(`/kb/categories/${id}`, data);
export const deleteKbCategory = (id: string) => api.delete(`/kb/categories/${id}`);

// ── Admin: articles ────────────────────────────────────────────────────────
export const getKbArticles = (categoryId?: string) =>
  api.get<{ data: KbArticleRow[] }>('/kb/articles', { params: categoryId ? { category_id: categoryId } : {} });
export const createKbArticle = (data: Partial<{ kb_category_id: string | null; title: string; body: string; is_published: boolean; sort_order: number }>) =>
  api.post('/kb/articles', data);
export const updateKbArticle = (id: string, data: Partial<{ kb_category_id: string | null; title: string; body: string; is_published: boolean; sort_order: number }>) =>
  api.put(`/kb/articles/${id}`, data);
export const deleteKbArticle = (id: string) => api.delete(`/kb/articles/${id}`);

// ── Portal types ───────────────────────────────────────────────────────────
export interface PortalKbArticleSummary {
  id: string;
  title: string;
  slug: string;
  views: number;
  excerpt: string;
}

export interface PortalKbCategory {
  id: string | null;
  name: string;
  slug: string;
  description: string | null;
  articles: PortalKbArticleSummary[];
}

export interface PortalKbArticle {
  id: string;
  title: string;
  slug: string;
  body: string;
  views: number;
  category_name: string | null;
  category_slug: string | null;
  created_at: string;
  updated_at: string;
}

// ── Portal ─────────────────────────────────────────────────────────────────
export const getPortalKnowledgebase = (search?: string) =>
  api.get<{ data: PortalKbCategory[] }>('/portal/knowledgebase', { params: search ? { search } : {} });
export const getPortalKbArticle = (slug: string) =>
  api.get<{ data: PortalKbArticle }>(`/portal/knowledgebase/${slug}`);
