import { ref, onMounted } from 'vue';
import { CATEGORIES_META, FAQS } from '../data/helpData.js';

const ARTICLES_URL   = '/public/api/v1/help_articles';
const CATEGORIES_URL = '/public/api/v1/help_articles/categories';
const FAQS_URL       = '/public/api/v1/help_articles/faqs';

export function useHelpData() {
  const categories = ref(
    CATEGORIES_META.map(c => ({
      ...c,
      iconSvg:  null,
      hidden:   c.hidden ?? false,
      articles: c.articles ?? [],
      count:    c.articles?.length ?? 0,
    }))
  );
  const faqs    = ref(FAQS);
  const loading = ref(true);
  const error   = ref(null);

  async function fetchData() {
    try {
      // Use allSettled so a failing fetch (e.g. faqs table not yet migrated)
      // never blocks the others from updating categories/articles.
      const [catResult, artResult, faqResult] = await Promise.allSettled([
        fetch(CATEGORIES_URL).then(r => (r.ok ? r.json() : null)),
        fetch(ARTICLES_URL).then(r => (r.ok ? r.json() : [])),
        fetch(FAQS_URL).then(r => (r.ok ? r.json() : [])),
      ]);

      const catData  = catResult.status  === 'fulfilled' ? catResult.value  : null;
      const articles = artResult.status  === 'fulfilled' ? (artResult.value  ?? []) : [];
      const faqData  = faqResult.status  === 'fulfilled' ? (faqResult.value  ?? []) : [];

      if (faqData.length > 0) faqs.value = faqData;

      // Group articles by category slug
      const grouped = {};
      articles.forEach(art => {
        if (!grouped[art.category]) grouped[art.category] = [];
        grouped[art.category].push(normalizeArticle(art));
      });

      // Build category list from API (preferred) or fall back to CATEGORIES_META
      const baseCats = catData && catData.length > 0
        ? catData.map(c => ({
            id:          c.id,
            name:        c.name,
            description: c.description,
            icon:        c.icon_class ?? '',
            iconSvg:     c.icon_svg ?? null,
            hidden:      c.hidden ?? false,
          }))
        : CATEGORIES_META.map(c => ({
            id:          c.id,
            name:        c.name,
            description: c.description,
            icon:        c.icon ?? '',
            iconSvg:     null,
            hidden:      c.hidden ?? false,
          }));

      // Always update when we have any API response (articles OR categories)
      if (baseCats.length > 0) {
        categories.value = baseCats.map(cat => ({
          ...cat,
          articles: grouped[cat.id] ?? [],
          count:    (grouped[cat.id] ?? []).length,
        }));
      }
    } catch (e) {
      error.value = e.message;
    } finally {
      loading.value = false;
    }
  }

  onMounted(fetchData);

  return { categories, faqs, loading, error };
}

function normalizeArticle(art) {
  return {
    id:        art.id,
    title:     art.title,
    body:      art.body ?? '',
    time:      art.reading_time ?? 'Leitura rápida',
    videoUrl:  art.video_url ?? null,
    nextSteps: art.next_steps ?? '',
  };
}
