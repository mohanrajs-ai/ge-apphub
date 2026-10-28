/**
 * Search and multi-faceted filter bar for the Gemini Enterprise AppHub catalog.
 */

import React from 'react';
import { Building2, Filter, Search, X } from 'lucide-react';

export interface SearchFilterBarProps {
  searchQuery: string;
  selectedCategory: string;
  selectedDepartment: string;
  selectedTag: string;
  categories: string[];
  departments: string[];
  totalCount: number;
  filteredCount: number;
  onSearchChange: (value: string) => void;
  onCategoryChange: (category: string) => void;
  onDepartmentChange: (department: string) => void;
  onClearFilters: () => void;
}

/**
 * Renders real-time search input, category chips, and department selector.
 */
export function SearchFilterBar({
  searchQuery,
  selectedCategory,
  selectedDepartment,
  selectedTag,
  categories,
  departments,
  totalCount,
  filteredCount,
  onSearchChange,
  onCategoryChange,
  onDepartmentChange,
  onClearFilters,
}: SearchFilterBarProps): React.ReactElement {
  const hasActiveFilters = Boolean(
    searchQuery.trim() ||
      selectedCategory ||
      selectedDepartment ||
      selectedTag,
  );

  return (
    <section
      aria-label="Search and filter applications"
      className="rounded-2xl border border-slate-200/90 bg-white p-5 shadow-sm dark:border-slate-800 dark:bg-slate-900"
    >
      <div className="flex flex-col gap-4 md:flex-row md:items-center">
        <div className="relative flex-1">
          <Search
            className="pointer-events-none absolute left-3.5 top-1/2 h-4 w-4 -translate-y-1/2 text-slate-400"
            aria-hidden="true"
          />
          <input
            type="search"
            value={searchQuery}
            onChange={(e) => onSearchChange(e.target.value)}
            placeholder="Search applications by name, description, category, or tag..."
            aria-label="Search applications"
            className="w-full rounded-xl border border-slate-200 bg-slate-50 py-2.5 pl-10 pr-4 text-sm text-slate-900 placeholder-slate-400 transition focus:border-blue-600 focus:bg-white focus:outline-none focus:ring-2 focus:ring-blue-500/20 dark:border-slate-700 dark:bg-slate-800/80 dark:text-white dark:placeholder-slate-400 dark:focus:border-blue-400"
          />
        </div>

        <div className="flex items-center gap-3">
          <div className="flex items-center gap-2 rounded-xl border border-slate-200 bg-slate-50 px-3 py-2 text-sm dark:border-slate-700 dark:bg-slate-800/80">
            <Building2
              className="h-4 w-4 text-slate-400"
              aria-hidden="true"
            />
            <label htmlFor="department-filter" className="sr-only">
              Filter by department
            </label>
            <select
              id="department-filter"
              aria-label="Filter by department"
              value={selectedDepartment}
              onChange={(e) => onDepartmentChange(e.target.value)}
              className="bg-transparent text-sm font-medium text-slate-700 focus:outline-none dark:text-slate-200"
            >
              <option
                value=""
                className="bg-white text-slate-900 dark:bg-slate-900 dark:text-white"
              >
                All Departments
              </option>
              {departments.map((dept) => (
                <option
                  key={dept}
                  value={dept}
                  className="bg-white text-slate-900 dark:bg-slate-900 dark:text-white"
                >
                  {dept}
                </option>
              ))}
            </select>
          </div>

          {hasActiveFilters && (
            <button
              type="button"
              onClick={onClearFilters}
              className="inline-flex items-center gap-1.5 rounded-xl border border-slate-200 bg-white px-3 py-2 text-xs font-medium text-slate-700 transition hover:bg-slate-100 dark:border-slate-700 dark:bg-slate-800 dark:text-slate-200 dark:hover:bg-slate-700"
            >
              <X className="h-3.5 w-3.5" aria-hidden="true" />
              Clear Filters
            </button>
          )}
        </div>
      </div>

      <div className="mt-4 flex flex-wrap items-center justify-between gap-3 border-t border-slate-100 pt-3.5 dark:border-slate-800">
        <div className="flex flex-wrap items-center gap-2">
          <span className="inline-flex items-center gap-1 text-xs font-medium text-slate-500 dark:text-slate-400">
            <Filter className="h-3.5 w-3.5" aria-hidden="true" />
            Category:
          </span>
          <button
            type="button"
            onClick={() => onCategoryChange('')}
            className={`rounded-full px-3 py-1 text-xs font-medium transition ${
              selectedCategory === ''
                ? 'bg-blue-600 text-white shadow-sm'
                : 'bg-slate-100 text-slate-700 hover:bg-slate-200 dark:bg-slate-800 dark:text-slate-300 dark:hover:bg-slate-700'
            }`}
          >
            All Categories
          </button>
          {categories.map((cat) => {
            const isActive = selectedCategory === cat;
            return (
              <button
                key={cat}
                type="button"
                aria-label={`Filter by category ${cat}`}
                onClick={() => onCategoryChange(isActive ? '' : cat)}
                className={`rounded-full px-3 py-1 text-xs font-medium transition ${
                  isActive
                    ? 'bg-blue-600 text-white shadow-sm'
                    : 'bg-slate-100 text-slate-700 hover:bg-slate-200 dark:bg-slate-800 dark:text-slate-300 dark:hover:bg-slate-700'
                }`}
              >
                {cat}
              </button>
            );
          })}
        </div>

        <p className="text-xs font-medium text-slate-500 dark:text-slate-400">
          Showing <span className="text-slate-900 dark:text-white">{filteredCount}</span> of{' '}
          <span className="text-slate-900 dark:text-white">{totalCount}</span>{' '}
          applications
        </p>
      </div>
    </section>
  );
}
