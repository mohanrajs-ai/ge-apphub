/**
 * Unit tests for the AppHub Header, ThemeContext, and API client.
 */

import { fireEvent, render, screen } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import { fetchApps, fetchCurrentUser } from '../api/client';
import { Header } from '../components/Header';
import { ThemeProvider } from '../context/ThemeContext';
import { UserContext } from '../types/catalog';

describe('Header & ThemeProvider', () => {
  const sampleUser: UserContext = {
    email: 'developer@enterprise.example.com',
    user_id: 'dev-user-001',
    roles: ['employee', 'engineering'],
    auth_source: 'mock_default',
  };

  it('renders Gemini Enterprise AppHub branding and current user email', () => {
    const onRoleChange = vi.fn();
    render(
      <ThemeProvider>
        <Header
          user={sampleUser}
          activeDevRole="employee"
          onDevRoleChange={onRoleChange}
        />
      </ThemeProvider>,
    );

    expect(
      screen.getByText(/Gemini Enterprise AppHub/i),
    ).toBeInTheDocument();
    expect(
      screen.getByText('developer@enterprise.example.com'),
    ).toBeInTheDocument();
  });

  it('toggles between light and dark theme when the theme button is clicked', () => {
    const onRoleChange = vi.fn();
    render(
      <ThemeProvider>
        <Header
          user={sampleUser}
          activeDevRole="employee"
          onDevRoleChange={onRoleChange}
        />
      </ThemeProvider>,
    );

    const toggleButton = screen.getByRole('button', {
      name: /toggle color theme/i,
    });
    expect(document.documentElement.classList.contains('dark')).toBe(false);

    fireEvent.click(toggleButton);
    expect(document.documentElement.classList.contains('dark')).toBe(true);

    fireEvent.click(toggleButton);
    expect(document.documentElement.classList.contains('dark')).toBe(false);
  });

  it('calls onDevRoleChange when the local role switcher is changed', () => {
    const onRoleChange = vi.fn();
    render(
      <ThemeProvider>
        <Header
          user={sampleUser}
          activeDevRole="employee"
          onDevRoleChange={onRoleChange}
        />
      </ThemeProvider>,
    );

    const roleSelect = screen.getByLabelText(/preview role/i);
    fireEvent.change(roleSelect, { target: { value: 'admin' } });
    expect(onRoleChange).toHaveBeenCalledWith('admin');
  });
});

describe('API Client', () => {
  it('fetches current user and catalog apps with role header', async () => {
    const mockFetch = vi.fn();
    mockFetch
      .mockResolvedValueOnce({
        ok: true,
        json: async () => ({
          email: 'alice@enterprise.example.com',
          user_id: 'alice',
          roles: ['admin'],
          auth_source: 'dev_override',
        }),
      })
      .mockResolvedValueOnce({
        ok: true,
        json: async () => ({
          items: [],
          total: 0,
          categories: ['Productivity'],
          departments: ['General'],
        }),
      });
    vi.stubGlobal('fetch', mockFetch);

    const user = await fetchCurrentUser('admin');
    expect(user.email).toBe('alice@enterprise.example.com');

    const catalog = await fetchApps({ devRole: 'admin', q: 'search' });
    expect(catalog.total).toBe(0);
    expect(mockFetch).toHaveBeenCalledTimes(2);

    vi.unstubAllGlobals();
  });

  it('throws descriptive error when API response is not ok', async () => {
    const mockFetch = vi.fn().mockResolvedValue({
      ok: false,
      status: 500,
    });
    vi.stubGlobal('fetch', mockFetch);

    await expect(fetchCurrentUser()).rejects.toThrow(/500/);
    await expect(fetchApps()).rejects.toThrow(/500/);

    vi.unstubAllGlobals();
  });
});
