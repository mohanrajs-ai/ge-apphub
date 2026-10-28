/**
 * Unit and integration tests for SearchFilterBar, AppCard, CatalogGrid, and App.
 */

import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import * as apiClient from '../api/client';
import { App } from '../App';
import { CatalogApplication } from '../types/catalog';

const WORKFORCE_OIDC_LAUNCH_URL =
  'https://auth.cloud.google/signin/locations/global/workforcePools/mohan-entra-id-oidc-pool/providers/entra-id-oidc-pool-provider?continueUrl=https%3A%2F%2Fvertexaisearch.cloud.google%2Fhome%2Fcid%2Fa8265c54-515b-413b-aaa2-828f0d65d29e&hl=en_US';

const SAMPLE_APPS: CatalogApplication[] = [
  {
    engine_id: 'ge-enterprise-search',
    display_name: 'Gemini Enterprise Knowledge Search',
    description:
      'Search across Confluence, Google Drive, and internal wikis with citations.',
    category: 'Productivity',
    department: 'Organization-Wide',
    tags: ['search', 'knowledge-base', 'workspace'],
    icon_name: 'Search',
    launch_url: WORKFORCE_OIDC_LAUNCH_URL,
    location: 'global',
    solution_type: 'SOLUTION_TYPE_SEARCH',
    allowed_roles: ['*'],
    featured: true,
  },
  {
    engine_id: 'ge-finops-insights',
    display_name: 'Cloud FinOps & Spend Intelligence Agent',
    description:
      'Analyze GCP billing trends and identify idle cloud resources.',
    category: 'Data & Analytics',
    department: 'Finance',
    tags: ['finops', 'bigquery', 'analytics'],
    icon_name: 'BarChart3',
    launch_url:
      'https://console.cloud.google.com/gen-app-builder/engines/ge-finops-insights',
    location: 'us',
    solution_type: 'SOLUTION_TYPE_GENERATIVE_CHAT',
    allowed_roles: ['*'],
    featured: false,
  },
];

describe('Gemini Enterprise AppHub Catalog View', () => {
  beforeEach(() => {
    vi.restoreAllMocks();
  });

  it('loads application cards and opens a centered popup window on Launch App click', async () => {
    const openSpy = vi.spyOn(window, 'open').mockImplementation(() => null);
    vi.spyOn(apiClient, 'fetchCurrentUser').mockResolvedValue({
      email: 'developer@enterprise.example.com',
      user_id: 'dev-user-001',
      roles: ['employee'],
      auth_source: 'mock_default',
    });
    vi.spyOn(apiClient, 'fetchApps').mockResolvedValue({
      items: SAMPLE_APPS,
      total: 2,
      categories: ['Data & Analytics', 'Productivity'],
      departments: ['Finance', 'Organization-Wide'],
    });

    render(<App />);

    await waitFor(() => {
      expect(
        screen.getByText('Gemini Enterprise Knowledge Search'),
      ).toBeInTheDocument();
    });

    expect(
      screen.getByText('Cloud FinOps & Spend Intelligence Agent'),
    ).toBeInTheDocument();

    const launchButtons = screen.getAllByRole('button', {
      name: /launch app/i,
    });
    expect(launchButtons).toHaveLength(2);

    fireEvent.click(launchButtons[0]);

    expect(openSpy).toHaveBeenCalledTimes(1);
    expect(openSpy).toHaveBeenCalledWith(
      WORKFORCE_OIDC_LAUNCH_URL,
      'ge_app_ge-enterprise-search',
      expect.stringContaining('popup=yes,width=1280,height=820'),
    );
  });

  it('filters applications in real time by search query, category, department, and tag', async () => {
    vi.spyOn(apiClient, 'fetchCurrentUser').mockResolvedValue({
      email: 'developer@enterprise.example.com',
      user_id: 'dev-user-001',
      roles: ['employee'],
      auth_source: 'mock_default',
    });
    vi.spyOn(apiClient, 'fetchApps').mockResolvedValue({
      items: SAMPLE_APPS,
      total: 2,
      categories: ['Data & Analytics', 'Productivity'],
      departments: ['Finance', 'Organization-Wide'],
    });

    render(<App />);

    await waitFor(() => {
      expect(
        screen.getByText('Gemini Enterprise Knowledge Search'),
      ).toBeInTheDocument();
    });

    const searchInput = screen.getByPlaceholderText(
      /search applications by name, description, category, or tag/i,
    );
    fireEvent.change(searchInput, { target: { value: 'FinOps' } });

    expect(
      screen.queryByText('Gemini Enterprise Knowledge Search'),
    ).not.toBeInTheDocument();
    expect(
      screen.getByText('Cloud FinOps & Spend Intelligence Agent'),
    ).toBeInTheDocument();

    const clearBtn = screen.getByRole('button', { name: /clear filters/i });
    fireEvent.click(clearBtn);

    expect(
      screen.getByText('Gemini Enterprise Knowledge Search'),
    ).toBeInTheDocument();

    const categoryButton = screen.getByRole('button', {
      name: 'Filter by category Data & Analytics',
    });
    fireEvent.click(categoryButton);
    expect(
      screen.queryByText('Gemini Enterprise Knowledge Search'),
    ).not.toBeInTheDocument();

    const departmentSelect = screen.getByLabelText(/filter by department/i);
    fireEvent.change(departmentSelect, { target: { value: 'Finance' } });
    expect(
      screen.getByText('Cloud FinOps & Spend Intelligence Agent'),
    ).toBeInTheDocument();
  });

  it('shows empty state with reset action when no applications match filters', async () => {
    vi.spyOn(apiClient, 'fetchCurrentUser').mockResolvedValue({
      email: 'developer@enterprise.example.com',
      user_id: 'dev-user-001',
      roles: ['employee'],
      auth_source: 'mock_default',
    });
    vi.spyOn(apiClient, 'fetchApps').mockResolvedValue({
      items: SAMPLE_APPS,
      total: 2,
      categories: ['Data & Analytics', 'Productivity'],
      departments: ['Finance', 'Organization-Wide'],
    });

    render(<App />);

    await waitFor(() => {
      expect(
        screen.getByText('Gemini Enterprise Knowledge Search'),
      ).toBeInTheDocument();
    });

    const searchInput = screen.getByPlaceholderText(
      /search applications by name, description, category, or tag/i,
    );
    fireEvent.change(searchInput, {
      target: { value: 'nonexistent-application-xyz' },
    });

    expect(
      screen.getByText(/no matching applications found/i),
    ).toBeInTheDocument();

    const resetButton = screen.getByRole('button', {
      name: /reset all filters/i,
    });
    fireEvent.click(resetButton);

    expect(
      screen.getByText('Gemini Enterprise Knowledge Search'),
    ).toBeInTheDocument();
  });

  it('displays error banner and retries when API request fails', async () => {
    vi.spyOn(apiClient, 'fetchCurrentUser').mockRejectedValueOnce(
      new Error('Network error'),
    );
    const fetchAppsSpy = vi
      .spyOn(apiClient, 'fetchApps')
      .mockRejectedValueOnce(new Error('Backend unavailable'))
      .mockResolvedValueOnce({
        items: SAMPLE_APPS,
        total: 2,
        categories: ['Data & Analytics', 'Productivity'],
        departments: ['Finance', 'Organization-Wide'],
      });

    render(<App />);

    await waitFor(() => {
      expect(
        screen.getByText(/unable to load application catalog/i),
      ).toBeInTheDocument();
    });

    vi.spyOn(apiClient, 'fetchCurrentUser').mockResolvedValue({
      email: 'developer@enterprise.example.com',
      user_id: 'dev-user-001',
      roles: ['employee'],
      auth_source: 'mock_default',
    });

    const retryBtn = screen.getByRole('button', { name: /retry/i });
    fireEvent.click(retryBtn);

    await waitFor(() => {
      expect(
        screen.getByText('Gemini Enterprise Knowledge Search'),
      ).toBeInTheDocument();
    });
    expect(fetchAppsSpy).toHaveBeenCalledTimes(2);
  });
});
