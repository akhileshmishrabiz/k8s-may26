import { render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import Home from './components/Home';

beforeEach(() => {
  global.fetch = jest.fn((url) => {
    if (url.includes('/api/topics')) {
      return Promise.resolve({
        ok: true,
        headers: { get: () => 'application/json' },
        json: () => Promise.resolve([]),
      });
    }
    if (url.includes('/api/leaderboard/recent')) {
      return Promise.resolve({
        ok: true,
        headers: { get: () => 'application/json' },
        json: () => Promise.resolve({ entries: [] }),
      });
    }
    if (url.includes('/api/leaderboard/stats')) {
      return Promise.resolve({
        ok: true,
        headers: { get: () => 'application/json' },
        json: () => Promise.resolve({ total_attempts: 0 }),
      });
    }
    return Promise.resolve({
      ok: true,
      headers: { get: () => 'application/json' },
      json: () => Promise.resolve({}),
    });
  });
});

test('renders DevOps Dojo heading', async () => {
  render(
    <MemoryRouter>
      <Home />
    </MemoryRouter>
  );
  await waitFor(() => {
    expect(screen.getByText(/DevOps Dojo/i)).toBeInTheDocument();
  });
});
