/**
 * Unit tests for the AppHub Header, ThemeContext, and API client.
 */

import { fireEvent, render, screen } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import {
  fetchApps,
  fetchAuthConfig,
  fetchCurrentUser,
  loginWithEmail,
  logoutUser,
} from '../api/client';
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

  it('renders Tech-M Gemini AI Hub branding, logo, and current user email', () => {
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

    const logoImg = screen.getByRole('img', { name: /Tech Mahindra Logo/i });
    expect(logoImg).toBeInTheDocument();
    expect(logoImg).toHaveAttribute(
      'src',
      'https://www.mahindra.com/sites/default/files/social-thumbnail/TM_Logo_Color_Pos_RGB.webp',
    );
    expect(screen.getByText(/Tech-M Gemini AI Hub/i)).toBeInTheDocument();
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

  it('renders Sign Out button and triggers onSignOut callback', () => {
    const onRoleChange = vi.fn();
    const onSignOut = vi.fn();
    render(
      <ThemeProvider>
        <Header
          user={{
            ...sampleUser,
            groups: ['hr-app-01-users@mohanrajs.altostrat.com'],
          }}
          activeDevRole="employee"
          onDevRoleChange={onRoleChange}
          onSignOut={onSignOut}
        />
      </ThemeProvider>,
    );

    const signOutBtn = screen.getByRole('button', { name: /sign out/i });
    fireEvent.click(signOutBtn);
    expect(onSignOut).toHaveBeenCalledTimes(1);
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

    mockFetch
      .mockResolvedValueOnce({
        ok: true,
        json: async () => ({
          google_client_id: '',
          suggested_users: [
            {
              email: 'mohanraj@mohanrajs.altostrat.com',
              label: 'Mohanraj',
              description: 'HR & Ops',
            },
          ],
        }),
      })
      .mockResolvedValueOnce({
        ok: true,
        json: async () => ({
          token: 'signed-token-123',
          user: {
            email: 'mohanraj@mohanrajs.altostrat.com',
            user_id: 'mohanraj@mohanrajs.altostrat.com',
            roles: ['employee'],
            groups: ['hr-app-01-users@mohanrajs.altostrat.com'],
            auth_source: 'session_token',
          },
        }),
      })
      .mockResolvedValueOnce({
        ok: true,
        json: async () => ({ status: 'logged_out' }),
      });

    const authCfg = await fetchAuthConfig();
    expect(authCfg.suggested_users).toHaveLength(1);

    const loginRes = await loginWithEmail('mohanraj@mohanrajs.altostrat.com');
    expect(loginRes.token).toBe('signed-token-123');

    await logoutUser();

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
