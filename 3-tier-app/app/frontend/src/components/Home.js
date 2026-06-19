import React, { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import {
  fetchLeaderboardStats,
  fetchRecentActivity,
  fetchTopics,
} from '../services/quizApi';
import { getPlayerName } from '../utils/player';

function formatTime(seconds) {
  const mins = Math.floor(seconds / 60);
  const secs = seconds % 60;
  return mins > 0 ? `${mins}m ${secs}s` : `${secs}s`;
}

function formatRelativeTime(iso) {
  const diffMs = Date.now() - new Date(iso).getTime();
  const minutes = Math.floor(diffMs / 60000);
  if (minutes < 1) return 'just now';
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  return `${days}d ago`;
}

function Home() {
  const [topics, setTopics] = useState([]);
  const [stats, setStats] = useState(null);
  const [recentActivity, setRecentActivity] = useState([]);
  const [search, setSearch] = useState('');
  const [error, setError] = useState(null);
  const [loading, setLoading] = useState(true);
  const [searchLoading, setSearchLoading] = useState(false);
  const currentPlayer = getPlayerName();

  useEffect(() => {
    let cancelled = false;

    const load = async () => {
      try {
        setSearchLoading(Boolean(search));
        const [topicsData, statsData, recentData] = await Promise.all([
          fetchTopics(search),
          fetchLeaderboardStats().catch(() => null),
          fetchRecentActivity(8).catch(() => ({ entries: [] })),
        ]);
        if (!cancelled) {
          setTopics(topicsData);
          setStats(statsData);
          setRecentActivity(recentData.entries || []);
          setError(null);
        }
      } catch (err) {
        if (!cancelled) {
          setError(err.message);
        }
      } finally {
        if (!cancelled) {
          setLoading(false);
          setSearchLoading(false);
        }
      }
    };

    const timer = setTimeout(load, search ? 300 : 0);
    return () => {
      cancelled = true;
      clearTimeout(timer);
    };
  }, [search]);

  if (loading) {
    return (
      <div className="container mx-auto px-4 py-16 flex flex-col items-center justify-center gap-3">
        <div
          className="h-8 w-8 rounded-full border-2 border-gray-200 border-t-blue-600 animate-spin"
          role="status"
          aria-label="Loading"
        />
        <p className="text-gray-500">Loading topics...</p>
      </div>
    );
  }

  if (error && topics.length === 0) {
    return (
      <div className="container mx-auto px-4 py-8">
        <div className="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded-lg">
          <p>Error loading platform: {error}</p>
          <p className="text-sm mt-1">Make sure the backend server is running.</p>
        </div>
      </div>
    );
  }

  return (
    <div className="container mx-auto px-4 py-8">
      <div className="text-center mb-10">
        <h1 className="text-4xl font-bold text-gray-900 mb-3">DevOps Dojo</h1>
        <p className="text-lg text-gray-600 max-w-2xl mx-auto">
          Master DevOps concepts through interactive quizzes. Compete on the leaderboard
          and track your progress across topics.
        </p>
        <Link
          to="/leaderboard"
          className="inline-block mt-6 bg-gray-900 text-white px-6 py-3 rounded-lg hover:bg-gray-800 transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gray-900 focus-visible:ring-offset-2"
        >
          View Leaderboard →
        </Link>
      </div>

      {stats && stats.total_attempts > 0 && (
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-10 max-w-3xl mx-auto">
          {[
            { label: 'Quizzes Taken', value: stats.total_attempts },
            { label: 'Players', value: stats.unique_players },
            { label: 'Passed', value: stats.total_passed },
            { label: 'Topics', value: topics.length },
          ].map((item) => (
            <div key={item.label} className="bg-white rounded-lg shadow-sm border border-gray-100 text-center p-4">
              <p className="text-2xl font-bold text-blue-600">{item.value}</p>
              <p className="text-sm text-gray-500">{item.label}</p>
            </div>
          ))}
        </div>
      )}

      {recentActivity.length > 0 && (
        <div className="mb-10 max-w-3xl mx-auto">
          <div className="flex items-center justify-between mb-4">
            <h2 className="text-xl font-bold text-gray-900">Recent Activity</h2>
            <Link to="/leaderboard" className="text-sm text-blue-600 hover:underline">
              View all →
            </Link>
          </div>
          <div className="bg-white rounded-xl shadow-sm border border-gray-100 divide-y divide-gray-100">
            {recentActivity.map((entry) => (
              <div
                key={entry.id}
                className={`flex flex-wrap items-center justify-between gap-3 px-4 py-3 ${
                  currentPlayer &&
                  entry.player_name.toLowerCase() === currentPlayer.toLowerCase()
                    ? 'bg-blue-50'
                    : ''
                }`}
              >
                <div>
                  <p className="font-medium text-gray-900">
                    {entry.player_name}
                    <span className="text-gray-500 font-normal"> · {entry.topic_name}</span>
                  </p>
                  <p className="text-sm text-gray-500">{formatRelativeTime(entry.completed_at)}</p>
                </div>
                <div className="flex items-center gap-3 text-sm">
                  <span
                    className={`font-semibold ${
                      entry.passed ? 'text-green-600' : 'text-orange-600'
                    }`}
                  >
                    {entry.score}%
                  </span>
                  <span className="text-gray-500">{formatTime(entry.time_taken_seconds)}</span>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4 mb-6">
        <h2 className="text-2xl font-bold text-gray-900">Choose a Topic</h2>
        <div className="relative w-full sm:w-72">
          <input
            type="search"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search topics..."
            aria-label="Search topics"
            className="w-full border border-gray-300 rounded-lg px-4 py-2 pr-10 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
          />
          {searchLoading && (
            <div className="absolute right-3 top-1/2 -translate-y-1/2 h-4 w-4 rounded-full border-2 border-gray-200 border-t-blue-600 animate-spin" />
          )}
        </div>
      </div>

      {topics.length === 0 ? (
        <div className="bg-white rounded-xl border border-dashed border-gray-300 text-center py-12 px-6">
          {search.trim() ? (
            <>
              <p className="text-gray-600 mb-2">No topics match &ldquo;{search}&rdquo;.</p>
              <button
                type="button"
                onClick={() => setSearch('')}
                className="text-sm text-blue-600 hover:underline"
              >
                Clear search
              </button>
            </>
          ) : (
            <>
              <p className="text-gray-600 mb-2">No quiz topics available yet.</p>
              <p className="text-sm text-gray-400">Check back soon or add questions via Manage.</p>
            </>
          )}
        </div>
      ) : (
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
        {topics.map((topic) => (
          <div
            key={topic.id}
            className="bg-white rounded-xl shadow-sm border border-gray-100 p-6 hover:shadow-md hover:border-gray-200 transition-all flex flex-col"
          >
            <h3 className="text-xl font-bold mb-2 text-gray-900">{topic.title}</h3>
            <p className="text-gray-600 mb-4 flex-grow">{topic.description}</p>
            {topic.question_count != null && (
              <p className="text-sm text-gray-400 mb-4">
                {topic.question_count} questions available
              </p>
            )}
            <Link
              to={`/quiz/${topic.id}`}
              className="inline-block text-center bg-blue-600 text-white px-6 py-2 rounded-lg hover:bg-blue-700 transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-500 focus-visible:ring-offset-2"
            >
              Take Quiz
            </Link>
          </div>
        ))}
      </div>
      )}
    </div>
  );
}

export default Home;
