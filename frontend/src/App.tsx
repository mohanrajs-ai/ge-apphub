/**
 * Root application component for Gemini Enterprise AppHub.
 */

import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { AlertCircle, RefreshCw } from 'lucide-react';
import { fetchApps, fetchCurrentUser } from './api/client';
import { CatalogGrid } from './components/CatalogGrid';
import { Header } from './components/Header';
import { SearchFilterBar } from './components/SearchFilterBar';
import { ThemeProvider } from './context/ThemeContext';
import { CatalogApplication, UserContext } from './types/catalog';

function filterAppsClientSide(
  apps: CatalogApplication[],
  searchQuery: string,
  category: string,
  department: string,
  tag: string,
): CatalogApplication[] {
  const needle = searchQuery.trim().toLowerCase();
  return apps.filter((app) => {
    if (category && app.category !== category) {
      return false;
    }
    if (department && app.department !== department) {
      return false;
    }
    if (tag && !app.tags.includes(tag)) {
      return false;
    }
    if (!needle) {
      return true;
    }
    const searchable = [
      app.display_name,
      app.description,
      app.category,
      app.department,
      app.engine_id,
      ...app.tags,
    ]
      .join(' ')
      .toLowerCase();
    return searchable.includes(needle);
  });
}

/**
 * Main portal layout and catalog state container wrapped in ThemeProvider.
 */
export function App(): React.ReactElement {
  const [user, setUser] = useState<UserContext | null>(null);
  const [apps, setApps] = useState<CatalogApplication[]>([]);
  const [categories, setCategories] = useState<string[]>([]);
  const [departments, setDepartments] = useState<string[]>([]);
  const [activeDevRole, setActiveDevRole] = useState<string>('employee');
  const [searchQuery, setSearchQuery] = useState<string>('');
  const [selectedCategory, setSelectedCategory] = useState<string>('');
  const [selectedDepartment, setSelectedDepartment] = useState<string>('');
  const [selectedTag, setSelectedTag] = useState<string>('');
  const [loading, setLoading] = useState<boolean>(true);
  const [error, setError] = useState<string | null>(null);

  const loadCatalogData = useCallback(async (role: string) => {
    setLoading(true);
    setError(null);
    try {
      const [userRes, catalogRes] = await Promise.all([
        fetchCurrentUser(role),
        fetchApps({ devRole: role }),
      ]);
      setUser(userRes);
      setApps(catalogRes.items);
      setCategories(catalogRes.categories);
      setDepartments(catalogRes.departments);
    } catch (err) {
      const message =
        err instanceof Error ? err.message : 'Unexpected backend error';
      setError(message);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void loadCatalogData(activeDevRole);
  }, [activeDevRole, loadCatalogData]);

  const filteredApps = useMemo(
    () =>
      filterAppsClientSide(
        apps,
        searchQuery,
        selectedCategory,
        selectedDepartment,
        selectedTag,
      ),
    [apps, searchQuery, selectedCategory, selectedDepartment, selectedTag],
  );

  function handleClearFilters(): void {
    setSearchQuery('');
    setSelectedCategory('');
    setSelectedDepartment('');
    setSelectedTag('');
  }

  return (
    <ThemeProvider>
      <div className="min-h-screen bg-slate-50 text-slate-900 transition-colors dark:bg-slate-950 dark:text-slate-100">
        <Header
          user={user}
          activeDevRole={activeDevRole}
          onDevRoleChange={setActiveDevRole}
        />

        <main className="mx-auto max-w-7xl px-4 py-8 sm:px-6 lg:px-8">
          <div className="mb-6">
            <h2 className="text-2xl font-bold tracking-tight text-slate-900 dark:text-white">
              Application Marketplace
            </h2>
            <p className="mt-1 text-sm text-slate-600 dark:text-slate-400">
              Browse, filter, and launch Gemini Enterprise agents and search
              applications tailored to your organization role.
            </p>
          </div>

          {error && (
            <div
              role="alert"
              className="mb-6 flex flex-wrap items-center justify-between gap-4 rounded-2xl border border-red-200 bg-red-50 px-5 py-4 text-sm text-red-800 dark:border-red-900/60 dark:bg-red-950/50 dark:text-red-200"
            >
              <div className="flex items-center gap-3">
                <AlertCircle className="h-5 w-5 shrink-0" aria-hidden="true" />
                <div>
                  <p className="font-semibold">
                    Unable to load application catalog
                  </p>
                  <p className="text-xs opacity-90">{error}</p>
                </div>
              </div>
              <button
                type="button"
                onClick={() => void loadCatalogData(activeDevRole)}
                className="inline-flex items-center gap-1.5 rounded-xl bg-red-600 px-3.5 py-2 text-xs font-semibold text-white shadow-sm transition hover:bg-red-700"
              >
                <RefreshCw className="h-3.5 w-3.5" aria-hidden="true" />
                Retry
              </button>
            </div>
          )}

          <SearchFilterBar
            searchQuery={searchQuery}
            selectedCategory={selectedCategory}
            selectedDepartment={selectedDepartment}
            selectedTag={selectedTag}
            categories={categories}
            departments={departments}
            totalCount={apps.length}
            filteredCount={filteredApps.length}
            onSearchChange={setSearchQuery}
            onCategoryChange={setSelectedCategory}
            onDepartmentChange={setSelectedDepartment}
            onClearFilters={handleClearFilters}
          />

          <CatalogGrid
            apps={filteredApps}
            loading={loading}
            onResetFilters={handleClearFilters}
            onSelectTag={(tag) =>
              setSelectedTag((prev) => (prev === tag ? '' : tag))
            }
          />
        </main>
      </div>
    </ThemeProvider>
  );
}
