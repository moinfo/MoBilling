import axios from 'axios';

const api = axios.create({
  baseURL: import.meta.env.VITE_API_URL || 'http://localhost:8001/api',
  headers: { 'Content-Type': 'application/json' },
});

api.interceptors.request.use((config) => {
  const token = localStorage.getItem('token');
  if (token) config.headers.Authorization = `Bearer ${token}`;
  return config;
});

api.interceptors.response.use(
  (response) => response,
  (error) => {
    if (error.response?.status === 401) {
      localStorage.removeItem('token');
      window.location.href = '/login';
    }

    // Subscription expired — redirect to payment page
    if (error.response?.status === 402) {
      if (!window.location.pathname.startsWith('/subscription')) {
        window.location.href = '/subscription/expired';
      }
    }

    return Promise.reject(error);
  }
);

export default api;
