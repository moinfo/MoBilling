import axios from 'axios';

const api = axios.create({
  baseURL: import.meta.env.VITE_API_URL || 'http://localhost:8000/api',
  headers: { 'Content-Type': 'application/json' },
});

api.interceptors.request.use((config) => {
  if (!config.headers.Authorization) {
    const token = localStorage.getItem('token');
    if (token) config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});

api.interceptors.response.use(
  (response) => response,
  (error) => {
    if (error.response?.status === 401) {
      localStorage.removeItem('token');
      // clients land on the client-area login; staff on the main login
      // (note the trailing slash — /portal-users is a STAFF page, not /portal/*)
      window.location.href = window.location.pathname.startsWith('/portal/')
        ? '/portal/login'
        : '/login';
    }

    // Subscription expired — redirect to payment page
    if (error.response?.status === 402) {
      if (!window.location.pathname.startsWith('/subscription')) {
        window.location.href = '/subscription/expired';
      }
    }

    // Self-hosted install's license failed license:check — redirect to its own explanatory page
    if (error.response?.status === 403 && error.response?.data?.code === 'LICENSE_INACTIVE') {
      if (window.location.pathname !== '/license-inactive') {
        window.location.href = '/license-inactive';
      }
    }

    return Promise.reject(error);
  }
);

export default api;
