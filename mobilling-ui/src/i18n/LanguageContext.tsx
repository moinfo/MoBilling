import {
  createContext,
  useContext,
  useState,
  useEffect,
  useCallback,
  type ReactNode,
} from 'react';
import type { Language } from './types';
import { en } from './en';
import { sw } from './sw';

/**
 * Portal i18n.
 *
 * Deliberately the same lightweight Context approach as moinfo.co.tz — flat
 * key maps, localStorage under "lang", no external library — so the two apps
 * behave identically and a key can be moved between them unchanged.
 *
 * Sharing the storage key matters: a customer who picks Swahili on the
 * marketing site and clicks through to the portal keeps their choice, because
 * both apps read the same value from the same origin family.
 */
interface LanguageContextType {
  language: Language;
  setLanguage: (lang: Language) => void;
  t: (key: string) => string;
}

const translations: Record<Language, Record<string, string>> = { en, sw };

const LanguageContext = createContext<LanguageContextType>({
  language: 'en',
  setLanguage: () => {},
  t: (key) => key,
});

export function LanguageProvider({ children }: { children: ReactNode }) {
  const [language, setLanguageState] = useState<Language>('en');

  useEffect(() => {
    const saved = localStorage.getItem('lang');
    if (saved === 'en' || saved === 'sw') setLanguageState(saved);
  }, []);

  useEffect(() => {
    document.documentElement.lang = language;
  }, [language]);

  const setLanguage = useCallback((lang: Language) => {
    setLanguageState(lang);
    localStorage.setItem('lang', lang);
  }, []);

  // Falls back to English, then to the key itself — a missing translation
  // shows readable English rather than a blank or a raw key.
  const t = useCallback(
    (key: string): string => translations[language][key] ?? translations.en[key] ?? key,
    [language],
  );

  return (
    <LanguageContext.Provider value={{ language, setLanguage, t }}>
      {children}
    </LanguageContext.Provider>
  );
}

export function useLanguage() {
  return useContext(LanguageContext);
}
